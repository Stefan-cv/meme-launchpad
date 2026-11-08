// main 包：MEME Launchpad Indexer 服务的入口程序
// 本文件负责启动索引器服务，包括：
// 1. 解析命令行参数（配置文件路径）
// 2. 加载应用配置
// 3. 初始化日志系统
// 4. 连接数据库并初始化表结构
// 5. 创建并启动区块链事件索引器
// 6. 监听系统信号实现优雅停机
package main

// 导入所需的标准库和项目内部包
import (
	"context"  // 上下文包，用于控制 goroutine 生命周期和传递取消信号
	"flag"     // 命令行参数解析包，用于读取 -config 等启动参数
	"os"       // 操作系统包，用于接收系统信号
	"os/signal" // 信号包，用于监听 SIGINT、SIGTERM 等操作系统信号
	"syscall"  // 系统调用包，提供 SIGINT、SIGTERM 縺常量定义

	// 导入项目内部包
	"github.com/meme-launchpad/indexer/internal/config"   // 配置管理包，负责加载 YAML 配置文件
	"github.com/meme-launchpad/indexer/internal/database"  // 数据库包，封装 PostgreSQL 连接池与数据操作
	"github.com/meme-launchpad/indexer/internal/indexer"   // 索引器包，核心逻辑：监听链上事件并同步到数据库
	"github.com/meme-launchpad/indexer/internal/logger"    // 日志包，基于 zap 的结构化日志初始化
	"go.uber.org/zap" // zap 高性能结构化日志库
)

