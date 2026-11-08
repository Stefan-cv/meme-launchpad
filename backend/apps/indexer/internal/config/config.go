// config 包：MEME Launchpad Indexer 的配置管理模块
// 本文件负责：
// 1. 定义应用配置结构体（服务配置、数据库配置、链配置、日志配置）
// 2. 从 YAML 配置文件加载配置
// 3. 支持环境变量覆盖配置项
// 4. 设置配置项默认值
package config

// 导入所需的包
import (
	"fmt"     // 格式化包，用于构建 DSN 连接字符串和错误信息
	"strings" // 字符串处理包，用于创建环境变量键名替换器

	"github.com/spf13/viper" // viper 配置管理库，支持多种格式、环境变量覆盖、默认值等
)

// Config 应用顶层配置结构体
// 包含四个子配置，分别对应 YAML 文件中的 Server、Database、Chain、Log 四个顶级键
// mapstructure 标签用于 viper 反序列化时将配置键映射到结构体字段
type Config struct {
	Server   ServerConfig   `mapstructure:"Server"`   // 服务配置：服务名称、监听地址和端口
	Database DatabaseConfig `mapstructure:"Database"` // 数据库配置：PostgreSQL 连接参数和连接池设置
	Chain    ChainConfig    `mapstructure:"Chain"`    // 链配置：区块链网络参数和合约信息
	Log      LogConfig      `mapstructure:"Log"`      // 日志配置：日志级别和输出格式
}

// ServerConfig 服务配置结构体
// 定义服务自身的基本信息，用于服务注册和日志标识
type ServerConfig struct {
	Name string `mapstructure:"Name"` // 服务名称，用于日志标识和监控标签，如 "meme-indexer"
	Host string `mapstructure:"Host"` // 服务监听主机地址，如 "0.0.0.0" 或 "127.0.0.1"
	Port int    `mapstructure:"Port"` // 服务监听端口号，如 8080
}

// DatabaseConfig 数据库配置结构体
// 包含 PostgreSQL 连接所需的全部参数
// 字段与 PostgreSQL 连接字符串（DSN）中的参数一一对应
type DatabaseConfig struct {
	Host         string `mapstructure:"Host"`         // 数据库主机地址，如 "localhost" 或 "postgres-service"
	Port         int    `mapstructure:"Port"`         // 数据库端口号，PostgreSQL 默认 5432
	User         string `mapstructure:"User"`         // 数据库用户名，用于认证
	Password     string `mapstructure:"Password"`     // 数据库密码，用于认证（建议通过环境变量传入）
	Name         string `mapstructure:"Name"`         // 数据库名称，如 "meme_launchpad"
	SSLMode      string `mapstructure:"SSLMode"`      // SSL 连接模式：disable（禁用）、require（强制）、verify-ca 等
	MaxOpenConns int    `mapstructure:"MaxOpenConns"` // 最大打开连接数，控制连接池上限，防止数据库过载
	MaxIdleConns int    `mapstructure:"MaxIdleConns"` // 最大空闲连接数，控制连接池中保持的空闲连接，减少连接建立开销
}

// ChainConfig 区块链网络配置结构体
// 包含连接区块链节点和索引合约事件所需的所有参数
type ChainConfig struct {
	Name           string `mapstructure:"Name"`           // 区块链网络名称，如 "BSC"（币安智能链），用于日志标识
	ChainID        int64  `mapstructure:"ChainID"`        // 链 ID，如 BSC 主网为 56，用于验证连接的网络是否正确
	RPC            string `mapstructure:"RPC"`            // HTTP RPC 节点地址，如 "https://bsc-dataseed.binance.org"，用于查询区块和过滤日志
	WSS            string `mapstructure:"WSS"`            // WebSocket 节点地址，如 "wss://bsc-ws-node.example.com"，用于订阅新区块头
	CoreContract   string `mapstructure:"CoreContract"`   // MEMECore 合约地址，如 "0x1234..."，索引器只监听该合约的事件
	StartBlock     uint64 `mapstructure:"StartBlock"`     // 起始同步区块号，0 表示从最新区块开始，非零值用于指定历史起点
	BlockBatchSize int    `mapstructure:"BlockBatchSize"` // 每次查询的区块批量大小，默认 1000，动态调整以适应 RPC 限制
	PollInterval   int    `mapstructure:"PollInterval"`   // 轮询间隔（秒），控制历史同步的查询频率，默认 3 秒
}

// LogConfig 日志配置结构体
// 控制日志输出的详细程度和格式
type LogConfig struct {
	Level  string `mapstructure:"Level"`  // 日志级别：debug、info、warn、error，控制输出哪些级别的日志
	Format string `mapstructure:"Format"` // 输出格式：json（生产环境，便于日志分析工具解析）或 console（开发环境，便于人眼阅读）
}

