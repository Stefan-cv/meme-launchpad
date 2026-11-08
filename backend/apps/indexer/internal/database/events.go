// database 包：MEME Launchpad Indexer 的事件数据库操作层
// 本文件负责将解析后的区块链事件持久化到 PostgreSQL 数据库，并同步更新业务表
// 核心职责：
// 1. 单条/批量插入四种链上事件（TokenCreated/TokenBought/TokenSold/TokenGraduated）
// 2. 同步更新业务表（tokens、trades），保持与链上状态一致
// 3. 更新 K 线（OHLCV）聚合数据，支持前端图表展示
// 4. 使用事务保证数据一致性，使用 SAVEPOINT 隔离 K 线更新错误
package database

// 导入所需的包
import (
	"context"  // 上下文包，用于控制数据库操作超时和传递取消信号
	"fmt"      // 格式化包，用于构建错误信息和 SAVEPOINT ID
	"math/big" // 大整数包，用于处理链上的 uint256 类型数值和高精度价格计算
	"time"     // 时间包，用于时间戳转换和 K 线时间对齐

	"github.com/jackc/pgx/v5" // pgx 是 PostgreSQL 的 Go 驱动，提供事务、查询等数据库操作
	"github.com/meme-launchpad/indexer/internal/types" // types 包，定义事件结构体
	"go.uber.org/zap" // zap 高性能结构化日志库
)

/*
 * 数据库设计说明：
 *   - 事件表（event tables）：原始链上事件的镜像，用于审计与追溯
 *     - token_created_events: 代币创建事件
 *     - token_bought_events: 代币购买事件
 *     - token_sold_events: 代币卖出事件
 *     - token_graduated_events: 代币毕业事件
 *   - 业务表（business tables）：面向 API 查询优化的聚合数据
 *     - tokens: 代币基本信息与状态
 *     - trades: 交易记录（买入/卖出统一存储）
 *     - klines: K 线数据（多时间间隔聚合）
 *
 * 事务策略：
 *   - 每个事件处理函数内部开启独立事务（tx）
 *   - 使用 defer tx.Rollback(ctx) 确保异常时自动回滚
 *   - 仅在所有操作成功后执行 tx.Commit(ctx)
 *   - ON CONFLICT 子句处理重复事件（幂等性保证）
 *
 * K 线更新隔离：
 *   - 使用 SAVEPOINT 隔离 K 线更新错误，避免影响主事务
 *   - K 线更新失败仅记录警告日志，不中断主流程
 *
 * 并发安全：
 *   - 本层函数由单个 indexer goroutine 调用，无并发竞争
 *   - database.DB 内部使用 pgx 连接池，支持高并发查询场景
 */

// InsertTokenCreatedEvent 插入单条代币创建事件，并同步到 tokens 业务表
// 参数：
//   - ctx: 上下文，用于控制操作超时
//   - event: 代币创建事件结构体指针，包含事件的所有字段
// 返回：
//   - error: 事务开启、SQL 执行或提交失败时返回错误
// 执行流程（单条事务）：
//   1. 开启数据库事务
//   2. 插入 token_created_events 事件表（ON CONFLICT DO NOTHING 保证幂等）
//   3. 从 token_creation_requests 表查询 logo（如用户提前上传）
//   4. 同步插入/更新 tokens 业务表（UPSERT 语义）
//   5. 提交事务
// 数据库字段映射：
//   - launch_mode=1: 固定值，表示标准发射模式
//   - bnb_target='24000000000000000000': 固定目标 24 BNB（内盘募资目标，18 位精度）
//   - status=1: 代币状态（1=募集中）
//   - nonce=0: 占位，实际由链上决定
// 错误处理：
//   - 事务开启失败：直接返回错误
//   - logo 查询失败：使用空字符串作为默认值，不影响主流程
//   - 任何 SQL 执行错误：触发回滚，返回错误
func (db *DB) InsertTokenCreatedEvent(ctx context.Context, event *types.TokenCreatedEvent) error {
	// 开启数据库事务
	// 事务确保事件表插入和业务表更新的原子性
	tx, err := db.pool.Begin(ctx)
	if err != nil {
		// 事务开启失败，直接返回错误
		return err
	}
	// defer 注册回滚操作：函数退出时如果事务未提交，自动回滚
	// 如果事务已提交（tx.Commit），Rollback 是无操作的（no-op）
	defer tx.Rollback(ctx)

	// 将 Unix 时间戳（秒）转换为 time.Time 类型，用于数据库 TIMESTAMP 字段
	blockTime := time.Unix(int64(event.BlockTimestamp), 0)

	// 步骤 1：插入 token_created_events 事件表
	// ON CONFLICT (transaction_hash, log_index) DO NOTHING 保证同一笔交易的同一日志只插入一次
	// 这实现了幂等性：重复处理同一事件不会导致数据重复
	_, err = tx.Exec(ctx, `
		INSERT INTO token_created_events (
			token_address, creator_address, name, symbol, total_supply,
			request_id, transaction_hash, block_number, block_timestamp, log_index
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
		ON CONFLICT (transaction_hash, log_index) DO NOTHING
	`,
		event.TokenAddress,    // $1: 代币合约地址
		event.CreatorAddress,  // $2: 创建者钱包地址
		event.Name,            // $3: 代币名称
		event.Symbol,          // $4: 代币符号
		event.TotalSupply,     // $5: 总供应量
		event.RequestID,       // $6: 创建请求 ID
		event.TransactionHash, // $7: 交易哈希
		event.BlockNumber,     // $8: 区块号
		blockTime,             // $9: 区块时间戳（time.Time 类型）
		event.LogIndex,        // $10: 日志索引
	)
	if err != nil {
		// 事件表插入失败，返回错误（defer 会自动回滚事务）
		return err
	}

	// 步骤 2：从 token_creation_requests 表获取 logo
	// 用户在创建代币前可能已通过前端上传了 logo 图片
	// 通过 request_id 关联：前端先创建请求（上传 logo），再在链上创建代币
	var logo string
	err = tx.QueryRow(ctx, `
		SELECT COALESCE(logo, '') FROM token_creation_requests WHERE request_id = $1
	`, event.RequestID).Scan(&logo) // 将查询结果扫描到 logo 变量
	if err != nil {
		// 如果查询失败（如 request_id 不存在），使用空字符串作为默认值
		// 不返回错误，因为 logo 不是必填项，代币可以在没有 logo 的情况下正常交易
		logo = ""
	}

	// 步骤 3：同步到 tokens 业务表
	// ON CONFLICT (token_contract_address) DO UPDATE 实现 UPSERT：
	//   - 新代币：插入完整记录
	//   - 已存在（重复事件或更新）：更新 name、symbol、logo、updated_at
	_, err = tx.Exec(ctx, `
		INSERT INTO tokens (
			name, symbol, logo, token_contract_address, creator_address,
			launch_mode, launch_time, bnb_target, total_supply, status,
			request_id, nonce, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, 1, $6, '24000000000000000000', $7, 1, $8, 0, $9, $9)
		ON CONFLICT (token_contract_address) DO UPDATE SET
			name = EXCLUDED.name,
			symbol = EXCLUDED.symbol,
			logo = COALESCE(NULLIF(EXCLUDED.logo, ''), tokens.logo),
			updated_at = EXCLUDED.updated_at
	`,
		event.Name,            // $1: 代币名称
		event.Symbol,          // $2: 代币符号
		logo,                  // $3: logo URL（可能为空字符串）
		event.TokenAddress,    // $4: 代币合约地址（作为唯一键）
		event.CreatorAddress,  // $5: 创建者地址
		event.BlockTimestamp,  // $6: 发射时间（Unix 时间戳）
		event.TotalSupply,     // $7: 总供应量
		event.RequestID,       // $8: 请求 ID
		blockTime,             // $9: 创建时间和更新时间
	)
	// COALESCE(NULLIF(EXCLUDED.logo, ''), tokens.logo) 的含义：
	//   - NULLIF(EXCLUDED.logo, '')：如果新 logo 是空字符串，转为 NULL
	//   - COALESCE(NULL, tokens.logo)：如果新 logo 是 NULL，保留旧 logo
	//   - 效果：只在有新 logo 时才更新，避免空字符串覆盖已有 logo
	if err != nil {
		// 业务表操作失败，返回错误（defer 会自动回滚事务）
		return err
	}

	// 提交事务：将所有变更持久化到数据库
	// Commit 成功后，defer 的 Rollback 不再执行任何操作
	return tx.Commit(ctx)
}

