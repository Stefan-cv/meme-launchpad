// main.go - MEME Token Launchpad API 服务的入口文件
// 本文件负责启动 HTTP 服务器、加载配置、注册路由和自定义错误处理
package main

import (
	"context"  // 上下文包，用于请求级别的超时控制和值传递
	"flag"     // 命令行参数解析包，用于读取配置文件路径
	"fmt"      // 格式化输出包，用于打印启动信息
	"net/http" // HTTP 协议包，用于定义 HTTP 状态码和错误处理

	"github.com/meme-launchpad/api/internal/config"  // 配置结构体定义，对应 YAML 配置文件
	"github.com/meme-launchpad/api/internal/handler"  // 路由注册器，将 URL 映射到具体的处理函数
	"github.com/meme-launchpad/api/internal/svc"      // 服务上下文，包含数据库、Redis、模型等全局依赖
	"github.com/zeromicro/go-zero/core/conf"          // go-zero 配置加载工具，从 YAML 文件读取配置
	"github.com/zeromicro/go-zero/rest"               // go-zero REST 框架，提供 HTTP 服务器和路由功能
	"github.com/zeromicro/go-zero/rest/httpx"         // go-zero HTTP 工具包，提供请求解析和响应写入
)

// 确保 context 包被导入（编译期检查，防止未使用的导入被自动移除）
var _ = context.Background

// configFile 定义命令行参数 -f，指定配置文件路径，默认值为 "etc/api.yaml"
var configFile = flag.String("f", "etc/api.yaml", "the config file")

func main() {
	// 解析命令行参数，将 -f 的值赋给 configFile 变量
	flag.Parse()

	// 声明配置结构体变量 c，用于存储从 YAML 文件读取的配置
	var c config.Config
	// MustLoad 从配置文件加载配置到 c 中，如果加载失败则直接 panic 终止程序
	// 这样可以确保服务不会在配置错误的情况下继续运行
	conf.MustLoad(*configFile, &c)

	// 使用配置创建 REST 服务器实例
	// rest.MustNewServer 创建服务器，如果创建失败则 panic
	// rest.WithCors() 启用跨域资源共享（CORS），允许前端应用从不同域名访问 API
	server := rest.MustNewServer(c.RestConf, rest.WithCors())
	// defer 确保在 main 函数退出前调用 server.Stop()，优雅关闭服务器
	defer server.Stop()

	// 自定义全局错误处理器
	// 当业务逻辑返回 error 时，httpx 会调用此函数生成 HTTP 响应
	// 这里将所有错误统一包装为 {"code": 500, "message": "错误信息"} 的 JSON 格式
	// 注意：HTTP 状态码始终返回 200，将业务错误码放在 JSON body 中
	// 这样做是为了让前端统一处理响应格式，避免 HTTP 状态码和业务码的不一致
	httpx.SetErrorHandlerCtx(func(ctx context.Context, err error) (int, any) {
		// 返回 HTTP 200 状态码和包含业务错误码的 JSON 响应体
		return http.StatusOK, map[string]interface{}{
			"code":    500,         // 业务错误码，500 表示服务端内部错误
			"message": err.Error(), // 错误的具体信息，从 error 对象中获取
		}
	})

	// 创建服务上下文，包含所有全局依赖（数据库连接池、Redis 客户端、模型实例等）
	// NewServiceContext 会初始化数据库连接、Redis 连接、各种模型和服务
	ctx := svc.NewServiceContext(c)
	// 将所有路由注册到服务器上，包括公开接口和需要认证的接口
	// RegisterHandlers 内部会根据路由配置创建对应的 HTTP 处理函数
	handler.RegisterHandlers(server, ctx)

	// 打印服务器启动信息，显示监听地址和端口
	fmt.Printf("Starting server at %s:%d...\n", c.Host, c.Port)
	// 启动 HTTP 服务器，开始监听请求
	// Start() 会阻塞，直到服务器被关闭
	server.Start()
}
