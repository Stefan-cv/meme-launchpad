// walletloginhandler.go - 钱包登录 HTTP 处理函数
// 处理用户通过 Web3 钱包签名进行登录的 HTTP 请求
package user

import (
	"net/http" // HTTP 协议包

	"github.com/meme-launchpad/api/internal/logic/user" // 用户业务逻辑层
	"github.com/meme-launchpad/api/internal/svc"         // 服务上下文
	"github.com/meme-launchpad/api/internal/types"       // 请求/响应类型定义
	"github.com/zeromicro/go-zero/rest/httpx"            // go-zero HTTP 工具包
)

// WalletLoginHandler 钱包登录处理函数
// 接收用户提交的钱包地址和签名，验证签名后签发 JWT Token
// 请求体（JSON）：{ "address": "0x...", "signature": "0x..." }
// 成功响应包含 Access Token、Refresh Token 和用户信息
func WalletLoginHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明钱包登录请求结构体
		var req types.WalletLoginRequest
		// 从 JSON body 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建钱包登录业务逻辑实例
		l := user.NewWalletLoginLogic(r.Context(), svcCtx)
		// 执行钱包登录逻辑（验证签名、查找/创建用户、生成 JWT）
		resp, err := l.WalletLogin(&req)
		if err != nil {
			// 登录失败（签名无效、nonce 过期等），返回错误
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			// 登录成功，返回 Token 和用户信息
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}