// main 函数：程序入口，执行完整的启动流程
// 整体流程：解析配置 -> 初始化日志 -> 连接数据库 -> 初始化表结构 -> 创建索引器 -> 启动索引器 -> 等待退出信号 -> 优雅停机
func main() {
	// 定义命令行参数 -config，默认值为 "config/config.yaml"，用于指定配置文件路径
	// 返回值为 *string 类型，需要在后续使用 * 解引用
	configPath := flag.String("config", "config/config.yaml", "配置文件路径")

	// 解析所有命令行参数，将值赋给对应的变量
	// 必须在访问 flag 变量之前调用，否则获取到的都是默认值
	flag.Parse()

	// 加载配置文件：读取 YAML 文件并解析为 Config 结构体
	// 如果配置文件不存在或格式错误，程序直接 panic 退出
	// panic 是合理的，因为没有配置文件服务无法启动
	cfg, err := config.Load(*configPath) // 使用 * 解引用获取配置文件路径字符串
	if err != nil {
		// 配置加载失败，直接 panic 终止程序
		// 原因：没有配置就无法连接数据库、无法连接区块链节点，服务完全不可用
		panic("Failed to load config: " + err.Error())
	}

	// 初始化 zap 结构化日志记录器
	// 传入日志配置（日志级别和输出格式）
	// 如果日志初始化失败（如配置无效），程序直接 panic 退出
	log, err := logger.New(&cfg.Log) // 传入 LogConfig 的指针，避免结构体拷贝
	if err != nil {
		// 日志初始化失败，直接 panic 终止程序
		// 原因：没有日志系统，后续问题无法排查，服务不宜继续运行
		panic("Failed to initialize logger: " + err.Error())
	}

	// defer log.Sync() 确保程序退出前将日志缓冲区中的数据刷新到输出
	// zap 的 Sync 方法会将内存中尚未写入的日志条目全部刷出
	// 忽略返回错误，因为程序即将退出，日志刷新失败影响较小
	defer log.Sync()

	// 记录服务启动信息，包含服务名称和链名称
	// 使用 zap.String 键值对的方式记录结构化日志，方便后续检索和分析
	log.Info("Starting MEME Launchpad Indexer",
		zap.String("name", cfg.Server.Name), // 服务名称，从配置文件读取
		zap.String("chain", cfg.Chain.Name), // 区块链网络名称（如 BSC），从配置文件读取
	)

	// 连接 PostgreSQL 数据库：创建连接池
	// 传入数据库配置（主机、端口、用户名、密码、数据库名等）和日志记录器
	// 数据库连接池支持最大连接数和空闲连接数配置，由 pgxpool 管理
	db, err := database.New(&cfg.Database, log) // 传入 DatabaseConfig 指针
	if err != nil {
		// 数据库连接失败，使用 Fatal 级别日志记录后退出程序
		// 原因：没有数据库连接，事件数据无法持久化，索引器无法正常工作
		log.Fatal("Failed to connect to database", zap.Error(err))
	}

	// defer db.Close() 确保程序退出前关闭数据库连接池
	// 释放所有数据库连接资源，防止连接泄漏
	defer db.Close()

	// 创建后台上下文，用于后续的数据库表结构初始化
	// context.Background() 返回一个空的上下文，作为所有上下文的根
	ctx := context.Background()

	// 初始化数据库表结构：创建所需的所有表和索引
	// 使用 CREATE TABLE IF NOT EXISTS 确保幂等性（重复执行不会报错）
	// 包括事件表、业务表、索引器状态表、K 线数据表及其索引
	if err := db.InitSchema(ctx); err != nil {
		// 表结构初始化失败，使用 Fatal 级别日志记录后退出程序
		// 原因：表结构不存在，后续的数据库操作都会失败
		log.Fatal("Failed to initialize database schema", zap.Error(err))
	}

	// 创建索引器实例：连接区块链 RPC 节点、解析合约 ABI、验证链 ID
	// 传入链配置、数据库连接、日志记录器三个依赖
	// New 函数内部会：
	//   1. 通过 ethclient.Dial 连接 RPC 节点
	//   2. 验证链 ID 是否与配置匹配（防止连错网络）
	//   3. 解析 MEMECore 合约 ABI
	idx, err := indexer.New(&cfg.Chain, db, log) // 传入 ChainConfig 指针
	if err != nil {
		// 索引器创建失败，使用 Fatal 级别日志记录后退出程序
		// 可能原因：RPC 连接失败、链 ID 不匹配、ABI 解析失败
		log.Fatal("Failed to create indexer", zap.Error(err))
	}

	// 创建带取消功能的上下文，用于优雅停机
	// context.WithCancel 返回一个上下文和取消函数
	// 当调用 cancel() 时，所有监听 ctx.Done() 的 goroutine 都会收到信号
	ctx, cancel := context.WithCancel(context.Background())

	// defer cancel() 确保程序退出前取消上下文
	// 这会通知所有使用该上下文的 goroutine 停止工作
	defer cancel()

	// 启动索引器：开始同步历史区块和监听新区块
	// Start 方法会启动两个 goroutine：
	//   1. syncHistoricalBlocks: 轮询同步历史区块事件
	//   2. watchNewBlocks: 通过 WebSocket 订阅新区块头
	if err := idx.Start(ctx); err != nil {
		// 索引器启动失败，使用 Fatal 级别日志记录后退出程序
		// 可能原因：数据库查询最后同步区块号失败
		log.Fatal("Failed to start indexer", zap.Error(err))
	}

	// 记录索引器启动成功
	log.Info("Indexer started successfully")

	// 创建操作系统信号通道，缓冲大小为 1
	// 缓冲大小 1 确保信号通知不会因为暂时无人接收而丢失
	quit := make(chan os.Signal, 1)

	// 注册监听 SIGINT（Ctrl+C）和 SIGTERM（kill 命令）信号
	// 当收到这两种信号时，会将信号写入 quit 通道
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	// 阻塞等待退出信号
	// <-quit 会从通道中读取一个信号，在此之前当前 goroutine 一直阻塞
	// 这是主 goroutine 保持运行的方式，避免程序立即退出
	<-quit

	// 收到退出信号后，记录停机开始日志
	log.Info("Shutting down indexer...")

	// 调用 cancel() 取消上下文
	// 这会通知所有监听 ctx.Done() 的 goroutine 停止工作
	// 特别是 syncHistoricalBlocks 和 watchNewBlocks 两个 goroutine
	cancel()

	// 调用 idx.Stop() 关闭索引器
	// 内部会关闭 stopCh 通道（通知 goroutine 停止）和 RPC 客户端连接
	idx.Stop()

	// 记录索引器优雅停机完成
	log.Info("Indexer stopped gracefully")
}
