// indexer 包：MEME Token Launchpad Indexer 服务的核心索引器逻辑
// 本文件为区块链事件索引器的主要实现，负责：
// 1. 连接区块链 RPC 节点
// 2. 同步历史区块中的合约事件
// 3. 通过 WebSocket 实时监听新区块
// 4. 解析合约日志为结构化事件数据
// 5. 批量写入数据库
package indexer

// 导入所需的包
import (
	"context"  // 上下文包，用于控制 goroutine 生命周期
	"fmt"      // 格式化包，用于构建错误信息
	"math/big" // 大整数包，用于处理链上的 uint256 类型数值（超过 int64 范围）
	"strings"  // 字符串处理包，用于 ABI JSON 解析和错误信息匹配
	"time"     // 时间包，用于创建定时器和时间间隔计算

	// go-ethereum 是以太坊 Go 客户端库，提供与以太坊节点交互的能力
	"github.com/ethereum/go-ethereum"           // 以太坊过滤查询构建器，用于构建日志过滤条件
	"github.com/ethereum/go-ethereum/accounts/abi" // ABI 包，用于解析 Solidity 合约 ABI 并解码事件日志
	"github.com/ethereum/go-ethereum/common"    // 通用工具包，提供 Address、Hash 等以太坊基础类型
	"github.com/ethereum/go-ethereum/core/types" // 核心类型包，提供 Log、Header 等区块链数据结构

	// go-ethereum 的 ethclient 包，提供高级 HTTP/WS RPC 客户端
	"github.com/ethereum/go-ethereum/ethclient"

	// 项目内部包
	"github.com/meme-launchpad/indexer/internal/config"   // 配置包，提供 ChainConfig 等配置结构体
	"github.com/meme-launchpad/indexer/internal/database"  // 数据库包，提供 DB 连接和数据操作方法
	evtypes "github.com/meme-launchpad/indexer/internal/types" // 事件类型包，别名 evtypes 避免与 Go 内置 types 冲突

	"go.uber.org/zap" // zap 高性能结构化日志库
)

/*
 * 架构概览：
 * 本文件为 MEME Token Launchpad Indexer 服务的核心索引器逻辑。
 * Indexer 负责监听区块链上的智能合约事件，解析后将数据同步到数据库，供 API 服务查询。
 *
 * 架构说明：
 *   - 采用"历史同步 + 实时监听"双模式：
 *     1. syncHistoricalBlocks: 通过轮询方式同步历史区块中的事件（补偿/追块）
 *     2. watchNewBlocks: 通过 WebSocket 订阅新区块头，实现近实时通知
 *   - 动态批量大小：根据 RPC 节点响应自动调整每次查询的区块范围，
 *     在 limit exceeded 时减小批量，连续成功时逐步恢复
 *   - 事件分类处理：将合约日志按事件类型（TokenCreated/TokenBought/TokenSold/TokenGraduated）
 *     分类解析后批量写入数据库
 *
 * 并发模型：
 *   - Start() 启动两个 goroutine：一个负责历史同步，一个负责实时监听
 *   - stopCh 用于协调优雅停机，两个 goroutine 均监听 stopCh
 *   - 历史同步与实时监听独立运行，互不阻塞
 *
 * 数据库交互：
 *   - 使用 database.DB 封装的数据库操作（BatchInsert/Insert）
 *   - 每次同步完成后更新 last_synced_block，确保断点续传
 *
 * 错误处理策略：
 *   - RPC 连接失败：返回错误，由调用方决定是否重试
 *   - 历史同步中的临时错误：记录日志，继续下一轮轮询
 *   - 事件解析错误：跳过该日志，不影响同区块其他事件
 *   - limit exceeded：动态减小批量大小，自适应 RPC 节点限制
 */

// Indexer 区块链事件索引器结构体
// 封装了与区块链交互所需的全部状态与依赖
// 该结构体是整个索引器的核心，持有 RPC 客户端、数据库连接、配置、日志等资源
type Indexer struct {
	client           *ethclient.Client   // 以太坊 RPC 客户端，用于查询区块、过滤日志、获取链 ID 等
	db               *database.DB        // 数据库连接实例，用于持久化事件数据到 PostgreSQL
	cfg              *config.ChainConfig // 链配置指针，包含 RPC、WSS、合约地址、起始区块、批量大小等
	logger           *zap.Logger         // zap 结构化日志记录器，用于记录运行状态和错误信息
	contractAddress  common.Address      // MEMECore 合约地址，用于过滤只属于该合约的日志
	contractABI      abi.ABI             // 合约 ABI 解析结果，用于将原始日志数据解码为结构化事件
	stopCh           chan struct{}       // 停机信号通道，关闭该通道会通知所有 goroutine 停止工作
	currentBatchSize uint64              // 动态调整的批量大小（区块数），根据 RPC 响应自适应
	// 初始值为配置中的 BlockBatchSize，遇到 limit exceeded 时减半（最低 10），连续成功 10 次后翻倍（最高不超过配置值）
}

