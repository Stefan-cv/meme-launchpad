// database 包：MEME Launchpad Indexer 的数据库连接和表结构管理模块
// 本文件负责：
// 1. 创建和管理 PostgreSQL 连接池
// 2. 初始化数据库表结构（事件表、业务表、K 线表、索引器状态表）
// 3. 创建数据库索引以提高查询性能
// 4. 管理索引器同步状态（断点续传）
package database

// 导入所需的包
import (
	"context" // 上下文包，用于传递取消信号和控制数据库操作超时
	"fmt"     // 格式化包，用于构建错误信息
	"time"    // 时间包，用于设置连接池参数和计算时间戳

	"github.com/jackc/pgx/v5/pgxpool" // pgx 连接池包，提供高性能的 PostgreSQL 连接池管理
	"github.com/meme-launchpad/indexer/internal/config" // 配置包，提供 DatabaseConfig 结构体
	"go.uber.org/zap" // zap 高性能结构化日志库
)

// DB PostgreSQL 数据库连接池封装
// 封装了 pgxpool.Pool 和 zap.Logger，提供统一的数据库操作入口
// 所有数据库操作都通过该结构体的方法进行，确保日志记录的一致性
type DB struct {
	pool   *pgxpool.Pool // pgx 连接池实例，管理多个数据库连接，支持并发安全访问
	logger *zap.Logger   // zap 日志记录器，用于记录数据库操作的运行日志和错误信息
}

