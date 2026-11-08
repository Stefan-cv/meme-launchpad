// getsignmsghandler.go - 获取签名消息 HTTP 处理函数
// 处理用户获取待签名消息的 HTTP 请求
// 这是 Web3 钱包登录流程的第一步：后端生成包含随机 nonce 的消息，前端使用钱包签名该消息
package user

import (
	"net/http" // HTTP 协议包

	"github.com/meme-launchpad/api/internal/logic/user" // 用户业务逻辑层
	"github.com/meme-launchpad/api/internal/svc"         // 服务上下文
	"github.com/meme-launchpad/api/internal/types"       // 请求/响应类型定义
	"github.com/zeromicro/go-zero/rest/httpx"            // go-zero HTTP 工具包
)

// GetSignMsgHandler 获取签名消息处理函数
// 接收钱包地址，返回包含随机 nonce 的签名消息
// 查询参数：address=0x...
// 响应包含：message（待签名的完整文本）、nonce（随机数）、expiry（过期时间戳）
func GetSignMsgHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明获取签名消息请求结构体
		var req types.GetSignMsgRequest
		// 从 URL 查询参数解析请求
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建获取签名消息业务逻辑实例
		l := user.NewGetSignMsgLogic(r.Context(), svcCtx)
		// 执行业务逻辑（验证地址、生成 nonce、构建消息、存入 Redis）
		resp, err := l.GetSignMsg(&req)
		if err != nil {
			// 生成签名消息失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			// 返回签名消息、nonce 和过期时间
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}