// New 创建索引器实例的工厂函数
// 参数：
//   - cfg: 链配置指针，包含 RPC 地址、WSS 地址、链 ID、合约地址、起始区块、批量大小等
//   - db: 数据库连接实例指针，用于事件数据持久化
//   - logger: zap 日志记录器指针，用于记录运行日志
// 返回：
//   - *Indexer: 成功时返回索引器实例指针
//   - error: 初始化失败时返回错误（RPC 连接失败、链 ID 不匹配、ABI 解析失败）
// 初始化流程：
//   1. 通过 ethclient.Dial 连接 RPC 节点，建立 HTTP 连接
//   2. 验证链 ID，确保连接的是正确的区块链网络（防止连错网络导致数据错误）
//   3. 解析合约 ABI（MEMECoreABI 为内嵌常量），用于后续事件日志解码
//   4. 初始化 stopCh（停机信号通道）与 currentBatchSize（动态批量大小）
// 错误处理：
//   - RPC 连接失败：返回 fmt.Errorf("failed to connect to RPC: ...")
//   - 链 ID 不匹配：返回 fmt.Errorf("chain ID mismatch: ...")
//   - ABI 解析失败：返回 fmt.Errorf("failed to parse ABI: ...")
func New(cfg *config.ChainConfig, db *database.DB, logger *zap.Logger) (*Indexer, error) {
	// 连接以太坊 RPC 节点
	// ethclient.Dial 创建一个 HTTP/HTTPS 客户端连接到指定的 RPC URL
	// 支持普通 HTTP 和 HTTPS 连接，不支持 WebSocket（WebSocket 需要单独创建客户端）
	client, err := ethclient.Dial(cfg.RPC) // cfg.RPC 如 "https://bsc-dataseed.binance.org"
	if err != nil {
		// RPC 连接失败，包装错误返回
		// 常见原因：URL 格式错误、网络不通、节点离线
		return nil, fmt.Errorf("failed to connect to RPC: %w", err)
	}

	// 获取链 ID 用于验证连接的网络是否正确
	// 调用 eth_chainId JSON-RPC 方法获取当前连接网络的链 ID
	chainID, err := client.ChainID(context.Background()) // 使用 Background 上下文，因为此时还没有创建业务上下文
	if err != nil {
		// 获取链 ID 失败，可能 RPC 节点响应异常
		return nil, fmt.Errorf("failed to get chain ID: %w", err)
	}

	// 验证链 ID 是否与配置匹配
	// 防止意外连接到错误的网络（如连到测试网而配置是主网）
	// 链 ID 不匹配会导致解析出的事件数据全部错误，必须严格检查
	if chainID.Int64() != cfg.ChainID {
		return nil, fmt.Errorf("chain ID mismatch: expected %d, got %d", cfg.ChainID, chainID.Int64())
	}

	// 解析合约 ABI JSON 字符串为 abi.ABI 结构体
	// MEMECoreABI 是在 abi.go 文件中定义的常量，包含合约的事件定义
	// 解析后的 ABI 用于后续通过 Topics[0] 匹配事件类型，以及 UnpackIntoInterface 解码日志数据
	contractABI, err := abi.JSON(strings.NewReader(MEMECoreABI)) // 从字符串读取器创建 ABI
	if err != nil {
		// ABI 解析失败，通常是 JSON 格式错误
		// 这是编译期就应该避免的问题，运行时出现说明 ABI 常量定义有误
		return nil, fmt.Errorf("failed to parse ABI: %w", err)
	}

	// 记录索引器初始化成功信息
	// 包含链名称、链 ID 和合约地址，便于运维确认配置是否正确
	logger.Info("Indexer initialized",
		zap.String("chain", cfg.Name),           // 区块链网络名称，如 "BSC"
		zap.Int64("chainID", cfg.ChainID),       // 链 ID，如 56（BSC 主网）
		zap.String("contract", cfg.CoreContract), // 合约地址，如 "0x1234..."
	)

	// 返回初始化完成的 Indexer 实例
	return &Indexer{
		client:           client,                                // RPC 客户端，用于后续查询区块和过滤日志
		db:               db,                                    // 数据库连接，用于持久化事件数据
		cfg:              cfg,                                   // 链配置，保存供后续方法使用
		logger:           logger,                                // 日志记录器，保存供后续方法使用
		contractAddress:  common.HexToAddress(cfg.CoreContract), // 将合约地址字符串转换为 common.Address 类型
		contractABI:      contractABI,                           // 解析后的合约 ABI，用于事件解码
		stopCh:           make(chan struct{}),                   // 创建停机信号通道，使用无缓冲通道确保信号可靠传递
		currentBatchSize: uint64(cfg.BlockBatchSize),            // 初始批量大小取配置值，后续会动态调整
	}, nil
}

// Start 启动索引器，开始同步区块链事件
// 参数：
//   - ctx: 上下文，用于控制索引器生命周期（通过 ctx.Done() 通知停机）
// 返回：
//   - error: 获取最后同步区块号失败时返回错误
// 启动流程：
//   1. 从数据库获取最后同步的区块号（实现断点续传）
//   2. 计算起始区块号（配置起始区块 vs 最后同步区块+1 取较大值）
//   3. 启动历史区块同步 goroutine（syncHistoricalBlocks），轮询同步历史事件
//   4. 启动实时区块监听 goroutine（watchNewBlocks），WebSocket 订阅新区块头
// 并发说明：
//   - 两个 goroutine 独立运行，均监听 ctx.Done() 和 stopCh
//   - 历史同步完成后会持续轮询新区块，与实时监听形成互补
//   - 实时监听主要用于快速感知新区块，实际数据仍由历史同步拉取
func (idx *Indexer) Start(ctx context.Context) error {
	// 记录索引器启动日志
	idx.logger.Info("Starting indexer...")

	// 从数据库查询该合约最后同步的区块号
	// 合约地址转为小写是为了与数据库中存储的小写地址匹配（以太坊地址大小写不敏感）
	// 这个值用于实现"断点续传"：索引器重启后从上次停止的区块继续同步
	lastBlock, err := idx.db.GetLastSyncedBlock(ctx, strings.ToLower(idx.cfg.CoreContract))
	if err != nil {
		// 查询失败，返回错误
		// 原因：数据库连接异常或 indexer_state 表不存在
		return fmt.Errorf("failed to get last synced block: %w", err)
	}

	// 确定起始同步区块号
	// 默认使用配置中的 StartBlock
	startBlock := idx.cfg.StartBlock

	// 如果数据库中有同步记录（lastBlock > 0），则从上次同步位置 +1 继续
	// 取较大值确保不会遗漏区块（配置起始区块可能早于数据库记录）
	if lastBlock > 0 {
		startBlock = lastBlock + 1 // +1 是因为 lastBlock 已经同步过，需要从下一个区块开始
	}

	// 记录起始同步区块号
	idx.logger.Info("Starting sync from block", zap.Uint64("startBlock", startBlock))

	// 启动历史区块同步 goroutine
	// 该 goroutine 以轮询方式按 PollInterval 周期查询新区块并同步事件
	// 传入 ctx 用于接收停机信号，startBlock 指定从哪个区块开始同步
	go idx.syncHistoricalBlocks(ctx, startBlock)

	// 启动实时区块监听 goroutine
	// 该 goroutine 通过 WebSocket 订阅新区块头，实现近实时感知新区块
	// 传入 ctx 用于接收停机信号
	go idx.watchNewBlocks(ctx)

	// 启动成功，返回 nil
	return nil
}

