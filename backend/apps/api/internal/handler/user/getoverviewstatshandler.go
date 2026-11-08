// getoverviewstatshandler.go - 获取用户概览统计 HTTP 处理函数
// 处理已登录用户查询自身概览统计信息的请求
package user

import (
	"net/http" // HTTP 协议包

	"github.com/meme-launchpad/api/internal/logic/user" // 用户业务逻辑层
	"github.com/meme-launchpad/api/internal/svc"         // 服务上下文
	"github.com/meme-launchpad/api/internal/types"       // 请求/响应类型定义
	"github.com/zeromicro/go-zero/rest/httpx"            // go-zero HTTP 工具包
)

// GetOverviewStatsHandler 获取用户概览统计处理函数
// 查询用户的创建代币数、持有代币数、加热代币数等统计信息
// 需要认证：从 JWT Token 或查询参数中获取用户地址
// 查询参数：address=0x...（可选，默认使用当前登录用户地址）
func GetOverviewStatsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明概览统计请求结构体
		var req types.OverviewStatsRequest
		// 从 URL 查询参数解析请求
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建概览统计查询逻辑实例
		l := user.NewGetOverviewStatsLogic(r.Context(), svcCtx)
		// 执行查询逻辑
		resp, err := l.GetOverviewStats(&req)
		if err != nil {
			// 查询失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			// 返回统计信息
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}
