// config.go - 应用配置结构体定义
// 本文件定义了 MEME Token Launchpad API 服务所需的所有配置项
// 配置项从 YAML 配置文件中读取，对应 etc/api.yaml 文件的结构
package config

import "github.com/zeromicro/go-zero/rest" // go-zero REST 框架配置，包含 Host、Port 等服务器基础配置

// Config 应用的顶层配置结构体
// 嵌套了多个子配置模块，每个模块对应一个业务领域的配置
type Config struct {
	rest.RestConf // 嵌入 go-zero 的 REST 服务器配置，包含 Host（监听地址）、Port（监听端口）等字段

	// Auth JWT 认证相关配置
	// 用于生成和验证用户登录后的访问令牌（Access Token）和刷新令牌（Refresh Token）
	Auth struct {
		AccessSecret  string // JWT 签名密钥，用于生成和验证 Token 的签名
		                     // 必须保密，泄露后攻击者可以伪造任何用户的 Token
		AccessExpire  int64  // Access Token 的过期时间（秒）
		                     // 通常设置较短（如 3600 秒 = 1 小时），用于日常 API 访问
		RefreshExpire int64  // Refresh Token 的过期时间（秒）
		                     // 通常设置较长（如 604800 秒 = 7 天），用于无感刷新 Access Token
	}

	// Database PostgreSQL 数据库连接配置
	// 使用 pgx 驱动连接 PostgreSQL，支持连接池管理
	Database struct {
		Host         string // 数据库主机地址（如 "localhost" 或 "db.example.com"）
		Port         int    // 数据库端口号（PostgreSQL 默认为 5432）
		User         string // 数据库用户名，用于认证连接
		Password     string // 数据库密码，用于认证连接
		Name         string // 数据库名称，指定要连接的具体数据库
		SSLMode      string // SSL 连接模式（如 "disable"、"require"、"verify-full"）
		                     // 开发环境通常为 "disable"，生产环境应为 "require" 或更高
		MaxOpenConns int    // 最大打开连接数，控制数据库连接池的上限
		                     // 设置过高可能耗尽数据库资源，过低则成为性能瓶颈
		MaxIdleConns int    // 最大空闲连接数，控制连接池中保持的空闲连接数
		                     // 适当的空闲连接可以减少频繁建立连接的开销
	}

	// Redis 缓存服务配置
	// 用于存储临时数据（如签名 nonce、会话信息等）
	Redis struct {
		Host string // Redis 服务器地址（格式："host:port"，如 "localhost:6379"）
		Pass string // Redis 密码，如果未设置密码则为空字符串
		DB   int    // Redis 数据库编号（0-15），不同编号用于隔离不同环境的数据
	}

	// Chain 区块链网络配置
	// 定义了与 BSC（币安智能链）交互所需的合约地址和参数
	Chain struct {
		Name            string // 区块链网络名称（如 "BSC Testnet"、"BSC Mainnet"）
		ChainID         int64  // 区块链网络 ID
		                     // 56 = BSC 主网, 97 = BSC 测试网
		                     // 用于交易签名和防止跨链重放攻击
		RPC             string // RPC 节点地址，用于与区块链节点通信
		                     // 如 "https://bsc-dataseed.binance.org/" 或本地节点
		CoreContract    string // MEMECore 核心合约地址
		                     // 负责代币创建、交易等核心业务逻辑
		FactoryContract string // 代币工厂合约地址
		                     // 使用 CREATE2 操作码确定性部署代币合约
		HelperContract  string // 辅助合约地址
		                     // 提供辅助计算功能（如价格查询等）
		VestingContract string // 归属（锁仓）合约地址
		                     // 管理代币的锁仓和线性释放规则
		TokenBytecode   string `json:",optional"` // MEMEToken 合约字节码（用于 CREATE2 地址计算）
		                     // optional 标记表示此字段可选，配置文件中可以不提供
		                     // CREATE2 地址预测需要此字节码来计算 initcode 哈希
	}

	// Storage 对象存储配置（通用配置，当前未使用，已被 Cos 配置替代）
	Storage struct {
		Type      string // 存储类型（如 "cos"、"s3" 等）
		Bucket    string // 存储桶名称
		Region    string // 存储区域
		AccessKey string `json:",optional"` // 访问密钥 ID
		SecretKey string `json:",optional"` // 访问密钥 Secret
		Endpoint  string `json:",optional"` // 自定义端点 URL
		CDNDomain string // CDN 加速域名，用于生成文件的公开访问 URL
	}

	// 腾讯云 COS（对象存储）配置
	// 用于存储代币 Logo、Banner 等图片文件
	Cos struct {
		SecretID  string `json:",optional"` // 腾讯云 API 密钥 ID
		SecretKey string `json:",optional"` // 腾讯云 API 密钥 Secret
		Bucket    string `json:",optional"` // 存储桶名称（格式：bucket-appid）
		Region    string `json:",optional"` // 存储桶区域（如 "ap-hongkong"）
		AppID     string `json:",optional"` // 腾讯云 AppID，用于构建访问 URL
		Domain    string `json:",optional"` // 自定义域名
		                     // 如果配置了自定义域名，生成文件 URL 时使用此域名
		                     // 否则使用默认的 COS 域名
	}

	// SignerPrivateKey 后端签名者私钥（十六进制格式，可选）
	// 用于对创建代币参数进行 ECDSA 签名，合约端验证签名后才会执行创建操作
	// 安全说明：私钥严禁泄露，生产环境应通过密钥管理服务注入
	SignerPrivateKey string `json:",optional"`
}