// InsertTokenBoughtEvent 插入单条代币购买事件，并同步到 trades 和 tokens 表
// 参数：
//   - ctx: 上下文
//   - event: 代币购买事件结构体指针
// 返回：
//   - error: 事务失败时返回错误
// 执行流程（单条事务）：
//   1. 开启数据库事务
//   2. 插入 token_bought_events 事件表
//   3. 同步插入 trades 业务表（trade_type=10 表示买入）
//   4. 更新 tokens 表的 bnb_current（累计 BNB）和 available_tokens（内盘剩余代币）
//   5. 更新 K 线数据（通过 SAVEPOINT 隔离错误）
//   6. 提交事务
// 数据一致性：
//   - trades 表与事件表通过 transaction_hash + trade_type 联合唯一约束去重
//   - tokens 表的 bnb_current 和 available_tokens 反映最新链上状态
// K 线更新策略：
//   - 使用 SAVEPOINT 隔离，失败不影响主事务
//   - 失败时记录 Warn 级别日志
func (db *DB) InsertTokenBoughtEvent(ctx context.Context, event *types.TokenBoughtEvent) error {
	// 开启数据库事务
	tx, err := db.pool.Begin(ctx)
	if err != nil {
		// 事务开启失败
		return err
	}
	// 确保异常时自动回滚
	defer tx.Rollback(ctx)

	// 转换区块时间戳为 time.Time 类型
	blockTime := time.Unix(int64(event.BlockTimestamp), 0)

	// 步骤 1：插入 token_bought_events 事件表
	_, err = tx.Exec(ctx, `
		INSERT INTO token_bought_events (
			token_address, buyer_address, bnb_amount, token_amount,
			trading_fee, virtual_bnb_reserve, virtual_token_reserve,
			available_tokens, collected_bnb,
			transaction_hash, block_number, block_timestamp, log_index
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		ON CONFLICT (transaction_hash, log_index) DO NOTHING
	`,
		event.TokenAddress,        // $1: 代币合约地址
		event.BuyerAddress,        // $2: 买家钱包地址
		event.BnbAmount,           // $3: 花费的 BNB 数量
		event.TokenAmount,         // $4: 获得的代币数量
		event.TradingFee,          // $5: 交易手续费
		event.VirtualBNBReserve,   // $6: 虚拟 BNB 储备
		event.VirtualTokenReserve, // $7: 虚拟代币储备
		event.AvailableTokens,     // $8: 剩余可购买代币
		event.CollectedBNB,        // $9: 累计收集 BNB
		event.TransactionHash,     // $10: 交易哈希
		event.BlockNumber,         // $11: 区块号
		blockTime,                 // $12: 区块时间戳
		event.LogIndex,            // $13: 日志索引
	)
	if err != nil {
		// 事件表插入失败
		return err
	}

	// 步骤 2：同步到 trades 业务表
	// trade_type=10 表示买入交易（20 表示卖出）
	// ON CONFLICT (transaction_hash, trade_type) 处理同一笔交易的买入/卖出分别记录
	// 同一笔交易哈希可以同时存在买入和卖出记录（trade_type 不同）
	_, err = tx.Exec(ctx, `
		INSERT INTO trades (
			token_address, user_address, trade_type, bnb_amount, token_amount,
			price, transaction_hash, block_number, block_timestamp
		) VALUES ($1, $2, 10, $3, $4, 0, $5, $6, $7)
		ON CONFLICT (transaction_hash, trade_type) DO NOTHING
	`,
		event.TokenAddress,    // $1: 代币合约地址
		event.BuyerAddress,    // $2: 买家地址（trades 表统一使用 user_address 字段）
		event.BnbAmount,       // $3: BNB 数量
		event.TokenAmount,     // $4: 代币数量
		event.TransactionHash, // $5: 交易哈希
		event.BlockNumber,     // $6: 区块号
		blockTime,             // $7: 区块时间戳
	)
	// price=0 是占位值，实际价格可在查询时根据 bnb_amount/token_amount 计算
	if err != nil {
		// trades 表插入失败
		return err
	}

	// 步骤 3：更新 tokens 表的 bnb_current 和 available_tokens
	// bnb_current: 该代币累计收集的 BNB 数量（反映募资进度）
	// available_tokens: 内盘剩余可购买代币数量（当为 0 时触发毕业）
	// 使用 LOWER() 函数实现大小写不敏感的地址匹配
	// 因为以太坊地址的校验和格式（EIP-55）可能导致大小写不一致
	_, err = tx.Exec(ctx, `
				UPDATE tokens SET
					bnb_current = $1::numeric,
					available_tokens = $2::numeric,
					updated_at = $3
				WHERE LOWER(token_contract_address) = LOWER($4)
			`,
		event.CollectedBNB,    // $1: 累计收集的 BNB（更新 bnb_current）
		event.AvailableTokens, // $2: 剩余可购买代币数量
		blockTime,             // $3: 更新时间
		event.TokenAddress,    // $4: 代币地址（大小写不敏感匹配）
	)
	if err != nil {
		// tokens 表更新失败
		return err
	}

	// 步骤 4：更新 K 线数据（使用 SAVEPOINT 隔离错误，避免影响主事务）
	// K 线数据是聚合数据，更新失败不应导致整个事务回滚
	// 传入 nil 表示更新所有支持的时间间隔
	if err := db.updateKlineDataWithSavepoint(ctx, tx, event.TokenAddress, blockTime, event.BnbAmount, event.TokenAmount, nil); err != nil {
		// K 线更新失败不影响主流程，只记录警告
		db.logger.Warn("Failed to update kline data",
			zap.String("token", event.TokenAddress), // 代币地址
			zap.Error(err))                          // 错误详情
	}

	// 提交事务
	return tx.Commit(ctx)
}

