// handlers.go - 代币模块的 HTTP 处理函数
// 本文件定义了代币相关的所有 HTTP 接口的处理函数（Handler）
// 每个 Handler 遵循相同的模式：解析请求 -> 创建逻辑实例 -> 执行业务逻辑 -> 返回响应
package token

import (
	"net/http" // HTTP 协议包，提供 ResponseWriter 和 Request 类型

	"github.com/meme-launchpad/api/internal/logic/token" // 代币业务逻辑层
	"github.com/meme-launchpad/api/internal/svc"         // 服务上下文
	"github.com/meme-launchpad/api/internal/types"       // 请求/响应类型定义
	"github.com/zeromicro/go-zero/rest/httpx"            // go-zero HTTP 工具包
)

// GetTokenListHandler 获取代币列表的处理函数
// 返回一个 http.HandlerFunc 闭包，捕获 svcCtx 依赖
func GetTokenListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明请求结构体，用于接收客户端传递的查询参数
		var req types.TokenListRequest
		// httpx.Parse 自动从 URL 查询参数中填充 req 结构体
		// 支持 form 标签指定的参数名映射
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误响应
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建代币列表查询的业务逻辑实例
		// 传入当前请求的 context（用于超时控制和值传递）和服务上下文
		l := token.NewGetTokenListLogic(r.Context(), svcCtx)
		// 执行业务逻辑，获取代币列表
		resp, err := l.GetTokenList(&req)
		if err != nil {
			// 业务逻辑执行失败，返回错误响应
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			// 业务逻辑执行成功，返回 JSON 格式的成功响应
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetTokenDetailHandler 获取代币详情的处理函数
func GetTokenDetailHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明代币详情请求结构体
		var req types.TokenDetailRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建代币详情查询的业务逻辑实例
		l := token.NewGetTokenDetailLogic(r.Context(), svcCtx)
		// 执行业务逻辑
		resp, err := l.GetTokenDetail(&req)
		if err != nil {
			// 查询失败
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			// 返回代币详情
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetHotPickHandler 获取热门推荐代币的处理函数
// 无需请求参数，直接查询热门代币列表
func GetHotPickHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 创建热门推荐查询的业务逻辑实例
		l := token.NewGetHotPickLogic(r.Context(), svcCtx)
		// 执行业务逻辑，无需传入请求参数
		resp, err := l.GetHotPick()
		if err != nil {
			// 查询失败
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			// 返回热门推荐列表
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetTrendingTokenHandler 获取趋势代币的处理函数
func GetTrendingTokenHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明代币列表请求结构体（复用，趋势代币的分页参数与普通列表相同）
		var req types.TokenListRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建趋势代币查询的业务逻辑实例
		l := token.NewGetTrendingTokenLogic(r.Context(), svcCtx)
		// 执行业务逻辑
		resp, err := l.GetTrendingToken(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetTokenHoldersHandler 获取代币持有者列表的处理函数
func GetTokenHoldersHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明代币持有者请求结构体
		var req types.TokenHoldersRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建持有者查询的业务逻辑实例
		l := token.NewGetTokenHoldersLogic(r.Context(), svcCtx)
		// 执行业务逻辑
		resp, err := l.GetTokenHolders(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// CreateTokenHandler 创建代币的处理函数
// 需要认证：从 JWT Token 中获取用户身份信息
func CreateTokenHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明创建代币请求结构体
		var req types.CreateTokenRequest
		// 解析请求参数（从 JSON body 中读取）
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建代币创建的业务逻辑实例
		l := token.NewCreateTokenLogic(r.Context(), svcCtx)
		// 执行创建逻辑（包含签名、CREATE2 地址预测、数据库存储等复杂操作）
		resp, err := l.CreateToken(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// CalculateAddressHandler 计算 CREATE2 预测地址的处理函数
// 用于在创建代币前预先知道代币合约地址
func CalculateAddressHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明计算地址请求结构体
		var req types.CalculateAddressRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建地址计算的业务逻辑实例
		l := token.NewCalculateAddressLogic(r.Context(), svcCtx)
		// 执行地址计算
		resp, err := l.CalculateAddress(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// FavoriteTokenHandler 收藏代币的处理函数
// 需要认证：从 JWT Token 中获取用户 ID
func FavoriteTokenHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明收藏请求结构体（包含代币 ID）
		var req types.FavoriteTokenRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建收藏逻辑实例
		l := token.NewFavoriteTokenLogic(r.Context(), svcCtx)
		// 执行收藏操作
		resp, err := l.FavoriteToken(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// UnfavoriteTokenHandler 取消收藏代币的处理函数
func UnfavoriteTokenHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明取消收藏请求结构体（与收藏请求结构体相同）
		var req types.FavoriteTokenRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建取消收藏逻辑实例
		l := token.NewUnfavoriteTokenLogic(r.Context(), svcCtx)
		// 执行取消收藏操作
		resp, err := l.UnfavoriteToken(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetMyIdoListHandler 获取我的 IDO 列表的处理函数
func GetMyIdoListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明我的代币列表请求结构体
		var req types.MyTokenListRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建 IDO 列表查询逻辑实例
		l := token.NewGetMyIdoListLogic(r.Context(), svcCtx)
		// 执行查询
		resp, err := l.GetMyIdoList(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetMyCreatedTokenListHandler 获取我创建的代币列表的处理函数
func GetMyCreatedTokenListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明我的代币列表请求结构体
		var req types.MyTokenListRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建我创建的代币列表查询逻辑实例
		l := token.NewGetMyCreatedTokenListLogic(r.Context(), svcCtx)
		// 执行查询
		resp, err := l.GetMyCreatedTokenList(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetMyOwnedTokenListHandler 获取我持有的代币列表的处理函数
func GetMyOwnedTokenListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明我的代币列表请求结构体
		var req types.MyTokenListRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建我持有的代币列表查询逻辑实例
		l := token.NewGetMyOwnedTokenListLogic(r.Context(), svcCtx)
		// 执行查询
		resp, err := l.GetMyOwnedTokenList(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetMyFavoriteTokensHandler 获取我收藏的代币列表的处理函数
func GetMyFavoriteTokensHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明我的代币列表请求结构体
		var req types.MyTokenListRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建我的收藏代币查询逻辑实例
		l := token.NewGetMyFavoriteTokensLogic(r.Context(), svcCtx)
		// 执行查询
		resp, err := l.GetMyFavoriteTokens(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetRankingTokenListHandler 获取排行榜代币列表的处理函数
func GetRankingTokenListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明排行榜请求结构体
		var req types.RankingTokenListRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建排行榜查询逻辑实例
		l := token.NewGetRankingTokenListLogic(r.Context(), svcCtx)
		// 执行查询
		resp, err := l.GetRankingTokenList(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetOverviewRankingsHandler 获取概览排行榜的处理函数
func GetOverviewRankingsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明概览排行榜请求结构体
		var req types.OverviewRankingsRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建概览排行榜查询逻辑实例
		l := token.NewGetOverviewRankingsLogic(r.Context(), svcCtx)
		// 执行查询
		resp, err := l.GetOverviewRankings(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetAdvancedTokenListHandler 获取高级筛选代币列表的处理函数
func GetAdvancedTokenListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明高级筛选请求结构体
		var req types.AdvancedTokenListRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建高级筛选查询逻辑实例
		l := token.NewGetAdvancedTokenListLogic(r.Context(), svcCtx)
		// 执行查询
		resp, err := l.GetAdvancedTokenList(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}

// GetTradeRankingsListHandler 获取交易排行榜列表的处理函数
func GetTradeRankingsListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 声明排行榜请求结构体（复用）
		var req types.RankingTokenListRequest
		// 解析请求参数
		if err := httpx.Parse(r, &req); err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 创建交易排行榜查询逻辑实例
		l := token.NewGetTradeRankingsListLogic(r.Context(), svcCtx)
		// 执行查询
		resp, err := l.GetTradeRankingsList(&req)
		if err != nil {
			httpx.ErrorCtx(r.Context(), w, err)
		} else {
			httpx.OkJsonCtx(r.Context(), w, resp)
		}
	}
}
