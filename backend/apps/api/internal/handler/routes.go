// routes.go - MEME Token Launchpad API 服务的路由注册中心
// 本文件负责将所有 HTTP 接口按照业务模块组织并注册到 go-zero 的 rest.Server 上，
// 同时区分公开接口（无需认证）与私有接口（需 JWT 认证）
package handler

import (
	"net/http"  // HTTP 协议包，提供 HTTP 方法和状态码常量
	"strconv"   // 字符串与数值转换包，用于解析 URL 查询参数中的数字

	"github.com/meme-launchpad/api/internal/handler/token" // 代币模块的 HTTP 处理函数
	"github.com/meme-launchpad/api/internal/handler/user"  // 用户模块的 HTTP 处理函数
	"github.com/meme-launchpad/api/internal/logic/kline"   // K线业务逻辑层
	"github.com/meme-launchpad/api/internal/middleware"     // 认证中间件
	"github.com/meme-launchpad/api/internal/svc"           // 服务上下文
	"github.com/meme-launchpad/api/internal/types"         // 请求/响应类型定义
	"github.com/zeromicro/go-zero/rest"                    // go-zero REST 框架
	"github.com/zeromicro/go-zero/rest/httpx"              // go-zero HTTP 工具包
)

/*
 * 路由架构说明：
 * - 公开接口：直接注册，任何客户端均可访问，用于浏览、查询等操作。
 * - 私有接口：通过 rest.WithMiddlewares 挂载 AuthMiddleware，验证请求头中的 JWT Token，
 *   确保只有已登录用户才能执行创建、收藏、上传等敏感操作。
 *
 * 路由前缀：所有接口统一以 /api/v1 为前缀。
 */