// InsertTokenSoldEvent 插入单条代币卖出事件，并同步到 trades 表
// 参数：
//   - ctx: 上下文
//   - event: 代币卖出事件结构体指针
// 返回：
//   - error: 事务失败时返回错误
// 执行流程（单条事务）：
//   1. 开启数据库事务
//   2. 插入 token_sold_events 事件表
//   3. 同步插入 trades 业务表（trade_type=20 表示卖出）
//   4. 更新 tokens 表的 bnb_current 和 available_tokens
//   5. 更新 K 线数据（SAVEPOINT 隔离）
//   6. 提交事务
// 与 InsertTokenBoughtEvent 的区别：
//   - trade_type=20（卖出）而非 10（买入）
//   - seller_address 替代 buyer_address
func (db *DB) InsertTokenSoldEvent(ctx context.Context, event *types.TokenSoldEvent) error {
	// 开启数据库事务
	tx, err := db.pool.Begin(ctx)
	if err != nil {
		return err
	}
	// 确保异常时自动回滚
	defer tx.Rollback(ctx)

	// 转换区块时间戳
	blockTime := time.Unix(int64(event.BlockTimestamp), 0)

	// 步骤 1：插入 token_sold_events 事件表
	_, err = tx.Exec(ctx, `
		INSERT INTO token_sold_events (
			token_address, seller_address, token_amount, bnb_amount,
			trading_fee, virtual_bnb_reserve, virtual_token_reserve,
			available_tokens, collected_bnb,
			transaction_hash, block_number, block_timestamp, log_index
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		ON CONFLICT (transaction_hash, log_index) DO NOTHING
	`,
		event.TokenAddress,        // $1: 代币合约地址
		event.SellerAddress,       // $2: 卖家钱包地址
		event.TokenAmount,         // $3: 卖出的代币数量
		event.BnbAmount,           // $4: 获得的 BNB 数量
		event.TradingFee,          // $5: 交易手续费
		event.VirtualBNBReserve,   // $6: 虚拟 BNB 储备
		event.VirtualTokenReserve, // $7: 虚拟代币储备
		event.AvailableTokens,     // $8: 剩余可购买代币
		event.CollectedBNB,        // $9: 累计收集 BNB
		event.TransactionHash,     // $10: 交易哈希
		event.BlockNumber,         // $11: 区块号
		blockTime,                 // $12: 区块时间戳
		event.LogIndex,            // $13: 日志索引
	)
	if err != nil {
		return err
	}

	// 步骤 2：同步到 trades 业务表 (trade_type=20 表示卖出)
	// 与买入使用相同的 trades 表结构，通过 trade_type 区分方向
	_, err = tx.Exec(ctx, `
		INSERT INTO trades (
			token_address, user_address, trade_type, bnb_amount, token_amount,
			price, transaction_hash, block_number, block_timestamp
		) VALUES ($1, $2, 20, $3, $4, 0, $5, $6, $7)
		ON CONFLICT (transaction_hash, trade_type) DO NOTHING
	`,
		event.TokenAddress,    // $1: 代币合约地址
		event.SellerAddress,   // $2: 卖家地址（trades 表使用 user_address 字段）
		event.BnbAmount,       // $3: BNB 数量
		event.TokenAmount,     // $4: 代币数量
		event.TransactionHash, // $5: 交易哈希
		event.BlockNumber,     // $6: 区块号
		blockTime,             // $7: 区块时间戳
	)
	if err != nil {
		return err
	}

	// 步骤 3：更新 tokens 表的 bnb_current 和 available_tokens
	// 卖出后：BNB 流出内盘，代币回到内盘
	// 使用 LOWER() 实现大小写不敏感匹配
	_, err = tx.Exec(ctx, `
				UPDATE tokens SET
					bnb_current = $1::numeric,
					available_tokens = $2::numeric,
					updated_at = $3
				WHERE LOWER(token_contract_address) = LOWER($4)
			`,
		event.CollectedBNB,    // $1: 累计 BNB（卖出时减少）
		event.AvailableTokens, // $2: 剩余代币（卖出时增加）
		blockTime,             // $3: 更新时间
		event.TokenAddress,    // $4: 代币地址
	)
	if err != nil {
		return err
	}

	// 步骤 4：更新 K 线数据（SAVEPOINT 隔离）
	if err := db.updateKlineDataWithSavepoint(ctx, tx, event.TokenAddress, blockTime, event.BnbAmount, event.TokenAmount, nil); err != nil {
		// K 线更新失败不影响主流程
		db.logger.Warn("Failed to update kline data",
			zap.String("token", event.TokenAddress),
			zap.Error(err))
	}

	// 提交事务
	return tx.Commit(ctx)
}

