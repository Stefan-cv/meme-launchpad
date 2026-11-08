// logger 包：MEME Launchpad Indexer 的日志初始化模块
// 本文件负责：
// 1. 根据配置创建 zap 结构化日志记录器
// 2. 支持日志级别配置（debug/info/warn/error）
// 3. 支持输出格式配置（json/console）
// 4. 配置时间戳格式为 ISO8601
// 5. 添加调用者信息和错误级别堆栈跟踪
package logger

// 导入所需的包
import (
	"os" // 操作系统包，用于指定日志输出到标准输出

	"strings" // 字符串处理包，用于日志级别字符串的大小写不敏感匹配

	"github.com/meme-launchpad/indexer/internal/config" // 配置包，提供 LogConfig 结构体
	"go.uber.org/zap"         // zap 核心包，提供 Logger 结构体
	"go.uber.org/zap/zapcore" // zapcore 包，提供日志核心组件（编码器、写入器、级别等）
)

// New 创建 zap 日志记录器实例
// 参数：
//   - cfg: 日志配置指针，包含日志级别（Level）和输出格式（Format）
// 返回：
//   - *zap.Logger: 初始化完成的 zap 日志记录器
//   - error: 当前实现始终返回 nil（没有初始化失败的场景）
// 配置说明：
//   - Level: 控制输出哪些级别的日志
//     - debug: 输出所有级别（开发调试用）
//     - info: 输出 info/warn/error（生产环境默认）
//     - warn/warning: 输出 warn/error
//     - error: 仅输出 error
//   - Format: 控制日志的输出格式
//     - json: JSON 格式，适合生产环境（便于日志分析工具如 ELK 解析）
//     - console: 控制台格式，适合开发环境（便于人眼阅读，带颜色）
func New(cfg *config.LogConfig) (*zap.Logger, error) {
	// 解析日志级别，默认为 InfoLevel
	// 如果配置中的 Level 为空或无法识别，使用默认的 Info 级别
	level := zapcore.InfoLevel

	// 根据配置字符串（转小写后）设置日志级别
	// 使用 strings.ToLower 实现大小写不敏感匹配
	switch strings.ToLower(cfg.Level) {
	case "debug":
		// Debug 级别：输出所有日志，包括调试信息
		// 适用于开发环境，可以看到最详细的运行信息
		level = zapcore.DebugLevel
	case "info":
		// Info 级别：输出 info、warn、error 级别的日志
		// 适用于生产环境的默认级别
		level = zapcore.InfoLevel
	case "warn", "warning":
		// Warn 级别：输出 warn 和 error 级别的日志
		// 适用于需要减少日志量的场景
		// 同时接受 "warn" 和 "warning" 两种写法，提高兼容性
		level = zapcore.WarnLevel
	case "error":
		// Error 级别：仅输出 error 级别的日志
		// 适用于只关注严重错误的场景
		level = zapcore.ErrorLevel
	}

	// 配置编码器配置（EncoderConfig）
	// 编码器配置决定了日志输出的字段名和格式
	var encoderConfig zapcore.EncoderConfig
	if cfg.Format == "json" {
		// JSON 格式使用生产环境编码器配置
		// 包含完整的字段名（如 "level"、"ts"、"msg"）
		encoderConfig = zap.NewProductionEncoderConfig()
	} else {
		// 控制台格式使用开发环境编码器配置
		// 包含更易读的字段名和颜色高亮
		encoderConfig = zap.NewDevelopmentEncoderConfig()
	}

	// 覆盖时间戳字段名为 "timestamp"（更符合常见日志格式）
	// 默认生产环境使用 "ts"，开发环境使用 "T"
	// 统一改为 "timestamp" 便于日志分析工具识别
	encoderConfig.TimeKey = "timestamp"

	// 设置时间戳编码器为 ISO8601 格式
	// ISO8601 格式：2024-01-15T14:37:45.123Z
	// 相比默认的 Unix 时间戳（如 1705323465），ISO8601 更易读和解析
	encoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder

	// 创建编码器实例
	// 编码器负责将日志条目编码为特定格式的字节流
	var encoder zapcore.Encoder
	if cfg.Format == "json" {
		// JSON 编码器：输出结构化 JSON 格式
		// 示例：{"level":"info","timestamp":"2024-01-15T14:37:45.123Z","msg":"Starting indexer"}
		encoder = zapcore.NewJSONEncoder(encoderConfig)
	} else {
		// 控制台编码器：输出人类可读的文本格式
		// 示例：2024-01-15T14:37:45.123Z  INFO  Starting indexer
		encoder = zapcore.NewConsoleEncoder(encoderConfig)
	}

	// 创建 zap 核心（Core）
	// Core 是 zap 的三个基本组件的组合：
	//   1. Encoder: 编码器，决定日志格式
	//   2. WriteSyncer: 写入同步器，决定日志输出到哪里
	//   3. LevelEnabler: 级别启用器，决定哪些级别的日志被输出
	core := zapcore.NewCore(
		encoder,                    // 编码器：JSON 或控制台格式
		zapcore.AddSync(os.Stdout), // 写入同步器：输出到标准输出（控制台）
		level,                      // 级别启用器：根据配置过滤日志级别
	)
	// zapcore.AddSync(os.Stdout) 将 os.Stdout 包装为 WriteSyncer
	// 也可以替换为文件输出（如通过 os.OpenFile 打开日志文件）

	// 创建最终的 Logger 实例
	// 在 Core 基础上添加额外功能：
	logger := zap.New(core,
		zap.AddCaller(),            // 添加调用者信息（文件名和行号），便于定位日志来源
		zap.AddCallerSkip(0),       // 调用者跳过层数，0 表示显示直接调用 zap 方法的代码行
		zap.AddStacktrace(zapcore.ErrorLevel), // 在 Error 及以上级别日志中添加堆栈跟踪
	)
	// AddCaller() 效果示例：日志中会包含 caller 字段，如 "indexer/indexer.go:135"
	// AddStacktrace 效果：当发生 error 级别日志时，自动附加完整的调用堆栈
	// 这对于排查生产环境问题非常有价值

	// 返回日志记录器实例
	// 当前实现始终返回 nil 错误
	return logger, nil
}