// RegisterHandlers 注册所有 HTTP 路由到 rest.Server
// 参数说明：
//   - server: go-zero 提供的 HTTP 服务器实例，用于添加路由规则
//   - svcCtx: 服务上下文，包含配置、数据库模型、缓存、COS 服务等全局依赖
// 执行流程：
//   1. 初始化认证中间件（基于配置的 AccessSecret 解析 JWT）
//   2. 分批注册公开路由（无需认证）
//   3. 分批注册私有路由（挂载 authMiddleware.Handle）
func RegisterHandlers(server *rest.Server, svcCtx *svc.ServiceContext) {
	// 创建认证中间件，用于校验请求中的 JWT Token
	// AccessSecret 是签名密钥，需与签发时保持一致
	authMiddleware := middleware.NewAuthMiddleware(svcCtx.Config.Auth.AccessSecret)

	// ==================== 无需认证的接口 ====================

	// User 相关 - 无需认证
	// 包含：获取签名消息、钱包登录、刷新 Token
	// 这些接口是认证流程的前置步骤，本身不需要携带 JWT
	server.AddRoutes(
		[]rest.Route{
			{
				// GET /api/v1/user/sign-msg
				// 获取钱包签名消息（包含随机 nonce），用于 Web3 钱包登录的第一步
				Method:  http.MethodGet,
				Path:    "/user/sign-msg",
				Handler: user.GetSignMsgHandler(svcCtx),
			},
			{
				// POST /api/v1/user/wallet-login
				// 钱包签名登录，验证用户的以太坊签名后签发 JWT Token
				Method:  http.MethodPost,
				Path:    "/user/wallet-login",
				Handler: user.WalletLoginHandler(svcCtx),
			},
			{
				// POST /api/v1/user/refresh-token
				// 使用 Refresh Token 换取新的 Access Token 和 Refresh Token
				Method:  http.MethodPost,
				Path:    "/user/refresh-token",
				Handler: user.RefreshTokenHandler(svcCtx),
			},
		},
		rest.WithPrefix("/api/v1"), // 所有路由添加 /api/v1 前缀
	)

	// Token 相关 - 无需认证
	// 包含：代币列表、详情、热门推荐、趋势、持有者、排行榜、概览、高级筛选等查询接口
	// 面向所有用户开放浏览，支持分页与排序
	server.AddRoutes(
		[]rest.Route{
			{
				// GET /api/v1/token/token-list
				// 获取代币列表，支持分页、排序和按发行模式筛选
				Method:  http.MethodGet,
				Path:    "/token/token-list",
				Handler: token.GetTokenListHandler(svcCtx),
			},
			{
				// GET /api/v1/token/detail
				// 获取代币详情，包含基本信息和24小时交易统计
				Method:  http.MethodGet,
				Path:    "/token/detail",
				Handler: token.GetTokenDetailHandler(svcCtx),
			},
			{
				// GET /api/v1/token/hot-pick
				// 获取热门推荐代币列表，按热度排序
				Method:  http.MethodGet,
				Path:    "/token/hot-pick",
				Handler: token.GetHotPickHandler(svcCtx),
			},
			{
				// GET /api/v1/token/trending-token
				// 获取趋势代币列表，按热度字段排序
				Method:  http.MethodGet,
				Path:    "/token/trending-token",
				Handler: token.GetTrendingTokenHandler(svcCtx),
			},
			{
				// GET /api/v1/token/holders
				// 获取代币持有者列表，包含持仓数量和占比
				Method:  http.MethodGet,
				Path:    "/token/holders",
				Handler: token.GetTokenHoldersHandler(svcCtx),
			},
			{
				// GET /api/v1/token/ranking-token-list
				// 获取排行榜代币列表（占位实现）
				Method:  http.MethodGet,
				Path:    "/token/ranking-token-list",
				Handler: token.GetRankingTokenListHandler(svcCtx),
			},
			{
				// GET /api/v1/token/overview-rankings
				// 获取概览排行榜数据，包含热门、最新、涨幅、交易量、市值排行
				Method:  http.MethodGet,
				Path:    "/token/overview-rankings",
				Handler: token.GetOverviewRankingsHandler(svcCtx),
			},
			{
				// GET /api/v1/token/advanced-token-list
				// 获取高级筛选代币列表，支持多维度筛选（占位实现）
				Method:  http.MethodGet,
				Path:    "/token/advanced-token-list",
				Handler: token.GetAdvancedTokenListHandler(svcCtx),
			},
		},
		rest.WithPrefix("/api/v1"),
	)

	// Comment 相关 - 无需认证
	// 仅开放评论列表查询，评论的增删改需认证
	server.AddRoutes(
		[]rest.Route{
			{
				// GET /api/v1/comment/list
				// 获取代币评论列表，支持分页和时间筛选
				Method:  http.MethodGet,
				Path:    "/comment/list",
				Handler: commentListHandler(svcCtx),
			},
		},
		rest.WithPrefix("/api/v1"),
	)

	// Trade 相关 - 无需认证
	// 提供交易记录查询、即将上线代币、即将满额代币、今日上线代币等公开数据
	server.AddRoutes(
		[]rest.Route{
			{
				// GET /api/v1/trade/list
				// 获取代币交易记录列表，支持分页和排序
				Method:  http.MethodGet,
				Path:    "/trade/list",
				Handler: tradeListHandler(svcCtx),
			},
			{
				// GET /api/v1/trade/upcoming-token
				// 获取即将上线的代币列表（占位实现）
				Method:  http.MethodGet,
				Path:    "/trade/upcoming-token",
				Handler: upcomingTokenHandler(svcCtx),
			},
			{
				// GET /api/v1/trade/almost-full-token
				// 获取即将满额的代币列表（占位实现）
				Method:  http.MethodGet,
				Path:    "/trade/almost-full-token",
				Handler: almostFullTokenHandler(svcCtx),
			},
			{
				// GET /api/v1/trade/today-launching-token
				// 获取今日上线的代币列表（占位实现）
				Method:  http.MethodGet,
				Path:    "/trade/today-launching-token",
				Handler: todayLaunchingTokenHandler(svcCtx),
			},
		},
		rest.WithPrefix("/api/v1"),
	)

	// Kline 相关 - 无需认证
	// 提供代币 K 线历史数据查询，支持普通分页与游标分页两种模式
	server.AddRoutes(
		[]rest.Route{
			{
				// GET /api/v1/kline/history
				// 获取 K 线历史数据（普通分页模式），需要指定时间范围
				Method:  http.MethodGet,
				Path:    "/kline/history",
				Handler: klineHistoryHandler(svcCtx),
			},
			{
				// GET /api/v1/kline/history-with-cursor
				// 获取 K 线历史数据（游标分页模式），适用于大数据量场景
				Method:  http.MethodGet,
				Path:    "/kline/history-with-cursor",
				Handler: klineHistoryWithCursorHandler(svcCtx),
			},
		},
		rest.WithPrefix("/api/v1"),
	)

	// Invite 相关 - 无需认证（部分查询接口）
	// 允许未登录用户查询某地址的邀请状态、佣金、邀请列表
	server.AddRoutes(
		[]rest.Route{
			{
				// GET /api/v1/back/user-status
				// 查询指定地址的用户代理状态（是否为代理、邀请码等）
				Method:  http.MethodGet,
				Path:    "/back/user-status",
				Handler: userStatusHandler(svcCtx),
			},
			{
				// GET /api/v1/back/user-commission
				// 查询指定地址的佣金信息（累计佣金、邀请人数等）
				Method:  http.MethodGet,
				Path:    "/back/user-commission",
				Handler: userCommissionHandler(svcCtx),
			},
			{
				// GET /api/v1/back/user-invites
				// 查询指定地址的邀请列表，支持分页
				Method:  http.MethodGet,
				Path:    "/back/user-invites",
				Handler: userInvitesHandler(svcCtx),
			},
		},
		rest.WithPrefix("/api/v1"),
	)

	// ==================== 需要认证的接口 ====================

	// User 相关 - 需要认证
	// 包含：用户概览统计、关注列表、粉丝列表
	// 通过 rest.WithMiddlewares 将 authMiddleware.Handle 注入到路由链中
	// 请求需携带有效的 JWT Token，否则返回 401
	server.AddRoutes(
		rest.WithMiddlewares(
			[]rest.Middleware{authMiddleware.Handle}, // 注入 JWT 认证中间件
			[]rest.Route{
				{
					// GET /api/v1/user/overview-stats
					// 获取用户概览统计信息（创建代币数、持有代币数等）
					Method:  http.MethodGet,
					Path:    "/user/overview-stats",
					Handler: user.GetOverviewStatsHandler(svcCtx),
				},
				{
					// GET /api/v1/user/following-list
					// 获取当前用户的关注列表（占位实现）
					Method:  http.MethodGet,
					Path:    "/user/following-list",
					Handler: followingListHandler(svcCtx),
				},
				{
					// GET /api/v1/user/followers-list
					// 获取当前用户的粉丝列表（占位实现）
					Method:  http.MethodGet,
					Path:    "/user/followers-list",
					Handler: followersListHandler(svcCtx),
				},
			}...,
		),
		rest.WithPrefix("/api/v1"),
	)

	// Token 相关 - 需要认证
	// 包含：创建代币、计算代币地址（CREATE2 预测）、收藏/取消收藏、
	//       我的 IDO 列表、我创建的代币、我持有的代币、我的收藏、交易排行
	// 这些操作涉及用户资产与链上交互，必须验证用户身份
	server.AddRoutes(
		rest.WithMiddlewares(
			[]rest.Middleware{authMiddleware.Handle}, // 注入 JWT 认证中间件
			[]rest.Route{
				{
					// POST /api/v1/token/create-token
					// 创建代币，后端签名后返回 CREATE2 部署参数
					Method:  http.MethodPost,
					Path:    "/token/create-token",
					Handler: token.CreateTokenHandler(svcCtx),
				},
				{
					// POST /api/v1/token/calculate-address
					// 计算 CREATE2 预测地址，支持靓号搜索
					Method:  http.MethodPost,
					Path:    "/token/calculate-address",
					Handler: token.CalculateAddressHandler(svcCtx),
				},
				{
					// POST /api/v1/token/favorite
					// 收藏代币，记录到 user_favorites 表
					Method:  http.MethodPost,
					Path:    "/token/favorite",
					Handler: token.FavoriteTokenHandler(svcCtx),
				},
				{
					// POST /api/v1/token/unfavorite
					// 取消收藏代币，从 user_favorites 表删除
					Method:  http.MethodPost,
					Path:    "/token/unfavorite",
					Handler: token.UnfavoriteTokenHandler(svcCtx),
				},
				{
					// GET /api/v1/token/my-ido-list
					// 获取我的 IDO 列表（占位实现）
					Method:  http.MethodGet,
					Path:    "/token/my-ido-list",
					Handler: token.GetMyIdoListHandler(svcCtx),
				},
				{
					// GET /api/v1/token/my-created-token-list
					// 获取我创建的代币列表（占位实现）
					Method:  http.MethodGet,
					Path:    "/token/my-created-token-list",
					Handler: token.GetMyCreatedTokenListHandler(svcCtx),
				},
				{
					// GET /api/v1/token/my-owned-token-list
					// 获取我持有的代币列表（占位实现）
					Method:  http.MethodGet,
					Path:    "/token/my-owned-token-list",
					Handler: token.GetMyOwnedTokenListHandler(svcCtx),
				},
				{
					// GET /api/v1/token/my-favorite-tokens
					// 获取我收藏的代币列表
					Method:  http.MethodGet,
					Path:    "/token/my-favorite-tokens",
					Handler: token.GetMyFavoriteTokensHandler(svcCtx),
				},
				{
					// GET /api/v1/token/trade-rankings-list
					// 获取交易排行榜列表（占位实现）
					Method:  http.MethodGet,
					Path:    "/token/trade-rankings-list",
					Handler: token.GetTradeRankingsListHandler(svcCtx),
				},
			}...,
		),
		rest.WithPrefix("/api/v1"),
	)

	// Comment 相关 - 需要认证
	// 包含：获取上传 URL、发表评论、发表图片评论、删除评论
	server.AddRoutes(
		rest.WithMiddlewares(
			[]rest.Middleware{authMiddleware.Handle}, // 注入 JWT 认证中间件
			[]rest.Route{
				{
					// GET /api/v1/comment/get-upload-url
					// 获取评论图片上传的预签名 URL（占位实现）
					Method:  http.MethodGet,
					Path:    "/comment/get-upload-url",
					Handler: commentUploadUrlHandler(svcCtx),
				},
				{
					// POST /api/v1/comment/post-comment
					// 发表文本评论（占位实现）
					Method:  http.MethodPost,
					Path:    "/comment/post-comment",
					Handler: postCommentHandler(svcCtx),
				},
				{
					// POST /api/v1/comment/post-img-comment
					// 发表带图片的评论（占位实现）
					Method:  http.MethodPost,
					Path:    "/comment/post-img-comment",
					Handler: postImgCommentHandler(svcCtx),
				},
				{
					// POST /api/v1/comment/delete
					// 删除评论（占位实现）
					Method:  http.MethodPost,
					Path:    "/comment/delete",
					Handler: deleteCommentHandler(svcCtx),
				},
			}...,
		),
		rest.WithPrefix("/api/v1"),
	)

	// File 相关 - 需要认证
	// 包含：获取 Token Logo、Banner、活动图片的预签名上传 URL，以及上传确认
	// 预签名 URL 由 COS（对象存储）服务生成，用于前端直传文件
	server.AddRoutes(
		rest.WithMiddlewares(
			[]rest.Middleware{authMiddleware.Handle}, // 注入 JWT 认证中间件
			[]rest.Route{
				{
					// GET /api/v1/file/token-logo-presign
					// 获取 Token Logo 上传的预签名 URL
					Method:  http.MethodGet,
					Path:    "/file/token-logo-presign",
					Handler: tokenLogoPresignHandler(svcCtx),
				},
				{
					// GET /api/v1/file/token-banner-presign
					// 获取 Token Banner 上传的预签名 URL
					Method:  http.MethodGet,
					Path:    "/file/token-banner-presign",
					Handler: tokenBannerPresignHandler(svcCtx),
				},
				{
					// GET /api/v1/file/activity-image-presign
					// 获取活动图片上传的预签名 URL
					Method:  http.MethodGet,
					Path:    "/file/activity-image-presign",
					Handler: activityImagePresignHandler(svcCtx),
				},
				{
					// POST /api/v1/file/upload-confirm
					// 确认文件上传完成（占位实现）
					Method:  http.MethodPost,
					Path:    "/file/upload-confirm",
					Handler: uploadConfirmHandler(svcCtx),
				},
			}...,
		),
		rest.WithPrefix("/api/v1"),
	)

	// Activity 相关 - 需要认证
	// 包含：查询用户参与的活动、用户创建的活动、创建新活动
	server.AddRoutes(
		rest.WithMiddlewares(
			[]rest.Middleware{authMiddleware.Handle}, // 注入 JWT 认证中间件
			[]rest.Route{
				{
					// GET /api/v1/act/user-participated
					// 获取用户参与的活动列表（占位实现）
					Method:  http.MethodGet,
					Path:    "/act/user-participated",
					Handler: userParticipatedHandler(svcCtx),
				},
				{
					// GET /api/v1/act/user-created
					// 获取用户创建的活动列表
					Method:  http.MethodGet,
					Path:    "/act/user-created",
					Handler: userCreatedHandler(svcCtx),
				},
				{
					// POST /api/v1/act/create
					// 创建新活动
					Method:  http.MethodPost,
					Path:    "/act/create",
					Handler: createActivityHandler(svcCtx),
				},
			}...,
		),
		rest.WithPrefix("/api/v1"),
	)

	// Invite 相关 - 需要认证
	// 包含：代理详情、每日佣金、每日新增代理、每日交易量、后代统计、创建返利记录、检查返利状态
	server.AddRoutes(
		rest.WithMiddlewares(
			[]rest.Middleware{authMiddleware.Handle}, // 注入 JWT 认证中间件
			[]rest.Route{
				{
					// GET /api/v1/back/agent-detail
					// 获取代理详情（占位实现）
					Method:  http.MethodGet,
					Path:    "/back/agent-detail",
					Handler: agentDetailHandler(svcCtx),
				},
				{
					// GET /api/v1/back/agent-daily-commission
					// 获取代理每日佣金统计（占位实现）
					Method:  http.MethodGet,
					Path:    "/back/agent-daily-commission",
					Handler: agentDailyCommissionHandler(svcCtx),
				},
				{
					// GET /api/v1/back/agent-daily-new-agents
					// 获取代理每日新增代理统计（占位实现）
					Method:  http.MethodGet,
					Path:    "/back/agent-daily-new-agents",
					Handler: agentDailyNewAgentsHandler(svcCtx),
				},
				{
					// GET /api/v1/back/agent-daily-trade-amount
					// 获取代理每日交易量统计（占位实现）
					Method:  http.MethodGet,
					Path:    "/back/agent-daily-trade-amount",
					Handler: agentDailyTradeAmountHandler(svcCtx),
				},
				{
					// GET /api/v1/back/agent-descendant-stats
					// 获取代理后代统计信息（占位实现）
					Method:  http.MethodGet,
					Path:    "/back/agent-descendant-stats",
					Handler: agentDescendantStatsHandler(svcCtx),
				},
				{
					// POST /api/v1/front/rebate_record
					// 创建返利记录（占位实现）
					Method:  http.MethodPost,
					Path:    "/front/rebate_record",
					Handler: createRebateRecordHandler(svcCtx),
				},
				{
					// GET /api/v1/front/rebate_record/check-status
					// 检查指定地址是否有待处理的返利记录
					Method:  http.MethodGet,
					Path:    "/front/rebate_record/check-status",
					Handler: checkRebateRecordStatusHandler(svcCtx),
				},
			}...,
		),
		rest.WithPrefix("/api/v1"),
	)
}