// Stop 停止索引器，执行优雅停机
// 执行流程：
//   1. 关闭 stopCh 通道，通知所有 goroutine 停止工作
//   2. 关闭 RPC 客户端连接，释放网络资源
//   3. 记录停机日志
// 注意：
//   - 关闭 stopCh 后，goroutine 会在下一次 select 时退出
//   - 不会等待正在进行的同步完成，如需优雅停机应在调用前设置 ctx 超时
func (idx *Indexer) Stop() {
	// 关闭 stopCh 通道
	// close 会使得所有从 stopCh 读取的 goroutine 收到零值并退出
	// 这是 Go 中广播停机信号的惯用方式（向多个 goroutine 同时发送信号）
	close(idx.stopCh)

	// 关闭以太坊 RPC 客户端连接
	// 释放底层 HTTP 连接和资源
	idx.client.Close()

	// 记录索引器停机日志
	idx.logger.Info("Indexer stopped")
}

// syncHistoricalBlocks 同步历史区块事件（核心同步逻辑）
// 参数：
//   - ctx: 上下文，用于接收停机信号
//   - startBlock: 起始区块号（含），从该区块开始同步
// 执行流程（轮询循环）：
//   1. 创建定时器，按 PollInterval 周期触发
//   2. 每次触发时获取最新区块号
//   3. 计算本次同步的区块范围 [currentBlock, toBlock]
//   4. 调用 syncBlockRange 同步该范围内的合约事件
//   5. 成功后更新 last_synced_block 到数据库
//   6. 根据成功/失败情况动态调整 batch size
// 动态批量大小策略：
//   - 遇到 limit exceeded 错误：批量大小减半，最低不低于 10
//     原因：RPC 节点对单次查询返回的数据量有限制，批量太大会被拒绝
//   - 连续成功 10 次：批量大小翻倍，最高不超过配置值
//     原因：批量越大同步效率越高，但需要在 RPC 限制范围内
// 错误处理：
//   - 获取最新区块号失败：记录错误日志，跳过本轮（下一轮重试）
//   - syncBlockRange 失败（非 limit exceeded）：记录错误日志，跳过本轮
//   - 更新 last_synced_block 失败：记录错误日志，不影响下一轮
// 并发安全：
//   - currentBatchSize 被单个 goroutine 访问，无需加锁
//   - 数据库操作通过 database.DB 封装，内部使用连接池
func (idx *Indexer) syncHistoricalBlocks(ctx context.Context, startBlock uint64) {
	// 创建定时器，按配置的轮询间隔（PollInterval 秒）周期触发
	// 每次触发表示可以尝试同步新区块
	ticker := time.NewTicker(time.Duration(idx.cfg.PollInterval) * time.Second)

	// 确保函数退出时停止定时器，释放资源
	// Stop 会停止定时器发送后续 tick
	defer ticker.Stop()

	// 当前待同步的区块号，初始值为 startBlock
	// 每次成功同步后更新为 toBlock + 1
	currentBlock := startBlock

	// 连续成功计数器，用于动态调整批量大小
	// 当连续成功 10 次时，将批量大小翻倍
	consecutiveSuccesses := 0

	// 主循环：通过 select 监听多个通道
	for {
		select {
		case <-ctx.Done():
			// 上下文被取消（通常是因为收到系统退出信号）
			// 退出当前 goroutine，停止历史同步
			return

		case <-idx.stopCh:
			// stopCh 被关闭（调用 Stop() 方法时触发）
			// 退出当前 goroutine，停止历史同步
			return

		case <-ticker.C:
			// 定时器触发，到达轮询间隔
			// 开始尝试同步新区块

			// 获取区块链最新区块号
			// 调用 eth_blockNumber JSON-RPC 方法
			latestBlock, err := idx.client.BlockNumber(ctx)
			if err != nil {
				// 获取最新区块号失败，记录错误日志
				// 常见原因：RPC 节点临时不可用、网络超时
				// 不返回错误，继续等待下一轮轮询
				idx.logger.Error("Failed to get latest block number", zap.Error(err))
				continue // 跳过本轮，等待下一次定时器触发
			}

			// 如果当前待同步区块已经超过最新区块，说明已经追上链头
			// 不需要同步，等待下一轮检查是否有新区块
			if currentBlock > latestBlock {
				continue
			}

			// 计算本次同步的结束区块号
			// 使用动态批量大小：从 currentBlock 开始，一次同步 currentBatchSize 个区块
			// -1 是因为范围包含两端：[currentBlock, currentBlock + batchSize - 1]
			toBlock := currentBlock + idx.currentBatchSize - 1
			// 如果计算出的结束区块超过最新区块，截断到最新区块
			// 避免查询不存在的区块号
			if toBlock > latestBlock {
				toBlock = latestBlock
			}

			// 调用 syncBlockRange 同步指定区块范围内的合约事件
			if err := idx.syncBlockRange(ctx, currentBlock, toBlock); err != nil {
				// 同步失败，检查错误类型

				// 检查是否是 RPC 节点返回的 "limit exceeded" 或 "query returned more than" 错误
				// 这类错误表示单次查询返回的数据量超过 RPC 节点限制
				if strings.Contains(err.Error(), "limit exceeded") || strings.Contains(err.Error(), "query returned more than") {
					// 减小批量大小：将当前批量大小减半
					idx.currentBatchSize = idx.currentBatchSize / 2
					// 设置批量大小下限为 10，避免批量过小导致同步效率过低
					if idx.currentBatchSize < 10 {
						idx.currentBatchSize = 10
					}
					// 记录批量大小调整的警告日志
					idx.logger.Warn("Reducing batch size due to limit exceeded",
						zap.Uint64("newBatchSize", idx.currentBatchSize),
					)
					// 重置连续成功计数器，因为本次同步失败
					consecutiveSuccesses = 0
					// 跳过本轮，不更新 currentBlock，下一轮用更小的批量重试
					continue
				}

				// 非 limit exceeded 类型的错误（如网络超时、RPC 内部错误等）
				// 记录错误日志，但不调整批量大小
				idx.logger.Error("Failed to sync block range",
					zap.Uint64("from", currentBlock), // 起始区块号
					zap.Uint64("to", toBlock),         // 结束区块号
					zap.Error(err),                    // 错误详情
				)
				// 跳过本轮，不更新 currentBlock，下一轮重试
				continue
			}

			// 同步成功后，尝试恢复批量大小
			// 递增连续成功计数器
			consecutiveSuccesses++
			// 当连续成功 10 次且当前批量大小小于配置值时，将批量大小翻倍
			// 这是一种"慢启动"策略，避免批量大小恢复过快导致再次触发 limit exceeded
			if consecutiveSuccesses >= 10 && idx.currentBatchSize < uint64(idx.cfg.BlockBatchSize) {
				idx.currentBatchSize = idx.currentBatchSize * 2 // 批量大小翻倍
				// 如果翻倍后超过配置的最大批量大小，截断到配置值
				if idx.currentBatchSize > uint64(idx.cfg.BlockBatchSize) {
					idx.currentBatchSize = uint64(idx.cfg.BlockBatchSize)
				}
				// 记录批量大小增加的信息日志
				idx.logger.Info("Increasing batch size", zap.Uint64("newBatchSize", idx.currentBatchSize))
				// 重置连续成功计数器，开始新一轮计数
				consecutiveSuccesses = 0
			}

			// 更新数据库中的最后同步区块号
			// 合约地址转为小写以匹配数据库中的记录
			// 使用 UPSERT（INSERT ON CONFLICT DO UPDATE）确保记录存在时更新而非报错
			if err := idx.db.UpdateLastSyncedBlock(ctx, strings.ToLower(idx.cfg.CoreContract), toBlock); err != nil {
				// 更新失败只记录错误日志，不影响同步流程
				// 下次同步会重新从 currentBlock 开始（因为没有更新 last_synced_block）
				// 这意味着可能会有少量重复事件，但数据库的 ON CONFLICT DO NOTHING 保证幂等性
				idx.logger.Error("Failed to update last synced block", zap.Error(err))
			}

			// 记录同步成功的信息日志
			idx.logger.Info("Synced blocks",
				zap.Uint64("from", currentBlock),    // 本次同步的起始区块
				zap.Uint64("to", toBlock),            // 本次同步的结束区块
				zap.Uint64("latest", latestBlock),    // 链上最新区块号（用于判断同步进度）
				zap.Uint64("batchSize", idx.currentBatchSize), // 当前批量大小（用于监控动态调整效果）
			)

			// 更新当前待同步区块号为本次结束区块 + 1
			// 下次轮询将从 toBlock + 1 开始
			currentBlock = toBlock + 1
		}
	}
}