// DSN 方法：生成 PostgreSQL 数据库连接字符串（Data Source Name）
// DSN 格式为：host=xxx port=xxx user=xxx password=xxx dbname=xxx sslmode=xxx
// 该方法将 DatabaseConfig 中的各字段拼接成 libpg 兼容的连接字符串
// 使用 fmt.Sprintf 进行格式化，确保参数正确插入
func (c *DatabaseConfig) DSN() string {
	// 空密码时必须省略 password= 片段：
	// pgx 对 "password= dbname=xxx" 的 keyword/value 解析会把后续参数丢弃，
	// 导致静默连到默认库（postgres）而非配置的库名
	passwordPart := ""
	if c.Password != "" {
		passwordPart = fmt.Sprintf(" password=%s", c.Password)
	}
	return fmt.Sprintf(
		"host=%s port=%d user=%s%s dbname=%s sslmode=%s",
		c.Host, c.Port, c.User, passwordPart, c.Name, c.SSLMode,
	)
}

// Load 函数：从指定路径加载 YAML 配置文件并解析为 Config 结构体
// 参数：
//   - configPath: 配置文件路径，如 "config/config.yaml"
// 返回：
//   - *Config: 解析后的配置结构体指针
//   - error: 文件读取失败、格式错误或反序列化失败时返回错误
// 加载流程：
//   1. 创建 viper 实例
//   2. 设置配置文件路径和格式
//   3. 启用环境变量覆盖（环境变量名通过 "." 到 "_" 的映射与配置键对应）
//   4. 读取并解析配置文件
//   5. 反序列化为 Config 结构体
//   6. 设置未指定配置项的默认值
func Load(configPath string) (*Config, error) {
	// 创建新的 viper 实例，避免使用全局实例带来的状态污染
	v := viper.New()

	// 设置配置文件路径，viper 会从该路径读取文件
	v.SetConfigFile(configPath)

	// 设置配置文件格式为 YAML
	// 虽然 viper 通常能根据文件扩展名自动判断，但显式设置更可靠
	v.SetConfigType("yaml")

	// 启用环境变量覆盖功能
	// 允许通过设置环境变量来覆盖 YAML 文件中的配置项
	// 例如：设置环境变量 SERVER_PORT=9090 可以覆盖 YAML 中的 Server.Port
	v.AutomaticEnv()

	// 设置环境变量键名替换规则：将配置键中的 "." 替换为 "_"
	// 这样 YAML 中的 "Database.Host" 可以通过环境变量 "DATABASE_HOST" 覆盖
	// 这是环境变量命名惯例（大写 + 下划线分隔）
	v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))

	// 读取配置文件内容
	// 如果文件不存在或读取失败，返回错误
	if err := v.ReadInConfig(); err != nil {
		return nil, fmt.Errorf("failed to read config: %w", err) // 使用 %w 包装原始错误，保留错误链
	}

	// 声明 Config 结构体变量，用于接收反序列化结果
	var cfg Config

	// 将 viper 中的配置值反序列化到 Config 结构体
	// 根据 mapstructure 标签将配置键映射到对应字段
	if err := v.Unmarshal(&cfg); err != nil {
		return nil, fmt.Errorf("failed to unmarshal config: %w", err) // 使用 %w 包装原始错误
	}

	// 以下为设置默认值的逻辑
	// 当 YAML 文件中未指定某些配置项时，使用合理的默认值
	// 默认值的选择基于经验和最佳实践

	// SSL 模式默认为 "disable"（禁用 SSL）
	// 适用场景：本地开发环境或内网部署，数据库连接不需要加密
	// 生产环境应设置为 "require" 或 "verify-full" 以确保连接安全
	if cfg.Database.SSLMode == "" {
		cfg.Database.SSLMode = "disable"
	}

	// 最大打开连接数默认为 25
	// 这个值需要平衡数据库并发能力和资源消耗
	// 25 个连接对于单个索引器服务来说足够，同时不会给数据库带来过大压力
	if cfg.Database.MaxOpenConns == 0 {
		cfg.Database.MaxOpenConns = 25
	}

	// 最大空闲连接数默认为 5
	// 保持一定数量的空闲连接可以减少频繁建立/断开连接的开销
	// 5 是一个适中的值，既能减少连接建立延迟，又不会占用过多数据库资源
	if cfg.Database.MaxIdleConns == 0 {
		cfg.Database.MaxIdleConns = 5
	}

	// 区块批量大小默认为 1000
	// 每次查询 RPC 时获取的区块范围大小
	// 1000 是大多数 BSC RPC 节点允许的合理范围
	// 索引器会根据 RPC 响应动态调整（遇 limit exceeded 时减半）
	if cfg.Chain.BlockBatchSize == 0 {
		cfg.Chain.BlockBatchSize = 1000
	}

	// 轮询间隔默认为 3 秒
	// 历史同步模式下，每隔 3 秒查询一次是否有新区块
	// 3 秒在 BSC（约 3 秒出块）上可以较及时地感知新区块
	if cfg.Chain.PollInterval == 0 {
		cfg.Chain.PollInterval = 3
	}

	// 返回配置结构体指针和 nil 错误
	return &cfg, nil
}