// ==================== 简化的 Handler 实现 ====================
// 以下 Handler 采用闭包模式，直接返回 http.HandlerFunc。
// 每个 Handler 的职责：
//   1. 解析请求参数（httpx.Parse 或 URL Query）
//   2. 调用 svcCtx 中的 Model/Service 执行业务逻辑
//   3. 组装响应数据，通过 httpx.OkJsonCtx 返回 JSON
//   4. 错误处理：参数解析失败返回 400，业务错误返回 500，均包装为统一响应格式

// commentListHandler 获取代币评论列表
// 请求参数：token_id（代币ID）、page_no、page_size、start_time（可选，时间戳筛选）
// 响应格式：{ comments: [...], total: 总数, hasMore: 是否还有更多 }
// 字段说明：
//   - holdingAmount: 评论者当前持仓数量
//   - walletAddress: 评论者钱包地址
//   - content: 文本内容（可能为空）
//   - img: 图片 URL（可能为空）
//   - createdAt: 评论创建时间（RFC3339 格式）
func commentListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 解析请求参数到 CommentListRequest 结构体
		var req types.CommentListRequest
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回 400 错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 调用 CommentModel 查询评论列表，支持分页与时间筛选
		// FindList 返回：评论列表、总数、是否有更多数据、错误
		comments, total, hasMore, err := svcCtx.CommentModel.FindList(r.Context(), req.TokenID, req.PageNo, req.PageSize, req.StartTime)
		if err != nil {
			// 数据库查询失败，返回 500 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "failed to get comments"))
			return
		}

		// 遍历查询结果，组装前端需要的字段格式
		var result []map[string]interface{}
		for _, c := range comments {
			// 构建每条评论的基础字段
			item := map[string]interface{}{
				"id":            c.ID,            // 评论 ID
				"holdingAmount": c.HoldingAmount, // 评论者当前持仓数量
				"walletAddress": c.WalletAddress, // 评论者钱包地址
				"createdAt":     c.CreatedAt.Format("2006-01-02T15:04:05Z07:00"), // 格式化为 RFC3339 时间字符串
			}
			// 文本内容可能为空（sql.NullString），需判断 Valid 标志
			// Valid=true 表示数据库中该字段非 NULL
			if c.Content.Valid {
				item["content"] = c.Content.String // 设置评论文本内容
			}
			// 图片 URL 可能为空
			if c.Img.Valid {
				item["img"] = c.Img.String // 设置评论图片 URL
			}
			result = append(result, item) // 将组装好的评论添加到结果列表
		}

		// 返回统一格式的成功响应
		httpx.OkJsonCtx(r.Context(), w, types.Success(map[string]interface{}{
			"comments": result,  // 评论列表
			"total":    total,   // 评论总数
			"hasMore":  hasMore, // 是否还有更多数据（用于前端无限滚动）
		}))
	}
}