// watchNewBlocks 通过 WebSocket 监听新区块头（实时监听）
// 该方法创建独立的 WebSocket 连接订阅新区块头通知
// 参数：
//   - ctx: 上下文，用于接收停机信号
// 执行流程：
//   1. 检查 WSS 配置是否为空，为空则跳过（降级为纯轮询模式）
//   2. 使用独立 WebSocket 客户端连接 WSS 节点
//   3. 订阅 NewHead（新区块头）通知
//   4. 在 headers 通道上持续接收新区块头
//   5. 记录新区块到达日志（Debug 级别）
// 注意：
//   - 当前实现仅记录新区块到达，实际事件拉取仍由 syncHistoricalBlocks 完成
//     原因：WebSocket 订阅只能获取区块头，无法直接获取合约事件
//     但新区块到达通知可以作为 syncHistoricalBlocks 轮询的补充，加快感知速度
//   - WebSocket 连接独立于 HTTP RPC 连接，避免互相影响
//   - 订阅错误时会退出 goroutine，不会自动重连（可以后续优化）
// 资源管理：
//   - wsClient 和 sub 均在函数退出时关闭/取消订阅（defer）
//   - headers 通道由 go-ethereum 内部管理，无需手动关闭
func (idx *Indexer) watchNewBlocks(ctx context.Context) {
	// 检查 WebSocket 配置是否存在
	// 如果未配置 WSS 地址，无法使用 WebSocket 订阅，记录警告并跳过
	if idx.cfg.WSS == "" {
		idx.logger.Warn("WSS not configured, skipping real-time subscription")
		return // 直接退出 goroutine，降级为纯轮询模式
	}

	// 创建独立的 WebSocket 客户端连接
	// 与 HTTP RPC 客户端分开，避免 WebSocket 长连接影响 HTTP 请求
	// ethclient.Dial 同时支持 HTTP 和 WebSocket URL（根据 URL scheme 自动判断）
	wsClient, err := ethclient.Dial(idx.cfg.WSS) // cfg.WSS 如 "wss://bsc-ws-node.example.com"
	if err != nil {
		// WebSocket 连接失败，记录错误日志
		// 注意：这里不返回错误给调用方，仅记录日志后退出 goroutine
		// 因为实时监听是辅助功能，失败不影响核心的历史同步
		idx.logger.Error("Failed to connect to WebSocket", zap.Error(err))
		return
	}
	// 确保函数退出时关闭 WebSocket 连接，释放资源
	defer wsClient.Close()

	// 创建新区块头接收通道
	// go-ethereum 会将订阅到的新区块头写入该通道
	headers := make(chan *types.Header)

	// 订阅新区块头通知
	// SubscribeNewHead 内部调用 eth_subscribe JSON-RPC 方法，订阅 "newHeads" 事件
	// 返回 Subscription 对象，用于管理订阅生命周期
	sub, err := wsClient.SubscribeNewHead(ctx, headers)
	if err != nil {
		// 订阅失败，记录错误日志
		// 可能原因：WebSocket 连接不支持订阅、节点不支持该功能
		idx.logger.Error("Failed to subscribe to new heads", zap.Error(err))
		return
	}
	// 确保函数退出时取消订阅，释放服务端资源
	defer sub.Unsubscribe()

	// 记录 WebSocket 订阅成功信息
	idx.logger.Info("Subscribed to new block headers via WebSocket")

	// 主循环：监听多个通道
	for {
		select {
		case <-ctx.Done():
			// 上下文被取消（收到停机信号）
			// 退出当前 goroutine
			return

		case <-idx.stopCh:
			// stopCh 被关闭（调用 Stop() 方法时触发）
			// 退出当前 goroutine
			return

		case err := <-sub.Err():
			// 订阅通道出现错误
			// 可能原因：WebSocket 连接断开、节点重启
			// 记录错误日志后退出 goroutine
			idx.logger.Error("WebSocket subscription error", zap.Error(err))
			return

		case header := <-headers:
			// 收到新区块头通知
			// header 包含区块号、时间戳、父哈希等基础信息
			// 使用 Debug 级别记录，避免在高频出块的链上产生过多日志
			idx.logger.Debug("New block received", zap.Uint64("block", header.Number.Uint64()))
		}
	}
}