// InsertTokenGraduatedEvent 插入单条代币毕业事件，并更新 tokens 状态
// 参数：
//   - ctx: 上下文
//   - event: 代币毕业事件结构体指针
// 返回：
//   - error: 事务失败时返回错误
// 执行流程（单条事务）：
//   1. 开启数据库事务
//   2. 插入 token_graduated_events 事件表
//   3. 更新 tokens 表状态为已毕业 (status=3)
//   4. 提交事务
// 业务含义：
//   - TokenGraduated 表示代币已完成内盘募资，达到 BNB 目标（默认 24 BNB）
//   - 合约自动将代币和募集的 BNB 注入 DEX（如 PancakeSwap）创建流动性池
//   - status=3 表示代币已毕业，内盘交易关闭，后续可在 DEX 交易
func (db *DB) InsertTokenGraduatedEvent(ctx context.Context, event *types.TokenGraduatedEvent) error {
	// 开启数据库事务
	tx, err := db.pool.Begin(ctx)
	if err != nil {
		return err
	}
	// 确保异常时自动回滚
	defer tx.Rollback(ctx)

	// 转换区块时间戳
	blockTime := time.Unix(int64(event.BlockTimestamp), 0)

	// 步骤 1：插入 token_graduated_events 事件表
	_, err = tx.Exec(ctx, `
		INSERT INTO token_graduated_events (
			token_address, liquidity_bnb, liquidity_tokens, liquidity_result,
			transaction_hash, block_number, block_timestamp, log_index
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		ON CONFLICT (transaction_hash, log_index) DO NOTHING
	`,
		event.TokenAddress,    // $1: 代币合约地址
		event.LiquidityBNB,    // $2: 注入 DEX 的 BNB 数量
		event.LiquidityTokens, // $3: 注入 DEX 的代币数量
		event.LiquidityResult, // $4: 流动性添加结果
		event.TransactionHash, // $5: 交易哈希
		event.BlockNumber,     // $6: 区块号
		blockTime,             // $7: 区块时间戳
		event.LogIndex,        // $8: 日志索引
	)
	if err != nil {
		return err
	}

	// 步骤 2：更新 tokens 表状态为已毕业 (status=3)
	// status 值含义：1=募集中（内盘交易中），2=可能的其他状态，3=已毕业（DEX 交易中）
	// 毕业后内盘交易关闭，代币可在 DEX 上自由交易
	_, err = tx.Exec(ctx, `
		UPDATE tokens SET
			status = 3,            -- 设置状态为已毕业
			updated_at = $1        -- 更新时间
		WHERE LOWER(token_contract_address) = LOWER($2) -- 大小写不敏感匹配
	`,
		blockTime,          // $1: 更新时间
		event.TokenAddress, // $2: 代币地址
	)
	if err != nil {
		return err
	}

	// 提交事务
	return tx.Commit(ctx)
}

// BatchInsertTokenCreatedEvents 批量插入代币创建事件，并同步到 tokens 表
// 参数：
//   - ctx: 上下文
//   - events: 代币创建事件切片（可能为空）
// 返回：
//   - error: 事务失败时返回错误
// 执行流程（批量事务）：
//   1. 空切片直接返回 nil（无操作）
//   2. 开启数据库事务
//   3. 遍历事件切片，逐个执行：
//      a. 插入 token_created_events 事件表
//      b. 查询 token_creation_requests 获取 logo
//      c. 同步插入/更新 tokens 业务表
//   4. 提交事务
// 与 InsertTokenCreatedEvent 的区别：
//   - 支持批量处理，减少事务开销（一次提交 vs N 次提交）
//   - 所有事件在同一个事务中，要么全部成功，要么全部回滚
// 性能考虑：
//   - 批量大小由调用方（indexer.syncBlockRange）控制
//   - 过大的批量可能导致事务时间过长，建议控制在合理范围
func (db *DB) BatchInsertTokenCreatedEvents(ctx context.Context, events []*types.TokenCreatedEvent) error {
	// 空切片检查：没有事件需要处理，直接返回
	if len(events) == 0 {
		return nil
	}

	// 开启数据库事务
	tx, err := db.pool.Begin(ctx)
	if err != nil {
		return err
	}
	// 确保异常时自动回滚
	defer tx.Rollback(ctx)

	// 遍历所有事件，逐个处理
	for _, event := range events {
		// 转换区块时间戳
		blockTime := time.Unix(int64(event.BlockTimestamp), 0)

		// 步骤 1：插入事件表
		_, err := tx.Exec(ctx, `
			INSERT INTO token_created_events (
				token_address, creator_address, name, symbol, total_supply,
				request_id, transaction_hash, block_number, block_timestamp, log_index
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
			ON CONFLICT (transaction_hash, log_index) DO NOTHING
		`,
			event.TokenAddress,    // $1: 代币合约地址
			event.CreatorAddress,  // $2: 创建者地址
			event.Name,            // $3: 代币名称
			event.Symbol,          // $4: 代币符号
			event.TotalSupply,     // $5: 总供应量
			event.RequestID,       // $6: 请求 ID
			event.TransactionHash, // $7: 交易哈希
			event.BlockNumber,     // $8: 区块号
			blockTime,             // $9: 区块时间戳
			event.LogIndex,        // $10: 日志索引
		)
		if err != nil {
			// 单个事件插入失败，整个事务回滚
			return err
		}

		// 步骤 2：从 token_creation_requests 表获取 logo
		var logo string
		err = tx.QueryRow(ctx, `
			SELECT COALESCE(logo, '') FROM token_creation_requests WHERE request_id = $1
		`, event.RequestID).Scan(&logo)
		if err != nil {
			// 查询失败，使用空字符串默认值
			logo = ""
		}

		// 步骤 3：同步到 tokens 业务表（UPSERT）
		_, err = tx.Exec(ctx, `
			INSERT INTO tokens (
				name, symbol, logo, token_contract_address, creator_address,
				launch_mode, launch_time, bnb_target, total_supply, status,
				request_id, nonce, created_at, updated_at
			) VALUES ($1, $2, $3, $4, $5, 1, $6, '24000000000000000000', $7, 1, $8, 0, $9, $9)
			ON CONFLICT (token_contract_address) DO UPDATE SET
				name = EXCLUDED.name,
				symbol = EXCLUDED.symbol,
				logo = COALESCE(NULLIF(EXCLUDED.logo, ''), tokens.logo),
				updated_at = EXCLUDED.updated_at
		`,
			event.Name,            // $1: 代币名称
			event.Symbol,          // $2: 代币符号
			logo,                  // $3: logo URL
			event.TokenAddress,    // $4: 代币合约地址
			event.CreatorAddress,  // $5: 创建者地址
			event.BlockTimestamp,  // $6: 发射时间
			event.TotalSupply,     // $7: 总供应量
			event.RequestID,       // $8: 请求 ID
			blockTime,             // $9: 创建/更新时间
		)
		if err != nil {
			// 业务表操作失败，整个事务回滚
			return err
		}
	}

	// 所有事件处理完成，提交事务
	return tx.Commit(ctx)
}