// commentUploadUrlHandler 获取评论图片上传的预签名 URL
// 当前为占位实现，返回空值，实际应由 COS 服务生成临时上传链接
func commentUploadUrlHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空的预签名结果，实际应调用 CosService.GeneratePresignedUrl
		httpx.OkJsonCtx(r.Context(), w, types.Success(map[string]interface{}{
			"uploadUrl": "",  // 上传 URL（空表示未实现）
			"imageUrl":  "",  // 图片访问 URL（空表示未实现）
			"expiresAt": 0,   // 过期时间戳（0 表示未实现）
		}))
	}
}

// postCommentHandler 发表评论
// 当前为占位实现，实际应解析评论内容并写入数据库
func postCommentHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回评论 ID=0，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success(map[string]interface{}{"commentId": 0}))
	}
}

// postImgCommentHandler 发表带图片的评论
// 当前为占位实现
func postImgCommentHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空数据，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success(nil))
	}
}

// deleteCommentHandler 删除评论
// 当前为占位实现
func deleteCommentHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空数据，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success(nil))
	}
}

// tradeListHandler 获取代币交易记录列表
// 请求参数：token_address（代币合约地址）、page_no、page_size、order_by、order_desc
// 响应格式：分页包装的交易记录列表
// 字段说明：
//   - blockNumber: 区块高度
//   - blockTimestamp: 区块时间（RFC3339）
//   - bnbAmount: BNB 交易金额
//   - tokenAmount: 代币交易数量
//   - price: 成交价格
//   - usdAmount: 折合 USD 金额
//   - tradeType: 交易类型（10=买入, 20=卖出）
//   - transactionHash: 交易哈希
//   - userAddress: 交易者地址
func tradeListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 解析请求参数到 TradeListRequest 结构体
		var req types.TradeListRequest
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 组装查询参数，传递给 TradeModel
		// 使用 map 而非结构体是因为 FindList 方法需要灵活的参数组合
		params := map[string]interface{}{
			"tokenAddress": req.TokenAddress, // 代币合约地址
			"pageNo":       req.PageNo,       // 页码
			"pageSize":     req.PageSize,     // 每页数量
			"orderBy":      req.OrderBy,      // 排序字段
			"orderDesc":    req.OrderDesc,    // 是否降序排序
		}

		// 调用 TradeModel 查询交易记录列表
		// 返回：交易列表、总数、错误
		trades, total, err := svcCtx.TradeModel.FindList(r.Context(), params)
		if err != nil {
			// 数据库查询失败，返回 500 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "failed to get trades"))
			return
		}

		// 遍历交易记录，格式化时间字段并构建响应数据
		var result []map[string]interface{}
		for _, t := range trades {
			result = append(result, map[string]interface{}{
				"blockNumber":     t.BlockNumber,                                    // 区块高度
				"blockTimestamp":  t.BlockTimestamp.Format("2006-01-02T15:04:05Z07:00"), // 格式化区块时间
				"bnbAmount":       t.BnbAmount,      // BNB 交易金额
				"tokenAmount":     t.TokenAmount,    // 代币交易数量
				"price":           t.Price,          // 成交价格
				"usdAmount":       t.UsdAmount,      // 折合 USD 金额
				"tradeType":       t.TradeType,      // 交易类型（10=买入, 20=卖出）
				"transactionHash": t.TransactionHash, // 交易哈希
				"userAddress":     t.UserAddress,    // 交易者地址
				"tokenAddress":    t.TokenAddress,   // 代币合约地址
				"createdAt":       t.CreatedAt.Format("2006-01-02T15:04:05Z07:00"), // 格式化创建时间
			})
		}

		// 使用统一分页响应格式返回
		httpx.OkJsonCtx(r.Context(), w, types.Success(types.NewPageResponse(req.PageNo, req.PageSize, total, result)))
	}
}

