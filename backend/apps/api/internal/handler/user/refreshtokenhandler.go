// refreshtokenhandler.go - 刷新令牌 HTTP 处理函数
// 处理用户使用 Refresh Token 换取新 Access Token 的请求
package user

import (
	"net/http" // HTTP 协议包

	"github.com/meme-launchpad/api/internal/logic/user" // 用户业务逻辑层
	"github.com/meme-launchpad/api/internal/svc"         // 服务上下文
	"github.com/meme-launchpad/api/internal/types"       // 请求/响应类型定义
	"github.com/zeromicro/go-zero/rest/httpx"            // go-zero HTTP 工具包
)

// RefreshTokenHandler 刷新令牌处理函数
// 接收 Refresh Token，验证其有效性后签发新的 Access Token 和 Refresh Token
// 请求体（JSON）：{ "refreshToken": "eyJhbGci..." }
// 成功响应包含新的 Token 对
func RefreshTokenHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明刷新令牌请求结构体
		var req types.RefreshTokenRequest
		// 从 JSON body 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建刷新令牌业务逻辑实例
		l := user.NewRefreshTokenLogic(r.Context(), svcCtx)
		// 执行令牌刷新逻辑（验证 Refresh Token、生成新 Token）
		resp, err := l.RefreshToken(&req)
		if err != nil {
			// 刷新失败（Token 无效或过期），返回错误
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			// 返回新的 Token 对
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}