// BatchInsertTokenBoughtEvents 批量插入代币购买事件，并更新 tokens 表和 K 线数据
// 参数：
//   - ctx: 上下文
//   - events: 代币购买事件切片
// 返回：
//   - error: 事务失败时返回错误
// 执行流程（批量事务）：
//   1. 空切片直接返回 nil
//   2. 开启数据库事务
//   3. 遍历事件切片，逐个执行：
//      a. 插入 token_bought_events 事件表
//      b. 同步插入 trades 业务表（trade_type=10）
//      c. 更新 tokens 表的 bnb_current 和 available_tokens
//      d. 更新 K 线数据（SAVEPOINT 隔离）
//   4. 提交事务
// 性能与一致性：
//   - 同一事务内处理多个事件，保证数据一致性
//   - 每个事件的 K 线更新使用独立 SAVEPOINT，互不影响
func (db *DB) BatchInsertTokenBoughtEvents(ctx context.Context, events []*types.TokenBoughtEvent) error {
	// 空切片检查
	if len(events) == 0 {
		return nil
	}

	// 开启数据库事务
	tx, err := db.pool.Begin(ctx)
	if err != nil {
		return err
	}
	// 确保异常时自动回滚
	defer tx.Rollback(ctx)

	// 遍历所有购买事件
	for _, event := range events {
		// 步骤 1：插入事件表
		_, err := tx.Exec(ctx, `
			INSERT INTO token_bought_events (
				token_address, buyer_address, bnb_amount, token_amount,
				trading_fee, virtual_bnb_reserve, virtual_token_reserve,
				available_tokens, collected_bnb,
				transaction_hash, block_number, block_timestamp, log_index
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
			ON CONFLICT (transaction_hash, log_index) DO NOTHING
		`,
			event.TokenAddress,        // $1: 代币合约地址
			event.BuyerAddress,        // $2: 买家地址
			event.BnbAmount,           // $3: BNB 数量
			event.TokenAmount,         // $4: 代币数量
			event.TradingFee,          // $5: 手续费
			event.VirtualBNBReserve,   // $6: 虚拟 BNB 储备
			event.VirtualTokenReserve, // $7: 虚拟代币储备
			event.AvailableTokens,     // $8: 剩余代币
			event.CollectedBNB,        // $9: 累计 BNB
			event.TransactionHash,     // $10: 交易哈希
			event.BlockNumber,         // $11: 区块号
			time.Unix(int64(event.BlockTimestamp), 0), // $12: 区块时间戳
			event.LogIndex,            // $13: 日志索引
		)
		if err != nil {
			return err
		}

		// 步骤 2：同步到 trades 业务表 (trade_type=10 表示买入)
		_, err = tx.Exec(ctx, `
			INSERT INTO trades (
				token_address, user_address, trade_type, bnb_amount, token_amount,
				price, transaction_hash, block_number, block_timestamp
			) VALUES ($1, $2, 10, $3, $4, 0, $5, $6, $7)
			ON CONFLICT (transaction_hash, trade_type) DO NOTHING
		`,
			event.TokenAddress,    // $1: 代币地址
			event.BuyerAddress,    // $2: 买家地址
			event.BnbAmount,       // $3: BNB 数量
			event.TokenAmount,     // $4: 代币数量
			event.TransactionHash, // $5: 交易哈希
			event.BlockNumber,     // $6: 区块号
			time.Unix(int64(event.BlockTimestamp), 0), // $7: 区块时间戳
		)
		if err != nil {
			return err
		}

		// 步骤 3：更新 tokens 表的 bnb_current 和 available_tokens
		_, err = tx.Exec(ctx, `
			UPDATE tokens SET
				bnb_current = $1::numeric,
				available_tokens = $2::numeric,
				updated_at = $3
			WHERE LOWER(token_contract_address) = LOWER($4)
		`,
			event.CollectedBNB,    // $1: 累计 BNB
			event.AvailableTokens, // $2: 剩余代币
			time.Unix(int64(event.BlockTimestamp), 0), // $3: 更新时间
			event.TokenAddress,    // $4: 代币地址
		)
		if err != nil {
			return err
		}

		// 步骤 4：更新 K 线数据（使用 SAVEPOINT 隔离错误）
		blockTime := time.Unix(int64(event.BlockTimestamp), 0)
		if err := db.updateKlineDataWithSavepoint(ctx, tx, event.TokenAddress, blockTime, event.BnbAmount, event.TokenAmount, nil); err != nil {
			// K 线更新失败不影响主流程
			db.logger.Warn("Failed to update kline data",
				zap.String("token", event.TokenAddress),
				zap.Error(err))
		}
	}

	// 所有事件处理完成，提交事务
	return tx.Commit(ctx)
}