// syncBlockRange 同步指定区块范围内的合约事件
// 这是事件同步的核心方法，负责从区块链获取日志并分类解析写入数据库
// 参数：
//   - ctx: 上下文，用于传递取消信号
//   - fromBlock: 起始区块号（含）
//   - toBlock: 结束区块号（含）
// 返回：
//   - error: 过滤日志失败时返回错误（触发上层批量大小调整）；其他错误仅记录日志
// 执行流程：
//   1. 构建 FilterQuery，指定区块范围与合约地址
//   2. 调用 FilterLogs 获取该范围内的所有合约日志
//   3. 遍历日志，获取区块时间戳（带缓存，同一区块只查询一次 RPC）
//   4. 按事件类型分类解析：
//      - TokenCreated: 代币创建事件
//      - TokenBought: 代币购买事件
//      - TokenSold: 代币卖出事件
//      - TokenGraduated: 代币毕业事件（达到目标，迁移到 DEX）
//   5. 批量写入数据库（不同事件类型分开批量插入）
// 性能优化：
//   - blockTimestamps 缓存：同一区块的多个日志共享时间戳，避免重复 RPC 查询
//   - 批量插入：TokenCreated/Bought/Sold 使用批量插入，减少数据库往返次数
//   - TokenGraduated 事件较少，采用单条插入
// 错误处理：
//   - FilterLogs 失败：返回错误，触发上层批量大小调整
//   - 单个日志解析失败：记录错误，跳过该日志，继续处理其他日志
//   - 数据库批量插入失败：记录错误，但不中断处理（部分成功）
func (idx *Indexer) syncBlockRange(ctx context.Context, fromBlock, toBlock uint64) error {
	// 构建以太坊日志过滤查询
	// FilterQuery 指定了查询的区块范围和合约地址
	query := ethereum.FilterQuery{
		FromBlock: big.NewInt(int64(fromBlock)), // 起始区块号，需要转换为 *big.Int 类型
		ToBlock:   big.NewInt(int64(toBlock)),   // 结束区块号，需要转换为 *big.Int 类型
		Addresses: []common.Address{idx.contractAddress}, // 只查询 MEMECore 合约的日志
		// 不设置 Topics 过滤条件，因为我们需要所有类型的事件
		// 事件类型区分在后续的 switch 语句中通过 Topics[0] 判断
	}

	// 调用 eth_getLogs JSON-RPC 方法获取过滤后的日志
	// 返回的 logs 是原始的以太坊日志数组，包含 Topics 和 Data 两部分数据
	logs, err := idx.client.FilterLogs(ctx, query)
	if err != nil {
		// 日志过滤失败，返回错误
		// 上层 syncHistoricalBlocks 会根据错误类型决定是否调整批量大小
		return fmt.Errorf("failed to filter logs: %w", err)
	}

	// 如果没有日志，直接返回 nil（空结果不是错误）
	if len(logs) == 0 {
		return nil
	}

	// 记录找到的日志数量
	idx.logger.Info("Found logs", zap.Int("count", len(logs)))

	// 创建区块时间戳缓存
	// key: 区块号, value: 该区块的 Unix 时间戳（秒）
	// 同一个区块中可能有多条日志，使用缓存避免对同一区块重复调用 BlockByNumber
	// RPC 调用是昂贵的网络操作，缓存可以显著减少请求数量
	blockTimestamps := make(map[uint64]uint64)

	// 声明四种事件类型的切片，用于收集分类后的事件
	var tokenCreatedEvents []*evtypes.TokenCreatedEvent     // 代币创建事件列表
	var tokenBoughtEvents []*evtypes.TokenBoughtEvent       // 代币购买事件列表
	var tokenSoldEvents []*evtypes.TokenSoldEvent           // 代币卖出事件列表
	var tokenGraduatedEvents []*evtypes.TokenGraduatedEvent // 代币毕业事件列表

	// 遍历所有日志，按事件类型分类解析
	for _, vLog := range logs {
		// 获取当前日志所在区块的时间戳
		// 先从缓存中查找，避免重复的 RPC 调用
		timestamp, ok := blockTimestamps[vLog.BlockNumber]
		if !ok {
			// 缓存未命中，需要通过 RPC 查询区块信息
			// 调用 eth_getBlockByNumber 获取完整区块数据
			block, err := idx.client.BlockByNumber(ctx, big.NewInt(int64(vLog.BlockNumber)))
			if err != nil {
				// 获取区块信息失败，记录错误并跳过该日志
				// 不返回错误，因为其他日志可能不受影响
				idx.logger.Error("Failed to get block", zap.Uint64("block", vLog.BlockNumber), zap.Error(err))
				continue // 跳过该日志，继续处理下一条
			}
			// 从区块头中提取 Unix 时间戳
			timestamp = block.Time()
			// 将时间戳存入缓存，后续同区块的日志可以直接使用
			blockTimestamps[vLog.BlockNumber] = timestamp
		}

		// 解析事件：通过 Topics[0]（事件签名哈希）匹配对应的事件类型
		// 在 Solidity 中，每个事件都有一个唯一的签名哈希（keccak256 哈希）
		// Topics[0] 存储的就是这个哈希值，可以用来区分不同类型的事件
		switch vLog.Topics[0] {
		case idx.contractABI.Events["TokenCreated"].ID:
			// 匹配到 TokenCreated 事件
			// 调用专门的解析函数解码日志数据
			event, err := idx.parseTokenCreatedEvent(vLog, timestamp)
			if err != nil {
				// 解析失败，记录错误并跳过该日志
				// 可能原因：日志数据格式不匹配、ABI 定义错误
				idx.logger.Error("Failed to parse TokenCreated event", zap.Error(err))
				continue
			}
			// 将解析成功的事件添加到对应列表
			tokenCreatedEvents = append(tokenCreatedEvents, event)
			// 记录 TokenCreated 事件的关键信息（Info 级别，因为创建事件较少且重要）
			idx.logger.Info("TokenCreated event",
				zap.String("token", event.TokenAddress),   // 代币合约地址
				zap.String("creator", event.CreatorAddress), // 创建者钱包地址
				zap.String("name", event.Name),             // 代币名称
				zap.String("symbol", event.Symbol),         // 代币符号
			)

		case idx.contractABI.Events["TokenBought"].ID:
			// 匹配到 TokenBought 事件（代币购买）
			event, err := idx.parseTokenBoughtEvent(vLog, timestamp)
			if err != nil {
				// 解析失败，记录错误并跳过
				idx.logger.Error("Failed to parse TokenBought event", zap.Error(err))
				continue
			}
			// 将解析成功的事件添加到购买事件列表
			tokenBoughtEvents = append(tokenBoughtEvents, event)
			// 记录 TokenBought 事件的关键信息（Debug 级别，因为购买事件频繁）
			idx.logger.Debug("TokenBought event",
				zap.String("token", event.TokenAddress),       // 代币合约地址
				zap.String("buyer", event.BuyerAddress),       // 买家钱包地址
				zap.String("bnbAmount", event.BnbAmount.String()), // 花费的 BNB 数量
			)

		case idx.contractABI.Events["TokenSold"].ID:
			// 匹配到 TokenSold 事件（代币卖出）
			event, err := idx.parseTokenSoldEvent(vLog, timestamp)
			if err != nil {
				// 解析失败，记录错误并跳过
				idx.logger.Error("Failed to parse TokenSold event", zap.Error(err))
				continue
			}
			// 将解析成功的事件添加到卖出事件列表
			tokenSoldEvents = append(tokenSoldEvents, event)
			// 记录 TokenSold 事件的关键信息（Debug 级别，因为卖出事件频繁）
			idx.logger.Debug("TokenSold event",
				zap.String("token", event.TokenAddress),           // 代币合约地址
				zap.String("seller", event.SellerAddress),         // 卖家钱包地址
				zap.String("tokenAmount", event.TokenAmount.String()), // 卖出的代币数量
			)

		case idx.contractABI.Events["TokenGraduated"].ID:
			// 匹配到 TokenGraduated 事件（代币毕业）
			// 代币毕业意味着内盘募资达标，自动迁移到 DEX
			event, err := idx.parseTokenGraduatedEvent(vLog, timestamp)
			if err != nil {
				// 解析失败，记录错误并跳过
				idx.logger.Error("Failed to parse TokenGraduated event", zap.Error(err))
				continue
			}
			// 将解析成功的事件添加到毕业事件列表
			tokenGraduatedEvents = append(tokenGraduatedEvents, event)
			// 记录 TokenGraduated 事件的关键信息（Info 级别，因为毕业事件较少且重要）
			idx.logger.Info("TokenGraduated event",
				zap.String("token", event.TokenAddress),                 // 代币合约地址
				zap.String("liquidityBNB", event.LiquidityBNB.String()), // 注入 DEX 的 BNB 流动性数量
			)
		}
	}

	// 批量写入数据库：将分类后的事件列表分别插入对应的数据库表
	// 使用批量插入提高吞吐量，减少数据库往返次数
	// 每种事件的批量插入失败只记录错误日志，不中断其他类型事件的处理
	// 这保证了"部分成功"：即使某类事件插入失败，其他类型的事件仍然能被持久化

	// 批量插入 TokenCreated 事件
	if err := idx.db.BatchInsertTokenCreatedEvents(ctx, tokenCreatedEvents); err != nil {
		idx.logger.Error("Failed to insert TokenCreated events", zap.Error(err))
	}
	// 批量插入 TokenBought 事件
	if err := idx.db.BatchInsertTokenBoughtEvents(ctx, tokenBoughtEvents); err != nil {
		idx.logger.Error("Failed to insert TokenBought events", zap.Error(err))
	}
	// 批量插入 TokenSold 事件
	if err := idx.db.BatchInsertTokenSoldEvents(ctx, tokenSoldEvents); err != nil {
		idx.logger.Error("Failed to insert TokenSold events", zap.Error(err))
	}

	// TokenGraduated 事件较少发生，使用逐条插入而非批量插入
	// 原因：毕业事件非常稀少（相对于买卖事件），逐条插入的开销可以忽略
	for _, event := range tokenGraduatedEvents {
		if err := idx.db.InsertTokenGraduatedEvent(ctx, event); err != nil {
			idx.logger.Error("Failed to insert TokenGraduated event", zap.Error(err))
		}
	}

	// 所有事件处理完成，返回 nil 表示成功
	return nil
}