// upcomingTokenHandler 获取即将上线的代币列表
// 当前为占位实现，返回空分页数据
func upcomingTokenHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空分页数据：第1页，每页10条，总数0，空列表
		httpx.OkJsonCtx(r.Context(), w, types.Success(types.NewPageResponse(1, 10, 0, []interface{}{})))
	}
}

// almostFullTokenHandler 获取即将满额的代币列表
// 当前为占位实现
func almostFullTokenHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空分页数据
		httpx.OkJsonCtx(r.Context(), w, types.Success(types.NewPageResponse(1, 10, 0, []interface{}{})))
	}
}

// todayLaunchingTokenHandler 获取今日上线的代币列表
// 当前为占位实现
func todayLaunchingTokenHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空分页数据
		httpx.OkJsonCtx(r.Context(), w, types.Success(types.NewPageResponse(1, 10, 0, []interface{}{})))
	}
}

// klineHistoryHandler 获取 K 线历史数据（普通分页模式）
// 请求参数：token_address、interval（时间间隔，如 1m/5m/1h/1d）、from、to、limit
// 业务逻辑委托给 kline.GetKlineHistoryLogic 处理
func klineHistoryHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 解析请求参数到 KlineHistoryRequest 结构体
		var req types.KlineHistoryRequest
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回 400 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(400, "invalid request parameters"))
			return
		}

		// 创建 Kline 业务逻辑实例并执行查询
		l := kline.NewGetKlineHistoryLogic(r.Context(), svcCtx)
		resp, err := l.GetKlineHistory(&req)
		if err != nil {
			// 查询失败，返回 500 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, err.Error()))
			return
		}
		// 返回查询结果（已经是 types.Response 格式）
		httpx.OkJsonCtx(r.Context(), w, resp)
	}
}