// BatchInsertTokenSoldEvents 批量插入代币卖出事件，并更新 tokens 表和 K 线数据
// 参数：
//   - ctx: 上下文
//   - events: 代币卖出事件切片
// 返回：
//   - error: 事务失败时返回错误
// 执行流程与 BatchInsertTokenBoughtEvents 对称：
//   - trade_type=20（卖出）而非 10（买入）
//   - seller_address 替代 buyer_address
func (db *DB) BatchInsertTokenSoldEvents(ctx context.Context, events []*types.TokenSoldEvent) error {
	// 空切片检查
	if len(events) == 0 {
		return nil
	}

	// 开启数据库事务
	tx, err := db.pool.Begin(ctx)
	if err != nil {
		return err
	}
	// 确保异常时自动回滚
	defer tx.Rollback(ctx)

	// 遍历所有卖出事件
	for _, event := range events {
		// 步骤 1：插入事件表
		_, err := tx.Exec(ctx, `
			INSERT INTO token_sold_events (
				token_address, seller_address, token_amount, bnb_amount,
				trading_fee, virtual_bnb_reserve, virtual_token_reserve,
				available_tokens, collected_bnb,
				transaction_hash, block_number, block_timestamp, log_index
			) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
			ON CONFLICT (transaction_hash, log_index) DO NOTHING
		`,
			event.TokenAddress,        // $1: 代币地址
			event.SellerAddress,       // $2: 卖家地址
			event.TokenAmount,         // $3: 代币数量
			event.BnbAmount,           // $4: BNB 数量
			event.TradingFee,          // $5: 手续费
			event.VirtualBNBReserve,   // $6: 虚拟 BNB 储备
			event.VirtualTokenReserve, // $7: 虚拟代币储备
			event.AvailableTokens,     // $8: 剩余代币
			event.CollectedBNB,        // $9: 累计 BNB
			event.TransactionHash,     // $10: 交易哈希
			event.BlockNumber,         // $11: 区块号
			time.Unix(int64(event.BlockTimestamp), 0), // $12: 区块时间戳
			event.LogIndex,            // $13: 日志索引
		)
		if err != nil {
			return err
		}

		// 步骤 2：同步到 trades 业务表 (trade_type=20 表示卖出)
		_, err = tx.Exec(ctx, `
			INSERT INTO trades (
				token_address, user_address, trade_type, bnb_amount, token_amount,
				price, transaction_hash, block_number, block_timestamp
			) VALUES ($1, $2, 20, $3, $4, 0, $5, $6, $7)
			ON CONFLICT (transaction_hash, trade_type) DO NOTHING
		`,
			event.TokenAddress,    // $1: 代币地址
			event.SellerAddress,   // $2: 卖家地址
			event.BnbAmount,       // $3: BNB 数量
			event.TokenAmount,     // $4: 代币数量
			event.TransactionHash, // $5: 交易哈希
			event.BlockNumber,     // $6: 区块号
			time.Unix(int64(event.BlockTimestamp), 0), // $7: 区块时间戳
		)
		if err != nil {
			return err
		}

		// 步骤 3：更新 tokens 表
		_, err = tx.Exec(ctx, `
			UPDATE tokens SET
				bnb_current = $1::numeric,
				available_tokens = $2::numeric,
				updated_at = $3
			WHERE LOWER(token_contract_address) = LOWER($4)
		`,
			event.CollectedBNB,    // $1: 累计 BNB
			event.AvailableTokens, // $2: 剩余代币
			time.Unix(int64(event.BlockTimestamp), 0), // $3: 更新时间
			event.TokenAddress,    // $4: 代币地址
		)
		if err != nil {
			return err
		}

		// 步骤 4：更新 K 线数据
		blockTime := time.Unix(int64(event.BlockTimestamp), 0)
		if err := db.updateKlineDataWithSavepoint(ctx, tx, event.TokenAddress, blockTime, event.BnbAmount, event.TokenAmount, nil); err != nil {
			// K 线更新失败不影响主流程
			db.logger.Warn("Failed to update kline data",
				zap.String("token", event.TokenAddress),
				zap.Error(err))
		}
	}

	// 提交事务
	return tx.Commit(ctx)
}

// updateKlineDataWithSavepoint 使用 SAVEPOINT 隔离更新 K 线数据，避免错误影响主事务
// 参数：
//   - ctx: 上下文
//   - tx: 当前数据库事务
//   - tokenAddress: 代币合约地址
//   - blockTime: 区块时间（用于对齐 K 线时间间隔）
//   - bnbAmount: BNB 交易金额
//   - tokenAmount: 代币交易数量
//   - intervals: 指定更新的时间间隔（nil 表示全部支持间隔）
// 返回：
//   - error: SAVEPOINT 操作或 K 线更新失败时返回错误
// 执行流程：
//   1. 生成唯一 SAVEPOINT ID（基于纳秒时间戳，避免冲突）
//   2. 创建 SAVEPOINT（在事务中设置一个回滚点）
//   3. 调用 updateKlineData 执行实际更新
//   4. 成功时释放 SAVEPOINT（RELEASE，释放资源）
//   5. 失败时回滚到 SAVEPOINT（ROLLBACK TO），撤销 K 线相关操作
// 设计目的：
//   - K 线数据属于"锦上添花"的聚合数据，不应因 K 线计算错误导致主交易回滚
//   - SAVEPOINT 是 PostgreSQL 支持的子事务机制，允许部分回滚
//   - 例如：如果代币不存在导致 tokens 表更新触发异常，K 线的 SAVEPOINT 回滚可以
//     撤销 K 线操作，但保留之前成功的 trades 表操作
func (db *DB) updateKlineDataWithSavepoint(ctx context.Context, tx pgx.Tx, tokenAddress string, blockTime time.Time, bnbAmount, tokenAmount *big.Int, intervals []string) error {
	// 生成唯一的 SAVEPOINT ID
	// 使用纳秒时间戳确保唯一性，避免并发场景下的 SAVEPOINT 名称冲突
	savepointID := fmt.Sprintf("kline_update_%d", time.Now().UnixNano())

	// 创建 SAVEPOINT
	// SAVEPOINT 类似于事务中的"书签"，后续可以回滚到该点
	_, err := tx.Exec(ctx, "SAVEPOINT "+savepointID)
	if err != nil {
		// SAVEPOINT 创建失败，返回错误
		return fmt.Errorf("failed to create savepoint: %w", err)
	}

	// 调用 updateKlineData 执行实际的 K 线数据更新
	err = db.updateKlineData(ctx, tx, tokenAddress, blockTime, bnbAmount, tokenAmount, intervals)
	if err != nil {
		// K 线更新失败，回滚到 SAVEPOINT
		// 这会撤销 SAVEPOINT 之后的所有数据库操作，但不影响 SAVEPOINT 之前的操作
		_, rollbackErr := tx.Exec(ctx, "ROLLBACK TO SAVEPOINT "+savepointID)
		if rollbackErr != nil {
			// 回滚也失败了，返回组合错误（同时包含原始错误和回滚错误）
			return fmt.Errorf("failed to rollback savepoint: %w (original error: %v)", rollbackErr, err)
		}
		// 回滚成功，返回原始的 K 线更新错误
		return err
	}

	// K 线更新成功，释放 SAVEPOINT
	// RELEASE 会释放 SAVEPOINT 占用的资源，并保留 SAVEPOINT 后的操作结果
	_, err = tx.Exec(ctx, "RELEASE SAVEPOINT "+savepointID)
	if err != nil {
		// 释放失败，返回错误
		return fmt.Errorf("failed to release savepoint: %w", err)
	}

	return nil
}