// parseTokenCreatedEvent 解析 TokenCreated 事件日志
// 事件定义（Solidity）：
//   event TokenCreated(address indexed token, address indexed creator, string name, string symbol, uint256 totalSupply, bytes32 requestId)
// 参数：
//   - vLog: 以太坊原始日志对象，包含 Topics（索引参数）和 Data（非索引参数）
//   - timestamp: 区块时间戳（Unix 秒级），由上层缓存提供
// 返回：
//   - *evtypes.TokenCreatedEvent: 解析后的事件结构体指针
//   - error: ABI 解码失败时返回错误
// 解析规则：
//   - Topics[0]: 事件签名哈希（已在 switch 中匹配）
//   - Topics[1]: indexed token 地址（32 字节，取后 20 字节为实际地址）
//   - Topics[2]: indexed creator 地址（32 字节，取后 20 字节为实际地址）
//   - Data: ABI 编码的非 indexed 参数，包含 name, symbol, totalSupply, requestId
func (idx *Indexer) parseTokenCreatedEvent(vLog types.Log, timestamp uint64) (*evtypes.TokenCreatedEvent, error) {
	// 定义用于接收 ABI 解码结果的匿名结构体
	// 字段名必须与 Solidity 事件中的参数名完全一致（区分大小写）
	// 只有非 indexed 的参数才会出现在 Data 中，需要通过 UnpackIntoInterface 解码
	// indexed 参数需要从 Topics 中手动提取
	event := struct {
		Name        string   // 代币名称，如 "Pepe Coin"
		Symbol      string   // 代币符号，如 "PEPE"
		TotalSupply *big.Int // 总供应量，使用 *big.Int 因为 uint256 超过 int64 范围
		RequestId   [32]byte // 请求 ID，bytes32 类型，用于关联前端的创建请求
	}{}

	// 使用 ABI 解码 Data 部分的非 indexed 参数
	// UnpackIntoInterface 将 vLog.Data（ABI 编码的字节流）解码到 event 结构体
	// "TokenCreated" 是事件名称，用于从 ABI 中查找对应的事件定义
	if err := idx.contractABI.UnpackIntoInterface(&event, "TokenCreated", vLog.Data); err != nil {
		// 解码失败，返回错误
		// 可能原因：日志数据与 ABI 定义不匹配
		return nil, err
	}

	// 构建并返回解析后的事件结构体
	return &evtypes.TokenCreatedEvent{
		// 从 Topics 中提取 indexed 参数
		// Topics[1] 是 token 地址（32 字节），common.BytesToAddress 取后 20 字节转换为地址
		TokenAddress:    common.BytesToAddress(vLog.Topics[1].Bytes()).Hex(),
		// Topics[2] 是 creator 地址，同样取后 20 字节
		CreatorAddress:  common.BytesToAddress(vLog.Topics[2].Bytes()).Hex(),
		// 从解码后的 Data 中获取非 indexed 参数
		Name:            event.Name,         // 代币名称
		Symbol:          event.Symbol,       // 代币符号
		TotalSupply:     event.TotalSupply,  // 总供应量
		// 将 bytes32 转换为十六进制哈希字符串
		RequestID:       common.BytesToHash(event.RequestId[:]).Hex(),
		// 从日志对象中提取交易级元数据
		TransactionHash: vLog.TxHash.Hex(),   // 交易哈希，用于唯一标识这笔交易
		BlockNumber:     vLog.BlockNumber,    // 区块号，用于排序和查询
		BlockTimestamp:  timestamp,            // 区块时间戳，用于时间范围查询
		LogIndex:        vLog.Index,           // 日志在区块内的索引，配合交易哈希保证唯一性
	}, nil
}

