// servicecontext.go - 服务上下文定义与初始化
// 本文件创建了应用运行时的全局依赖容器（ServiceContext），
// 负责在服务启动时初始化数据库连接、Redis 客户端、数据模型和业务服务，
// 并将这些依赖注入到各个 HTTP 处理函数中使用
package svc

import (
	"context" // 上下文包，用于数据库连接初始化时的超时控制
	"fmt"     // 格式化输出包，用于构建数据库连接字符串和打印错误信息
	"log"     // 日志包，用于输出签名私钥的初始化信息

	"github.com/jackc/pgx/v5/pgxpool"             // PostgreSQL 连接池驱动，提供高效的数据库连接管理
	"github.com/meme-launchpad/api/internal/config" // 配置结构体，包含所有初始化参数
	"github.com/meme-launchpad/api/internal/model"  // 数据模型包，包含各业务表的数据访问层
	"github.com/meme-launchpad/api/internal/service/chain"  // 链上事件服务，处理区块链事件数据查询
	"github.com/meme-launchpad/api/internal/service/cos"    // 腾讯云 COS 服务，处理文件上传的预签名 URL 生成
	tokenservice "github.com/meme-launchpad/api/internal/service/token" // 代币服务，处理代币创建、地址预测等核心业务
	"github.com/redis/go-redis/v9" // Redis 客户端，用于缓存 nonce、会话等临时数据
)

// ServiceContext 服务上下文结构体
// 作为全局依赖容器，持有应用运行时所需的所有数据库连接、模型实例和服务实例
// 在服务启动时创建，通过依赖注入的方式传递给各个 handler 和 logic 层
type ServiceContext struct {
	Config config.Config // 应用配置，包含数据库、Redis、链等所有配置项

	// 数据库
	DB *pgxpool.Pool // PostgreSQL 连接池，提供并发安全的数据库连接管理
	                   // pgxpool 相比单连接可以复用连接，减少频繁建立/断开连接的开销

	// Redis
	Redis *redis.Client // Redis 客户端实例，用于存储签名 nonce、缓存热点数据等

	// Models - 数据访问层，封装了对数据库表的 CRUD 操作
	UserModel     *model.UserModel     // 用户模型，操作 users 表
	TokenModel    *model.TokenModel    // 代币模型，操作 tokens 表
	TradeModel    *model.TradeModel    // 交易模型，操作 trades 表
	KlineModel    *model.KlineModel    // K线模型，操作 klines 表
	CommentModel  *model.CommentModel  // 评论模型，操作 comments 表
	ActivityModel *model.ActivityModel // 活动模型，操作 activities 表
	InviteModel   *model.InviteModel   // 邀请模型，操作 invites/agents 表

	// Services - 业务服务层，封装了复杂的业务逻辑
	TokenService *tokenservice.TokenService // 代币服务，处理代币创建签名、CREATE2 地址预测等核心逻辑
	EventService *chain.EventService       // 链上事件服务，查询代币创建/买入/卖出/毕业等链上事件
	CosService   *cos.CosService           // COS 服务，生成文件上传的预签名 URL
}