// updateKlineData 更新 K 线（OHLCV）数据
// 根据交易事件计算价格并更新对应时间间隔的 K 线数据
// 参数：
//   - ctx: 上下文
//   - tx: 数据库事务（可为 nil，为 nil 时使用连接池直接执行）
//   - tokenAddress: 代币合约地址
//   - blockTime: 区块时间
//   - bnbAmount: BNB 交易金额
//   - tokenAmount: 代币交易数量
//   - intervals: 指定更新的时间间隔（nil 表示全部支持间隔）
// 返回：
//   - error: 计算或数据库操作失败时返回错误
// 执行流程：
//   1. 校验输入数据（跳过无效数据）
//   2. 计算价格：price = bnbAmount / tokenAmount（18 位小数精度）
//   3. 遍历所有支持的时间间隔（或指定间隔）
//   4. 对齐时间到间隔边界（alignTimeToInterval）
//   5. 执行 UPSERT 操作更新 klines 表
// K 线数据模型（OHLCV）：
//   - open_price: 该时间间隔第一笔交易的价格（新记录时设置，已存在不更新）
//   - high_price: 该时间间隔最高价格（GREATEST 取最大值更新）
//   - low_price: 该时间间隔最低价格（LEAST 取最小值更新）
//   - close_price: 该时间间隔最后一笔交易的价格（总是更新为最新）
//   - volume: 累计交易量（累加 tokenAmount）
// 支持的时间间隔：1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w
func (db *DB) updateKlineData(ctx context.Context, tx pgx.Tx, tokenAddress string, blockTime time.Time, bnbAmount, tokenAmount *big.Int, intervals []string) error {
	// 输入数据校验
	// 跳过无效数据：BNB 金额为 nil、代币数量为 nil、代币数量为零
	// 代币数量为零会导致价格计算除零错误
	if bnbAmount == nil || tokenAmount == nil || tokenAmount.Sign() == 0 {
		return nil // 跳过，不算错误
	}

	// 计算交易价格：price = bnbAmount / tokenAmount
	// 使用 big.Float 进行高精度浮点除法，避免精度损失
	// 18 位小数精度对应 ERC20 代币的标准精度（wei 级别）
	price := new(big.Float).Quo(
		new(big.Float).SetInt(bnbAmount), // 将 *big.Int 转换为 *big.Float
		new(big.Float).SetInt(tokenAmount), // 将 *big.Int 转换为 *big.Float
	)
	// 将价格格式化为 18 位小数的字符串
	// 'f' 格式表示不带指数的十进制表示
	// 18 是小数位数，匹配 NUMERIC(78, 18) 的精度
	priceStr := price.Text('f', 18)

	// 定义支持的 K 线时间间隔
	// key: 间隔标识，value: 是否有效
	validIntervals := map[string]bool{
		"1m": true,  // 1 分钟 K 线
		"5m": true,  // 5 分钟 K 线
		"15m": true, // 15 分钟 K 线
		"30m": true, // 30 分钟 K 线
		"1h": true,  // 1 小时 K 线
		"4h": true,  // 4 小时 K 线
		"1d": true,  // 1 天 K 线
		"1w": true,  // 1 周 K 线
	}

	// 如果没有指定 intervals，使用所有支持的间隔
	// 每笔交易会同时更新所有时间间隔的 K 线数据
	if len(intervals) == 0 {
		intervals = []string{"1m", "5m", "15m", "30m", "1h", "4h", "1d", "1w"}
	}

	// 为每个时间间隔更新 K 线数据
	for _, interval := range intervals {
		// 验证间隔是否有效
		if !validIntervals[interval] {
			continue // 跳过无效间隔
		}

		// 计算该时间间隔的开始时间（对齐到间隔边界）
		// 例如：15m 间隔下，14:37 会对齐到 14:30
		openTime := alignTimeToInterval(blockTime, interval)

		// 使用 UPSERT 更新或插入 K 线数据
		var err error
		if tx != nil {
			// 在事务中执行（正常流程）
			_, err = tx.Exec(ctx, `
				INSERT INTO klines (
					token_address, interval, open_time,
					open_price, high_price, low_price, close_price, volume
				) VALUES ($1, $2, $3, $4::numeric, $5::numeric, $6::numeric, $7::numeric, $8::numeric)
				ON CONFLICT (token_address, interval, open_time)
				DO UPDATE SET
					high_price = GREATEST(klines.high_price, EXCLUDED.high_price),
					low_price = LEAST(klines.low_price, EXCLUDED.low_price),
					close_price = EXCLUDED.close_price,
					volume = klines.volume + EXCLUDED.volume
			`,
				tokenAddress,           // $1: 代币地址
				interval,               // $2: 时间间隔
				openTime,               // $3: K 线起始时间
				priceStr,               // $4: 开盘价格（新记录时设置）
				priceStr,               // $5: 最高价格（与已有值取最大）
				priceStr,               // $6: 最低价格（与已有值取最小）
				priceStr,               // $7: 收盘价格（总是更新）
				tokenAmount.String(),   // $8: 成交量（累加到已有值）
			)
		} else {
			// 无事务时使用连接池直接执行（备用路径）
			// 与事务版本使用相同的 SQL，区别在于通过 db.pool.Exec 执行
			_, err = db.pool.Exec(ctx, `
				INSERT INTO klines (
					token_address, interval, open_time,
					open_price, high_price, low_price, close_price, volume
				) VALUES ($1, $2, $3, $4::numeric, $5::numeric, $6::numeric, $7::numeric, $8::numeric)
				ON CONFLICT (token_address, interval, open_time)
				DO UPDATE SET
					high_price = GREATEST(klines.high_price, EXCLUDED.high_price),
					low_price = LEAST(klines.low_price, EXCLUDED.low_price),
					close_price = EXCLUDED.close_price,
					volume = klines.volume + EXCLUDED.volume
			`,
				tokenAddress,           // $1: 代币地址
				interval,               // $2: 时间间隔
				openTime,               // $3: K 线起始时间
				priceStr,               // $4: 开盘价格
				priceStr,               // $5: 最高价格
				priceStr,               // $6: 最低价格
				priceStr,               // $7: 收盘价格
				tokenAmount.String(),   // $8: 成交量
			)
		}
		// UPSERT 逻辑详解：
		// INSERT: 如果该代币在该间隔该时间没有 K 线记录，插入新行
		//   此时 open_price = high_price = low_price = close_price = 当前价格
		// ON CONFLICT DO UPDATE: 如果已存在记录，更新：
		//   - high_price = GREATEST(已有最高价, 当前价格) -- 取最大值
		//   - low_price = LEAST(已有最低价, 当前价格)     -- 取最小值
		//   - close_price = 当前价格                       -- 总是更新为最新
		//   - volume = 已有成交量 + 当前成交量              -- 累加
		//   - open_price 不更新，保持第一笔交易的价格
		if err != nil {
			// K 线更新失败，返回错误
			return err
		}
	}

	// 所有间隔更新完成
	return nil
}