// New 创建数据库连接池实例
// 参数：
//   - cfg: 数据库配置指针，包含主机、端口、用户名、密码、数据库名、连接池大小等
//   - logger: zap 日志记录器指针
// 返回：
//   - *DB: 成功时返回数据库实例指针
//   - error: 连接池配置解析失败、创建失败或连接测试失败时返回错误
// 执行流程：
//   1. 解析 DSN（数据源名称）生成连接池配置
//   2. 设置连接池参数（最大连接数、最小空闲连接数、连接生命周期等）
//   3. 创建连接池
//   4. 测试连接可用性（Ping）
//   5. 返回 DB 实例
func New(cfg *config.DatabaseConfig, logger *zap.Logger) (*DB, error) {
	// 解析 DSN 字符串为 pgxpool 配置对象
	// DSN 格式：host=xxx port=xxx user=xxx password=xxx dbname=xxx sslmode=xxx
	poolConfig, err := pgxpool.ParseConfig(cfg.DSN())
	if err != nil {
		// DSN 解析失败，返回错误
		// 常见原因：DSN 格式错误、参数缺失
		return nil, fmt.Errorf("failed to parse database config: %w", err)
	}

	// 设置连接池最大连接数
	// 控制同时可打开的数据库连接上限，防止数据库过载
	// 过大：消耗数据库资源；过小：高并发时请求排队等待
	poolConfig.MaxConns = int32(cfg.MaxOpenConns) // 从配置读取，默认 25

	// 设置连接池最小空闲连接数
	// 连接池会至少保持这么多空闲连接，减少连接建立的延迟
	// 过大：占用数据库连接资源；过小：突发请求时需要新建连接
	poolConfig.MinConns = int32(cfg.MaxIdleConns) // 从配置读取，默认 5

	// 设置连接最大生命周期为 1 小时
	// 超过此时间的连接会被关闭并重建，防止长时间复用可能的问题
	// 如：数据库端超时配置变更、网络中间件状态变化等
	poolConfig.MaxConnLifetime = time.Hour

	// 设置连接最大空闲时间为 30 分钟
	// 空闲超过此时间的连接会被关闭，释放数据库资源
	// 30 分钟是合理的平衡点：不会频繁创建销毁连接，也不会长时间占用资源
	poolConfig.MaxConnIdleTime = 30 * time.Minute

	// 使用配置创建连接池
	// NewWithConfig 会立即创建 MinConns 数量的连接
	pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		// 连接池创建失败，返回错误
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	// 测试连接是否可用
	// Ping 会尝试与数据库建立一次通信，验证连接参数是否正确
	// 使用 context.Background() 因为此时还没有业务上下文
	if err := pool.Ping(context.Background()); err != nil {
		// 连接测试失败，返回错误
		// 常见原因：主机不可达、端口错误、认证失败、数据库不存在
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// 记录数据库连接成功信息
	logger.Info("Database connected successfully",
		zap.String("host", cfg.Host),     // 数据库主机地址
		zap.Int("port", cfg.Port),         // 数据库端口号
		zap.String("database", cfg.Name),  // 数据库名称
	)

	// 返回 DB 实例，包含连接池和日志记录器
	return &DB{pool: pool, logger: logger}, nil
}

// Close 关闭数据库连接池
// 关闭连接池会释放所有连接资源（包括活跃连接和空闲连接）
// 应在服务停机时调用，通常通过 defer 注册
func (db *DB) Close() {
	db.pool.Close() // 关闭连接池，所有等待连接的操作会返回错误
}

// Pool 返回底层的 pgxpool.Pool 连接池实例
// 允许外部代码直接使用连接池执行自定义查询
// 适用于需要更灵活数据库操作的场景
func (db *DB) Pool() *pgxpool.Pool {
	return db.pool // 返回连接池指针，调用方可直接使用
}

// InitSchema 初始化数据库表结构
// 创建索引器所需的所有表和索引，使用 IF NOT EXISTS 确保幂等性
// 参数：
//   - ctx: 上下文，用于控制操作超时
// 返回：
//   - error: SQL 执行失败时返回错误
// 表结构设计说明：
//   - 事件表（4张）：存储原始链上事件的镜像，用于审计与追溯
//   - indexer_state 表：记录索引器同步进度，实现断点续传
//   - klines 表：存储 K 线（OHLCV）聚合数据，支持多时间间隔
//   - 所有事件表使用 (transaction_hash, log_index) 联合唯一约束防止重复插入
//   - NUMERIC(78, 0) 类型用于存储 uint256 值（最大 78 位数字，0 位小数）
//   - NUMERIC(78, 18) 用于存储高精度价格（18 位小数对应 ERC20 的 18 位精度）
func (db *DB) InitSchema(ctx context.Context) error {
	// 定义完整的数据库表结构 SQL
	// 使用多行字符串保持 SQL 的可读性
	schema := `
		-- token_created_events: 代币创建事件表
		-- 存储所有 TokenCreated 事件的完整数据，包括代币基本信息和创建者信息
		CREATE TABLE IF NOT EXISTS token_created_events (
			id SERIAL PRIMARY KEY,                                -- 自增主键，用于内部引用
			token_address VARCHAR(42) NOT NULL,                   -- 代币合约地址（0x 开头，42 字符）
			creator_address VARCHAR(42) NOT NULL,                 -- 创建者钱包地址
			name VARCHAR(255) NOT NULL,                           -- 代币名称（如 "Pepe Coin"）
			symbol VARCHAR(50) NOT NULL,                          -- 代币符号（如 "PEPE"）
			total_supply NUMERIC(78, 0) NOT NULL,                 -- 总供应量，NUMERIC(78,0) 可存储 uint256
			request_id VARCHAR(66) NOT NULL,                      -- 创建请求 ID（0x 开头的 bytes32 哈希）
			transaction_hash VARCHAR(66) NOT NULL,                -- 交易哈希（0x 开头，66 字符）
			block_number BIGINT NOT NULL,                         -- 区块号，用于按区块范围查询
			block_timestamp TIMESTAMP NOT NULL,                    -- 区块时间戳，用于按时间范围查询
			log_index INTEGER NOT NULL,                            -- 日志在区块内的索引
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,        -- 记录创建时间
			UNIQUE(transaction_hash, log_index)                    -- 联合唯一约束：同一交易的同一日志只记录一次
		);

		-- token_bought_events: 代币购买事件表
		-- 存储所有 TokenBought 事件的完整数据，包括交易金额和 AMM 储备量
		CREATE TABLE IF NOT EXISTS token_bought_events (
			id SERIAL PRIMARY KEY,                                -- 自增主键
			token_address VARCHAR(42) NOT NULL,                   -- 代币合约地址
			buyer_address VARCHAR(42) NOT NULL,                   -- 买家钱包地址
			bnb_amount NUMERIC(78, 0) NOT NULL,                   -- 花费的 BNB 数量（含手续费）
			token_amount NUMERIC(78, 0) NOT NULL,                 -- 获得的代币数量
			trading_fee NUMERIC(78, 0) NOT NULL DEFAULT 0,        -- 交易手续费（以 BNB 计），默认 0
			virtual_bnb_reserve NUMERIC(78, 0) NOT NULL DEFAULT 0,  -- AMM 虚拟 BNB 储备量
			virtual_token_reserve NUMERIC(78, 0) NOT NULL DEFAULT 0, -- AMM 虚拟代币储备量
			available_tokens NUMERIC(78, 0) NOT NULL DEFAULT 0,   -- 内盘剩余可购买代币数量
			collected_bnb NUMERIC(78, 0) NOT NULL DEFAULT 0,      -- 该代币累计收集的 BNB
			transaction_hash VARCHAR(66) NOT NULL,                -- 交易哈希
			block_number BIGINT NOT NULL,                         -- 区块号
			block_timestamp TIMESTAMP NOT NULL,                    -- 区块时间戳
			log_index INTEGER NOT NULL,                            -- 日志索引
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,        -- 记录创建时间
			UNIQUE(transaction_hash, log_index)                    -- 联合唯一约束
		);

		-- token_sold_events: 代币卖出事件表
		-- 存储所有 TokenSold 事件的完整数据，结构与 token_bought_events 对称
		CREATE TABLE IF NOT EXISTS token_sold_events (
			id SERIAL PRIMARY KEY,                                -- 自增主键
			token_address VARCHAR(42) NOT NULL,                   -- 代币合约地址
			seller_address VARCHAR(42) NOT NULL,                  -- 卖家钱包地址
			token_amount NUMERIC(78, 0) NOT NULL,                 -- 卖出的代币数量
			bnb_amount NUMERIC(78, 0) NOT NULL,                   -- 获得的 BNB 数量
			trading_fee NUMERIC(78, 0) NOT NULL DEFAULT 0,        -- 交易手续费
			virtual_bnb_reserve NUMERIC(78, 0) NOT NULL DEFAULT 0,  -- AMM 虚拟 BNB 储备量
			virtual_token_reserve NUMERIC(78, 0) NOT NULL DEFAULT 0, -- AMM 虚拟代币储备量
			available_tokens NUMERIC(78, 0) NOT NULL DEFAULT 0,   -- 内盘剩余可购买代币数量
			collected_bnb NUMERIC(78, 0) NOT NULL DEFAULT 0,      -- 该代币累计收集的 BNB
			transaction_hash VARCHAR(66) NOT NULL,                -- 交易哈希
			block_number BIGINT NOT NULL,                         -- 区块号
			block_timestamp TIMESTAMP NOT NULL,                    -- 区块时间戳
			log_index INTEGER NOT NULL,                            -- 日志索引
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,        -- 记录创建时间
			UNIQUE(transaction_hash, log_index)                    -- 联合唯一约束
		);

		-- token_graduated_events: 代币毕业事件表
		-- 存储所有 TokenGraduated 事件，记录代币从内盘迁移到 DEX 的信息
		CREATE TABLE IF NOT EXISTS token_graduated_events (
			id SERIAL PRIMARY KEY,                                -- 自增主键
			token_address VARCHAR(42) NOT NULL,                   -- 代币合约地址
			liquidity_bnb NUMERIC(78, 0) NOT NULL,                -- 注入 DEX 的 BNB 流动性数量
			liquidity_tokens NUMERIC(78, 0) NOT NULL,             -- 注入 DEX 的代币流动性数量
			liquidity_result NUMERIC(78, 0) NOT NULL,             -- 流动性添加结果（如 LP Token 数量）
			transaction_hash VARCHAR(66) NOT NULL,                -- 交易哈希
			block_number BIGINT NOT NULL,                         -- 区块号
			block_timestamp TIMESTAMP NOT NULL,                    -- 区块时间戳
			log_index INTEGER NOT NULL,                            -- 日志索引
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,        -- 记录创建时间
			UNIQUE(transaction_hash, log_index)                    -- 联合唯一约束
		);

		-- indexer_state: 索引器状态表
		-- 记录每个合约的最后同步区块号，实现断点续传
		-- 每个合约地址只有一条记录（UNIQUE 约束）
		CREATE TABLE IF NOT EXISTS indexer_state (
			id SERIAL PRIMARY KEY,                                -- 自增主键
			contract_address VARCHAR(42) NOT NULL,                -- 合约地址（作为状态记录的唯一标识）
			last_block_number BIGINT NOT NULL,                    -- 最后成功同步的区块号
			updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,        -- 最后更新时间
			UNIQUE(contract_address)                               -- 每个合约只保留一条状态记录
		);

		-- 索引定义：提高常用查询的性能
		-- 以下索引覆盖了 API 服务中最常见的查询模式

		-- token_created_events 表索引
		-- 按代币地址查询（如获取某代币的创建信息）
		CREATE INDEX IF NOT EXISTS idx_token_created_token_address ON token_created_events(token_address);
		-- 按创建者地址查询（如获取某用户创建的所有代币）
		CREATE INDEX IF NOT EXISTS idx_token_created_creator ON token_created_events(creator_address);
		-- 按区块号查询（如按区块范围筛选事件）
		CREATE INDEX IF NOT EXISTS idx_token_created_block ON token_created_events(block_number);

		-- token_bought_events 表索引
		-- 按代币地址查询（如获取某代币的所有购买记录）
		CREATE INDEX IF NOT EXISTS idx_token_bought_token_address ON token_bought_events(token_address);
		-- 按买家地址查询（如获取某用户的所有购买记录）
		CREATE INDEX IF NOT EXISTS idx_token_bought_buyer ON token_bought_events(buyer_address);
		-- 按区块号查询
		CREATE INDEX IF NOT EXISTS idx_token_bought_block ON token_bought_events(block_number);

		-- token_sold_events 表索引
		-- 按代币地址查询
		CREATE INDEX IF NOT EXISTS idx_token_sold_token_address ON token_sold_events(token_address);
		-- 按卖家地址查询
		CREATE INDEX IF NOT EXISTS idx_token_sold_seller ON token_sold_events(seller_address);
		-- 按区块号查询
		CREATE INDEX IF NOT EXISTS idx_token_sold_block ON token_sold_events(block_number);

		-- token_graduated_events 表索引
		-- 按代币地址查询
		CREATE INDEX IF NOT EXISTS idx_token_graduated_token_address ON token_graduated_events(token_address);
		-- 按区块号查询
		CREATE INDEX IF NOT EXISTS idx_token_graduated_block ON token_graduated_events(block_number);

		-- klines: K 线数据表
		-- 存储 OHLCV（开盘/最高/最低/收盘/成交量）聚合数据
		-- 支持多种时间间隔（1分钟到1周），用于前端绘制价格图表
		CREATE TABLE IF NOT EXISTS klines (
			id SERIAL,                                            -- 自增 ID（不作为主键，由复合主键替代）
			token_address VARCHAR(42) NOT NULL,                   -- 代币合约地址
			interval VARCHAR(10) NOT NULL,                        -- K 线时间间隔：1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w
			open_time TIMESTAMP NOT NULL,                          -- 该 K 线周期的起始时间
			open_price NUMERIC(78, 18) NOT NULL,                  -- 开盘价格（18 位小数精度，匹配 ERC20 精度）
			high_price NUMERIC(78, 18) NOT NULL,                  -- 最高价格
			low_price NUMERIC(78, 18) NOT NULL,                   -- 最低价格
			close_price NUMERIC(78, 18) NOT NULL,                 -- 收盘价格
			volume NUMERIC(78, 0) NOT NULL,                       -- 成交量（代币数量，整数）
			created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,        -- 记录创建时间
			PRIMARY KEY (id, open_time),                           -- 复合主键：id + open_time，便于分区
			UNIQUE(token_address, interval, open_time)             -- 联合唯一约束：同一代币同一间隔同一时间只一条记录
		);

		-- klines 表复合索引
		-- 使用 LOWER(token_address) 实现大小写不敏感匹配
		-- 按时间降序排列（最新的 K 线在前），这是前端图表最常见的查询顺序
		CREATE INDEX IF NOT EXISTS idx_klines_token_interval ON klines(LOWER(token_address), interval, open_time DESC);
		`

	// 执行建表 SQL
	// Exec 执行不返回行的 SQL 语句（如 CREATE TABLE、CREATE INDEX）
	// 忽略返回的影响行数，因为建表语句不需要
	_, err := db.pool.Exec(ctx, schema)
	if err != nil {
		// 建表失败，返回错误
		// 常见原因：数据库权限不足、SQL 语法错误、表已存在但结构冲突
		return fmt.Errorf("failed to initialize schema: %w", err)
	}

	// 记录表结构初始化成功
	db.logger.Info("Database schema initialized successfully")
	return nil
}

// GetLastSyncedBlock 获取指定合约最后同步的区块号
// 从 indexer_state 表查询，用于实现断点续传
// 参数：
//   - ctx: 上下文
//   - contractAddress: 合约地址（应为小写格式）
// 返回：
//   - uint64: 最后同步的区块号，如果没有记录返回 0
//   - error: 查询出错时返回错误（注意：没有记录时返回 0, nil，不是错误）
// 业务含义：
//   - 返回 0 表示从未同步过，需要从配置的 StartBlock 开始
//   - 返回非零值表示上次同步到的位置，应从该值 +1 继续
func (db *DB) GetLastSyncedBlock(ctx context.Context, contractAddress string) (uint64, error) {
	// 声明用于接收查询结果的变量
	var blockNumber uint64

	// 执行 SQL 查询，获取指定合约的最后同步区块号
	// 使用 $1 参数化查询防止 SQL 注入
	err := db.pool.QueryRow(ctx,
		"SELECT last_block_number FROM indexer_state WHERE contract_address = $1",
		contractAddress, // 合约地址参数
	).Scan(&blockNumber) // 将查询结果扫描到 blockNumber 变量

	if err != nil {
		// 查询出错，可能是没有匹配的记录（pgx.ErrNoRows）或其他数据库错误
		// 无论哪种情况，都返回 0 和 nil，表示没有同步记录
		// 这样调用方可以统一处理：0 表示从头开始同步
		return 0, nil
	}

	// 返回查询到的区块号
	return blockNumber, nil
}

// UpdateLastSyncedBlock 更新指定合约的最后同步区块号
// 使用 UPSERT（INSERT ON CONFLICT DO UPDATE）语义，确保记录存在时更新而非报错
// 参数：
//   - ctx: 上下文
//   - contractAddress: 合约地址
//   - blockNumber: 最新的已同步区块号
// 返回：
//   - error: SQL 执行失败时返回错误
// SQL 语义：
//   - INSERT: 如果该合约没有记录，插入新行
//   - ON CONFLICT (contract_address) DO UPDATE: 如果已存在，更新 last_block_number 和 updated_at
//   - 这种模式称为"UPSERT"，是 PostgreSQL 特有的语法
func (db *DB) UpdateLastSyncedBlock(ctx context.Context, contractAddress string, blockNumber uint64) error {
	// 执行 UPSERT SQL
	_, err := db.pool.Exec(ctx, `
		INSERT INTO indexer_state (contract_address, last_block_number, updated_at)
		VALUES ($1, $2, NOW())                          -- 插入新记录，updated_at 设为当前时间
		ON CONFLICT (contract_address)                   -- 当 contract_address 冲突时（已存在）
		DO UPDATE SET last_block_number = $2, updated_at = NOW() -- 更新区块号和时间戳
	`, contractAddress, blockNumber) // 参数：合约地址、区块号
	return err // 返回可能的执行错误
}