// parseTokenBoughtEvent 解析 TokenBought 事件日志
// 事件定义（Solidity）：
//   event TokenBought(address indexed token, address indexed buyer, uint256 bnbAmount, uint256 tokenAmount,
//                     uint256 tradingFee, uint256 virtualBNBReserve, uint256 virtualTokenReserve,
//                     uint256 availableTokens, uint256 collectedBNB)
// 参数：
//   - vLog: 以太坊原始日志对象
//   - timestamp: 区块时间戳
// 返回：
//   - *evtypes.TokenBoughtEvent: 解析后的事件结构体指针
//   - error: ABI 解码失败时返回错误
// 解析规则：
//   - Topics[1]: indexed token 地址
//   - Topics[2]: indexed buyer 地址
//   - Data: ABI 编码的非 indexed 参数（bnbAmount, tokenAmount, tradingFee 等）
// 业务含义：
//   - TokenBought 表示用户用 BNB 购买了代币
//   - virtualBNBReserve/virtualTokenReserve: AMM 虚拟储备量，用于计算价格
//   - availableTokens: 内盘剩余可购买代币数量
//   - collectedBNB: 该代币累计收集的 BNB 数量
func (idx *Indexer) parseTokenBoughtEvent(vLog types.Log, timestamp uint64) (*evtypes.TokenBoughtEvent, error) {
	// 定义用于接收 ABI 解码结果的匿名结构体
	// 所有字段都是非 indexed 参数，从 Data 中解码
	event := struct {
		BnbAmount           *big.Int // 花费的 BNB 数量（含手续费）
		TokenAmount         *big.Int // 获得的代币数量
		TradingFee          *big.Int // 交易手续费（以 BNB 计）
		VirtualBNBReserve   *big.Int // AMM 虚拟 BNB 储备量，反映当前价格
		VirtualTokenReserve *big.Int // AMM 虚拟代币储备量，反映当前价格
		AvailableTokens     *big.Int // 内盘剩余可购买代币数量
		CollectedBNB        *big.Int // 该代币累计收集的 BNB 数量
	}{}

	// 使用 ABI 解码 Data 部分
	if err := idx.contractABI.UnpackIntoInterface(&event, "TokenBought", vLog.Data); err != nil {
		// 解码失败，返回错误
		return nil, err
	}

	// 构建并返回解析后的事件结构体
	return &evtypes.TokenBoughtEvent{
		// 从 Topics 中提取 indexed 参数
		TokenAddress:        common.BytesToAddress(vLog.Topics[1].Bytes()).Hex(), // 代币合约地址
		BuyerAddress:        common.BytesToAddress(vLog.Topics[2].Bytes()).Hex(), // 买家钱包地址
		// 从解码后的 Data 中获取非 indexed 参数
		BnbAmount:           event.BnbAmount,           // 花费的 BNB 数量
		TokenAmount:         event.TokenAmount,         // 获得的代币数量
		TradingFee:          event.TradingFee,          // 交易手续费
		VirtualBNBReserve:   event.VirtualBNBReserve,   // 虚拟 BNB 储备
		VirtualTokenReserve: event.VirtualTokenReserve, // 虚拟代币储备
		AvailableTokens:     event.AvailableTokens,     // 剩余可购买代币
		CollectedBNB:        event.CollectedBNB,        // 累计收集 BNB
		// 交易级元数据
		TransactionHash:     vLog.TxHash.Hex(),   // 交易哈希
		BlockNumber:         vLog.BlockNumber,    // 区块号
		BlockTimestamp:      timestamp,            // 区块时间戳
		LogIndex:            vLog.Index,           // 日志索引
	}, nil
}