// alignTimeToInterval 将时间对齐到对应的时间间隔边界
// 参数：
//   - t: 原始时间（通常是交易发生的区块时间）
//   - interval: 时间间隔字符串（1m/5m/15m/30m/1h/4h/1d/1w）
// 返回：
//   - time.Time: 对齐后的时间（该时间间隔的起始时间）
// 对齐规则：
//   - 1m: 对齐到分钟（秒和纳秒清零）
//     例：14:37:45 -> 14:37:00
//   - 5m: 对齐到 5 分钟边界（如 00, 05, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55）
//     例：14:37:45 -> 14:35:00
//   - 15m: 对齐到 15 分钟边界（如 00, 15, 30, 45）
//     例：14:37:45 -> 14:30:00
//   - 30m: 对齐到 30 分钟边界（如 00, 30）
//     例：14:37:45 -> 14:30:00
//   - 1h: 对齐到小时（分钟及以下清零）
//     例：14:37:45 -> 14:00:00
//   - 4h: 对齐到 4 小时边界（如 00:00, 04:00, 08:00, 12:00, 16:00, 20:00）
//     例：14:37:45 -> 12:00:00
//   - 1d: 对齐到天（时分秒清零）
//     例：2024-01-15 14:37:45 -> 2024-01-15 00:00:00
//   - 1w: 对齐到周（周一零点，周日视为第 7 天）
//     例：2024-01-17 (周三) 14:37:45 -> 2024-01-15 (周一) 00:00:00
func alignTimeToInterval(t time.Time, interval string) time.Time {
	switch interval {
	case "1m":
		// 对齐到分钟：秒和纳秒清零
		// time.Date 精确构造时间，保留年月日时分，秒和纳秒设为 0
		return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), t.Minute(), 0, 0, t.Location())
	case "5m":
		// 对齐到 5 分钟：分钟数向下取整到 5 的倍数
		// 例：37 / 5 * 5 = 35
		minute := (t.Minute() / 5) * 5
		return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), minute, 0, 0, t.Location())
	case "15m":
		// 对齐到 15 分钟：分钟数向下取整到 15 的倍数
		// 例：37 / 15 * 15 = 30
		minute := (t.Minute() / 15) * 15
		return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), minute, 0, 0, t.Location())
	case "30m":
		// 对齐到 30 分钟：分钟数向下取整到 30 的倍数
		// 例：37 / 30 * 30 = 30
		minute := (t.Minute() / 30) * 30
		return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), minute, 0, 0, t.Location())
	case "1h":
		// 对齐到小时：分钟、秒、纳秒清零
		return time.Date(t.Year(), t.Month(), t.Day(), t.Hour(), 0, 0, 0, t.Location())
	case "4h":
		// 对齐到 4 小时：小时数向下取整到 4 的倍数
		// 例：14 / 4 * 4 = 12
		hour := (t.Hour() / 4) * 4
		return time.Date(t.Year(), t.Month(), t.Day(), hour, 0, 0, 0, t.Location())
	case "1d":
		// 对齐到天：时、分、秒、纳秒清零
		return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, t.Location())
	case "1w":
		// 对齐到周：回到本周一零点
		weekday := int(t.Weekday()) // 获取星期几（0=周日, 1=周一, ..., 6=周六）
		if weekday == 0 {
			weekday = 7 // 周日转换为 7，便于计算到周一的天数差
		}
		// 计算需要减去的天数：当前星期几 - 1
		// 例：周三(3) - 1 = 2，需要减去 2 天回到周一
		daysToSubtract := weekday - 1
		return time.Date(t.Year(), t.Month(), t.Day()-daysToSubtract, 0, 0, 0, 0, t.Location())
	default:
		// 未识别的间隔，返回原始时间不做对齐
		return t
	}
}