// NewServiceContext 创建并初始化服务上下文
// 参数：
//   - c: 应用配置，包含所有初始化所需的参数
// 返回：
//   - *ServiceContext: 初始化完成的服务上下文实例
// 执行流程：
//   1. 构建数据库连接字符串并创建连接池
//   2. 初始化 Redis 客户端并测试连接
//   3. 创建各数据模型实例
//   4. 创建各业务服务实例
//   5. 组装并返回 ServiceContext
func NewServiceContext(c config.Config) *ServiceContext {
	// ========== 初始化数据库连接 ==========
	// 构建 PostgreSQL 连接字符串（DSN 格式）
	// 格式：postgres://用户名:密码@主机:端口/数据库名?sslmode=SSL模式
	dbURL := fmt.Sprintf(
		"postgres://%s:%s@%s:%d/%s?sslmode=%s",
		c.Database.User,     // 数据库用户名
		c.Database.Password, // 数据库密码
		c.Database.Host,     // 数据库主机地址
		c.Database.Port,     // 数据库端口号
		c.Database.Name,     // 数据库名称
		c.Database.SSLMode,  // SSL 连接模式
	)

	// 解析连接字符串，创建连接池配置对象
	// ParseConfig 会验证连接字符串格式，并设置默认的连接池参数
	poolConfig, err := pgxpool.ParseConfig(dbURL)
	if err != nil {
		// 连接字符串格式错误，直接 panic 终止程序
		// 这种错误通常是配置文件写错了，无法恢复
		panic(fmt.Sprintf("Failed to parse database config: %v", err))
	}

	// 设置连接池的最大连接数
	// 控制同时可以有多少个活跃的数据库连接
	// 设置过高可能耗尽数据库资源，过低则成为性能瓶颈
	poolConfig.MaxConns = int32(c.Database.MaxOpenConns)
	// 设置连接池的最小空闲连接数
	// 保持一定数量的空闲连接可以减少频繁建立连接的延迟
	poolConfig.MinConns = int32(c.Database.MaxIdleConns)

	// 使用配置创建数据库连接池
	// NewWithConfig 不会立即建立所有连接，而是在需要时按需创建
	db, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		// 连接池创建失败，直接 panic 终止程序
		// 数据库是不可替代的基础设施，无法连接则服务无法运行
		panic(fmt.Sprintf("Failed to connect to database: %v", err))
	}

	// ========== 初始化 Redis ==========
	// 创建 Redis 客户端实例
	rdb := redis.NewClient(&redis.Options{
		Addr:     c.Redis.Host, // Redis 服务器地址（host:port 格式）
		Password: c.Redis.Pass, // Redis 密码，空字符串表示无密码
		DB:       c.Redis.DB,   // Redis 数据库编号（0-15）
	})

	// 测试 Redis 连接是否可用
	// 发送 PING 命令，期望返回 PONG
	if _, err := rdb.Ping(context.Background()).Result(); err != nil {
		// Redis 连接失败仅打印警告，不终止程序
		// 因为 Redis 主要用于缓存和 nonce 存储，连接失败不影响核心查询功能
		fmt.Printf("Warning: Failed to connect to Redis: %v\n", err)
	}

	// ========== 初始化 Models ==========
	// 创建代币模型和交易模型，这两个模型会被后续的 EventService 使用
	// 所以需要提前创建，而不是在最后的 return 语句中直接创建
	tokenModel := model.NewTokenModel(db)
	tradeModel := model.NewTradeModel(db)

	// 打印签名私钥的初始化信息（用于调试，生产环境应移除）
	log.Println("SignerPrivateKey: ", c.SignerPrivateKey)

	// ========== 初始化 Services ==========
	// 创建代币服务，封装了代币创建签名、CREATE2 地址预测等核心业务逻辑
	// 需要：签名私钥、核心合约地址、工厂合约地址、代币字节码、RPC 地址、链 ID、代币模型
	tokenService := tokenservice.NewTokenService(
		c.SignerPrivateKey,       // 后端签名者私钥，用于对创建代币参数进行 ECDSA 签名
		c.Chain.CoreContract,    // 核心合约地址，签名时的合约地址参数
		c.Chain.FactoryContract, // 工厂合约地址，用于 CREATE2 地址计算
		c.Chain.TokenBytecode,   // 代币合约字节码，用于 CREATE2 地址预测
		c.Chain.RPC,             // RPC 节点地址（当前未使用，预留扩展）
		c.Chain.ChainID,         // 链 ID，签名时的链标识参数
		tokenModel,              // 代币模型，用于保存创建请求和获取 nonce
	)

	// 创建链上事件服务，封装了链上事件数据的查询逻辑
	// 需要：RPC 地址、核心合约地址、代币模型、交易模型
	eventService := chain.NewEventService(
		c.Chain.RPC,          // RPC 节点地址（当前未使用，预留扩展）
		c.Chain.CoreContract, // 核心合约地址（当前未使用，预留扩展）
		tokenModel,           // 代币模型，用于获取数据库连接
		tradeModel,           // 交易模型，用于获取数据库连接
	)

	// ========== 初始化 COS 服务 ==========
	// 仅在配置了 SecretID 和 SecretKey 时才初始化 COS 服务
	// 如果未配置（如本地开发环境），CosService 将为 nil
	// 使用 CosService 前需要检查是否为 nil
	var cosService *cos.CosService
	if c.Cos.SecretID != "" && c.Cos.SecretKey != "" {
		// 创建 COS 服务实例，传入完整配置
		cosService = cos.NewCosService(c)
	}

	// ========== 组装并返回 ServiceContext ==========
	return &ServiceContext{
		Config: c,  // 保存完整配置，供后续使用
		DB:     db, // 数据库连接池
		Redis:  rdb, // Redis 客户端

		// 初始化 Models - 各业务表的数据访问层
		UserModel:     model.NewUserModel(db),     // 用户模型
		TokenModel:    tokenModel,                  // 代币模型（复用前面创建的实例）
		TradeModel:    tradeModel,                  // 交易模型（复用前面创建的实例）
		KlineModel:    model.NewKlineModel(db),     // K线模型
		CommentModel:  model.NewCommentModel(db),   // 评论模型
		ActivityModel: model.NewActivityModel(db),  // 活动模型
		InviteModel:   model.NewInviteModel(db),    // 邀请模型

		// 初始化 Services - 各业务领域的服务层
		TokenService: tokenService, // 代币服务
		EventService: eventService, // 链上事件服务
		CosService:   cosService,   // COS 对象存储服务
	}
}