// parseTokenSoldEvent 解析 TokenSold 事件日志
// 事件定义（Solidity）：
//   event TokenSold(address indexed token, address indexed seller, uint256 tokenAmount, uint256 bnbAmount,
//                   uint256 tradingFee, uint256 virtualBNBReserve, uint256 virtualTokenReserve,
//                   uint256 availableTokens, uint256 collectedBNB)
// 参数：
//   - vLog: 以太坊原始日志对象
//   - timestamp: 区块时间戳
// 返回：
//   - *evtypes.TokenSoldEvent: 解析后的事件结构体指针
//   - error: ABI 解码失败时返回错误
// 解析规则：
//   - Topics[1]: indexed token 地址
//   - Topics[2]: indexed seller 地址
//   - Data: ABI 编码的非 indexed 参数
// 与 TokenBought 的区别：
//   - seller 替代 buyer
//   - tokenAmount 在前，bnbAmount 在后（卖出代币获得 BNB）
// 业务含义：
//   - TokenSold 表示用户卖出代币获得 BNB
func (idx *Indexer) parseTokenSoldEvent(vLog types.Log, timestamp uint64) (*evtypes.TokenSoldEvent, error) {
	// 定义用于接收 ABI 解码结果的匿名结构体
	// 注意字段顺序与 Solidity 事件定义一致：tokenAmount 在前，bnbAmount 在后
	event := struct {
		TokenAmount         *big.Int // 卖出的代币数量
		BnbAmount           *big.Int // 获得的 BNB 数量（扣手续费后）
		TradingFee          *big.Int // 交易手续费（以 BNB 计）
		VirtualBNBReserve   *big.Int // AMM 虚拟 BNB 储备量
		VirtualTokenReserve *big.Int // AMM 虚拟代币储备量
		AvailableTokens     *big.Int // 内盘剩余可购买代币数量
		CollectedBNB        *big.Int // 该代币累计收集的 BNB 数量
	}{}

	// 使用 ABI 解码 Data 部分
	if err := idx.contractABI.UnpackIntoInterface(&event, "TokenSold", vLog.Data); err != nil {
		// 解码失败，返回错误
		return nil, err
	}

	// 构建并返回解析后的事件结构体
	return &evtypes.TokenSoldEvent{
		// 从 Topics 中提取 indexed 参数
		TokenAddress:        common.BytesToAddress(vLog.Topics[1].Bytes()).Hex(), // 代币合约地址
		SellerAddress:       common.BytesToAddress(vLog.Topics[2].Bytes()).Hex(), // 卖家钱包地址
		// 从解码后的 Data 中获取非 indexed 参数
		TokenAmount:         event.TokenAmount,         // 卖出的代币数量
		BnbAmount:           event.BnbAmount,           // 获得的 BNB 数量
		TradingFee:          event.TradingFee,          // 交易手续费
		VirtualBNBReserve:   event.VirtualBNBReserve,   // 虚拟 BNB 储备
		VirtualTokenReserve: event.VirtualTokenReserve, // 虚拟代币储备
		AvailableTokens:     event.AvailableTokens,     // 剩余可购买代币
		CollectedBNB:        event.CollectedBNB,        // 累计收集 BNB
		// 交易级元数据
		TransactionHash:     vLog.TxHash.Hex(),   // 交易哈希
		BlockNumber:         vLog.BlockNumber,    // 区块号
		BlockTimestamp:      timestamp,            // 区块时间戳
		LogIndex:            vLog.Index,           // 日志索引
	}, nil
}

// parseTokenGraduatedEvent 解析 TokenGraduated 事件日志
// 事件定义（Solidity）：
//   event TokenGraduated(address indexed token, uint256 liquidityBNB, uint256 liquidityTokens, uint256 liquidityResult)
// 参数：
//   - vLog: 以太坊原始日志对象
//   - timestamp: 区块时间戳
// 返回：
//   - *evtypes.TokenGraduatedEvent: 解析后的事件结构体指针
//   - error: ABI 解码失败时返回错误
// 业务含义：
//   - TokenGraduated 表示代币已完成内盘募资，达到目标后迁移到 DEX（如 PancakeSwap）
//   - 当代币累计收集的 BNB 达到目标值（默认 24 BNB）时，合约自动触发毕业
//   - 毕业流程：合约将代币和募集的 BNB 注入 DEX 创建流动性池
//   - liquidityBNB: 注入 DEX 的 BNB 数量（用于创建 LP）
//   - liquidityTokens: 注入 DEX 的代币数量（用于创建 LP）
//   - liquidityResult: 流动性添加结果（如 LP Token 数量或操作状态）
// 解析规则：
//   - Topics[1]: indexed token 地址
//   - Data: ABI 编码的 liquidityBNB, liquidityTokens, liquidityResult
func (idx *Indexer) parseTokenGraduatedEvent(vLog types.Log, timestamp uint64) (*evtypes.TokenGraduatedEvent, error) {
	// 定义用于接收 ABI 解码结果的匿名结构体
	// 只有三个非 indexed 参数
	event := struct {
		LiquidityBNB    *big.Int // 注入 DEX 的 BNB 数量
		LiquidityTokens *big.Int // 注入 DEX 的代币数量
		LiquidityResult *big.Int // 流动性添加结果
	}{}

	// 使用 ABI 解码 Data 部分
	if err := idx.contractABI.UnpackIntoInterface(&event, "TokenGraduated", vLog.Data); err != nil {
		// 解码失败，返回错误
		return nil, err
	}

	// 构建并返回解析后的事件结构体
	return &evtypes.TokenGraduatedEvent{
		// 从 Topics 中提取 indexed 参数（只有 token 是 indexed 的）
		TokenAddress:    common.BytesToAddress(vLog.Topics[1].Bytes()).Hex(), // 代币合约地址
		// 从解码后的 Data 中获取非 indexed 参数
		LiquidityBNB:    event.LiquidityBNB,    // 注入 DEX 的 BNB 数量
		LiquidityTokens: event.LiquidityTokens, // 注入 DEX 的代币数量
		LiquidityResult: event.LiquidityResult, // 流动性添加结果
		// 交易级元数据
		TransactionHash: vLog.TxHash.Hex(),   // 交易哈希
		BlockNumber:     vLog.BlockNumber,    // 区块号
		BlockTimestamp:  timestamp,            // 区块时间戳
		LogIndex:        vLog.Index,           // 日志索引
	}, nil
}