// klineHistoryWithCursorHandler 获取 K 线历史数据（游标分页模式）
// 适用于大数据量场景，通过 cursor 实现高效翻页，避免深分页性能问题
func klineHistoryWithCursorHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 解析请求参数到 KlineHistoryWithCursorRequest 结构体
		var req types.KlineHistoryWithCursorRequest
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回 400 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(400, "invalid request parameters"))
			return
		}

		// 创建 Kline 游标分页业务逻辑实例并执行查询
		l := kline.NewGetKlineHistoryWithCursorLogic(r.Context(), svcCtx)
		resp, err := l.GetKlineHistoryWithCursor(&req)
		if err != nil {
			// 查询失败，返回 500 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, err.Error()))
			return
		}
		// 返回查询结果
		httpx.OkJsonCtx(r.Context(), w, resp)
	}
}

// tokenLogoPresignHandler 获取 Token Logo 上传的预签名 URL
// 请求参数（Query）：mimeType（文件类型，默认 png）、chainId（链ID，默认 97 BSC 测试网）
// 响应：uploadUrl（临时上传地址）、imageUrl（访问地址）、expiresAt（过期时间）
// 错误处理：
//   - COS 服务未配置时返回 500
//   - 生成失败时返回 500
func tokenLogoPresignHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 从 URL 查询参数获取文件 MIME 类型
		mimeType := r.URL.Query().Get("mimeType")
		// 从 URL 查询参数获取链 ID
		chainIdStr := r.URL.Query().Get("chainId")
		// 如果未指定 MIME 类型，默认使用 png
		if mimeType == "" {
			mimeType = "png"
		}
		// 默认链 ID 为 97（BSC 测试网）
		chainId := 97
		// 尝试将链 ID 字符串转换为整数
		if chainIdStr != "" {
			if id, err := strconv.Atoi(chainIdStr); err == nil {
				chainId = id // 转换成功，使用用户指定的链 ID
			}
		}

		// 检查 COS 服务是否已初始化
		// 如果配置中未提供 SecretID/SecretKey，CosService 为 nil
		if svcCtx.CosService == nil {
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "COS service not configured"))
			return
		}

		// 调用 COS 服务生成预签名 URL（有效期通常为数分钟）
		// "token-logo" 是 COS 存储桶中的目录名
		result, err := svcCtx.CosService.GeneratePresignedUrl("token-logo", mimeType, chainId)
		if err != nil {
			// 生成预签名 URL 失败，返回 500 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "failed to generate presigned url"))
			return
		}

		// 返回预签名 URL 结果
		httpx.OkJsonCtx(r.Context(), w, types.Success(result))
	}
}

// tokenBannerPresignHandler 获取 Token Banner 上传的预签名 URL
// 逻辑与 tokenLogoPresignHandler 完全一致，仅 bucket 目录不同
func tokenBannerPresignHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 从 URL 查询参数获取文件 MIME 类型
		mimeType := r.URL.Query().Get("mimeType")
		// 从 URL 查询参数获取链 ID
		chainIdStr := r.URL.Query().Get("chainId")
		// 默认 MIME 类型为 png
		if mimeType == "" {
			mimeType = "png"
		}
		// 默认链 ID 为 97（BSC 测试网）
		chainId := 97
		if chainIdStr != "" {
			if id, err := strconv.Atoi(chainIdStr); err == nil {
				chainId = id
			}
		}

		// 检查 COS 服务是否已初始化
		if svcCtx.CosService == nil {
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "COS service not configured"))
			return
		}

		// 调用 COS 服务生成预签名 URL
		// "token-banner" 是 Banner 图片的存储目录名
		result, err := svcCtx.CosService.GeneratePresignedUrl("token-banner", mimeType, chainId)
		if err != nil {
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "failed to generate presigned url"))
			return
		}

		httpx.OkJsonCtx(r.Context(), w, types.Success(result))
	}
}

// activityImagePresignHandler 获取活动图片上传的预签名 URL
// 逻辑同上，bucket 目录为 activity-image
func activityImagePresignHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 从 URL 查询参数获取文件 MIME 类型
		mimeType := r.URL.Query().Get("mimeType")
		// 从 URL 查询参数获取链 ID
		chainIdStr := r.URL.Query().Get("chainId")
		// 默认 MIME 类型为 png
		if mimeType == "" {
			mimeType = "png"
		}
		// 默认链 ID 为 97（BSC 测试网）
		chainId := 97
		if chainIdStr != "" {
			if id, err := strconv.Atoi(chainIdStr); err == nil {
				chainId = id
			}
		}

		// 检查 COS 服务是否已初始化
		if svcCtx.CosService == nil {
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "COS service not configured"))
			return
		}

		// 调用 COS 服务生成预签名 URL
		// "activity-image" 是活动图片的存储目录名
		result, err := svcCtx.CosService.GeneratePresignedUrl("activity-image", mimeType, chainId)
		if err != nil {
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "failed to generate presigned url"))
			return
		}

		httpx.OkJsonCtx(r.Context(), w, types.Success(result))
	}
}

// uploadConfirmHandler 确认文件上传完成
// 当前为占位实现，实际应校验文件是否已上传到 COS 并更新数据库记录
func uploadConfirmHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空数据，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success(nil))
	}
}

// Activity handlers

// userParticipatedHandler 获取用户参与的活动列表
// 当前为占位实现
func userParticipatedHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空分页数据
		httpx.OkJsonCtx(r.Context(), w, types.Success(types.NewPageResponse(1, 10, 0, []interface{}{})))
	}
}

// userCreatedHandler 获取用户创建的活动列表
// 当前为占位实现
func userCreatedHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空分页数据
		httpx.OkJsonCtx(r.Context(), w, types.Success(types.NewPageResponse(1, 10, 0, []interface{}{})))
	}
}

// createActivityHandler 创建新活动
// 当前为占位实现
func createActivityHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回占位的活动 ID 和状态
		// status=1 通常表示活动创建成功/进行中
		httpx.OkJsonCtx(r.Context(), w, types.Success(map[string]interface{}{
			"activityId": 0, // 活动ID（0 表示占位）
			"status":     1, // 活动状态（1=进行中）
		}))
	}
}

// User handlers

// followingListHandler 获取当前用户的关注列表
// 当前为占位实现
func followingListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空分页数据
		httpx.OkJsonCtx(r.Context(), w, types.Success(types.NewPageResponse(1, 10, 0, []interface{}{})))
	}
}

// followersListHandler 获取当前用户的粉丝列表
// 当前为占位实现
func followersListHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空分页数据
		httpx.OkJsonCtx(r.Context(), w, types.Success(types.NewPageResponse(1, 10, 0, []interface{}{})))
	}
}

// Invite handlers

// userStatusHandler 查询指定地址的用户邀请状态
// 请求参数：address（钱包地址）
// 响应：用户的代理等级、邀请码、上级邀请人等状态信息
func userStatusHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 解析请求参数到 UserStatusRequest 结构体
		var req types.UserStatusRequest
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 查询 InviteModel 获取用户邀请状态
		// 返回是否为代理、邀请码、地址等信息
		status, err := svcCtx.InviteModel.GetUserStatus(r.Context(), req.Address)
		if err != nil {
			// 数据库查询失败，返回 500 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "failed to get user status"))
			return
		}

		// 返回用户邀请状态信息
		httpx.OkJsonCtx(r.Context(), w, types.Success(status))
	}
}

// userCommissionHandler 查询指定地址的佣金信息
// 请求参数：address（钱包地址）
// 响应：累计佣金、可提现佣金、已提现佣金等
func userCommissionHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 解析请求参数到 UserStatusRequest 结构体（复用同一结构体，因为参数都是 address）
		var req types.UserStatusRequest
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 查询 InviteModel 获取用户佣金信息
		commission, err := svcCtx.InviteModel.GetUserCommission(r.Context(), req.Address)
		if err != nil {
			// 数据库查询失败，返回 500 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "failed to get commission"))
			return
		}

		// 返回佣金信息
		httpx.OkJsonCtx(r.Context(), w, types.Success(commission))
	}
}

// userInvitesHandler 查询指定地址的邀请列表
// 请求参数：address（钱包地址）、page、size（分页参数）
// 响应：邀请记录列表与总数
func userInvitesHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 解析请求参数到 UserInvitesRequest 结构体
		var req types.UserInvitesRequest
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 查询 InviteModel 获取邀请列表
		// 返回：邀请记录列表、总数、错误
		invites, total, err := svcCtx.InviteModel.GetUserInvites(r.Context(), req.Address, req.Page, req.Size)
		if err != nil {
			// 数据库查询失败，返回 500 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "failed to get invites"))
			return
		}

		// 返回邀请列表和总数
		httpx.OkJsonCtx(r.Context(), w, types.Success(map[string]interface{}{
			"list":  invites, // 邀请记录列表
			"total": total,   // 邀请总数
		}))
	}
}

// agentDetailHandler 获取代理详情
// 当前为占位实现
func agentDetailHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空对象，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success(map[string]interface{}{}))
	}
}

// agentDailyCommissionHandler 获取代理每日佣金统计
// 当前为占位实现
func agentDailyCommissionHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空数组，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success([]interface{}{}))
	}
}

// agentDailyNewAgentsHandler 获取代理每日新增代理统计
// 当前为占位实现
func agentDailyNewAgentsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空数组，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success([]interface{}{}))
	}
}

// agentDailyTradeAmountHandler 获取代理每日交易量统计
// 当前为占位实现
func agentDailyTradeAmountHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空数组，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success([]interface{}{}))
	}
}

// agentDescendantStatsHandler 获取代理后代统计信息
// 当前为占位实现
func agentDescendantStatsHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空分页数据，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success(types.NewPageResponse(1, 10, 0, []interface{}{})))
	}
}

// createRebateRecordHandler 创建返利记录
// 当前为占位实现
func createRebateRecordHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 返回空数据，表示占位实现
		httpx.OkJsonCtx(r.Context(), w, types.Success(nil))
	}
}

// checkRebateRecordStatusHandler 检查返利记录状态
// 请求参数：address（钱包地址）
// 响应：是否有待处理的返利记录（布尔值）
func checkRebateRecordStatusHandler(svcCtx *svc.ServiceContext) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 解析请求参数到 UserStatusRequest 结构体（复用结构体，参数都是 address）
		var req types.UserStatusRequest
		if err := httpx.Parse(r, &req); err != nil {
			// 参数解析失败，返回错误
			httpx.ErrorCtx(r.Context(), w, err)
			return
		}

		// 查询 InviteModel 检查是否有待处理的返利记录
		// status=0 表示待处理，status=1 表示已完成
		hasPending, err := svcCtx.InviteModel.CheckRebateRecordStatus(r.Context(), req.Address)
		if err != nil {
			// 数据库查询失败，返回 500 错误
			httpx.OkJsonCtx(r.Context(), w, types.Error(500, "failed to check status"))
			return
		}

		// 返回是否有待处理的返利记录（true/false）
		httpx.OkJsonCtx(r.Context(), w, types.Success(hasPending))
	}
}
