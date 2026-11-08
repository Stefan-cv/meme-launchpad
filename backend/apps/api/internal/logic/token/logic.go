// logic.go - 代币模块业务逻辑
// 本文件实现了代币相关的所有核心业务逻辑，包括：
// 代币列表查询、详情查询、热门推荐、趋势代币、持有者查询、
// 代币创建、CREATE2 地址计算、收藏/取消收藏、我的代币列表等
package token

import (
	"context" // 上下文包
	"math/big" // 大数运算包，用于精确的代币金额计算
	"time"    // 时间包

	"github.com/meme-launchpad/api/internal/middleware"      // 认证中间件，用于获取当前用户
	tokenservice "github.com/meme-launchpad/api/internal/service/token" // 代币服务
	"github.com/meme-launchpad/api/internal/svc"            // 服务上下文
	"github.com/meme-launchpad/api/internal/types"           // 请求/响应类型
	"github.com/zeromicro/go-zero/core/logx"                // 日志库
)

// ==================== 代币列表 ====================

// GetTokenListLogic 代币列表查询逻辑
type GetTokenListLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

// NewGetTokenListLogic 创建代币列表查询逻辑实例
func NewGetTokenListLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetTokenListLogic {
	return &GetTokenListLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetTokenList 获取代币列表
// 支持分页、排序和按发行模式筛选
// 核心业务逻辑：计算每个代币的众筹进度百分比（当前 BNB / 目标 BNB * 100）
func (l *GetTokenListLogic) GetTokenList(req *types.TokenListRequest) (*types.Response, error) {
	// 组装查询参数，传递给 TokenModel
	params := map[string]interface{}{
		"pageNo":     req.PageNo,     // 页码
		"pageSize":   req.PageSize,   // 每页数量
		"sort":       req.Sort,       // 排序方式（hot/new/marketCap）
		"launchMode": req.LaunchMode, // 发行模式筛选
	}

	// 调用 TokenModel 查询代币列表
	tokens, total, err := l.svcCtx.TokenModel.FindList(l.ctx, params)
	if err != nil {
		l.Logger.Errorf("failed to get token list: %v", err)
		return types.Error(500, "failed to get tokens"), nil
	}

	// 转换为前端所需的响应格式
	var result []map[string]interface{}
	for _, t := range tokens {
		// 计算众筹进度百分比: (bnb_current / bnb_target) * 100
		// 使用 big.Float 进行高精度计算，避免浮点数精度丢失
		progressPct := "0" // 默认进度为 0%
		if t.BnbTarget != "" && t.BnbTarget != "0" {
			// 解析当前 BNB 金额为大数
			current, _, err := new(big.Float).SetPrec(256).Parse(t.BnbCurrent, 10)
			if err == nil {
				// 解析目标 BNB 金额为大数
				target, _, err := new(big.Float).SetPrec(256).Parse(t.BnbTarget, 10)
				if err == nil && target.Sign() > 0 {
					// 计算百分比: (current / target) * 100
					percent := new(big.Float).Quo(current, target) // 除法
					percent = percent.Mul(percent, big.NewFloat(100)) // 乘以 100
					// 限制最大值为 100%（超过目标也算 100%）
					if percent.Cmp(big.NewFloat(100)) > 0 {
						percent = big.NewFloat(100)
					}
					// 格式化为保留 2 位小数的字符串
					progressPct = percent.Text('f', 2)
				}
			}
		}

		// 构建单个代币的响应数据
		item := map[string]interface{}{
			"id":          t.ID,                   // 代币 ID
			"name":        t.Name,                 // 代币名称
			"symbol":      t.Symbol,               // 代币符号
			"logo":        t.Logo,                 // Logo URL
			"tokenAddr":   t.TokenContractAddress, // 合约地址
			"launchMode":  t.LaunchMode,           // 发行模式
			"launchTime":  t.LaunchTime,           // 上线时间
			"currentBnb":  t.BnbCurrent,           // 当前已筹集 BNB
			"targetBnb":   t.BnbTarget,            // 目标 BNB
			"progressPct": progressPct,            // 进度百分比
			"marketCap":   "0",                    // 市值（占位，待实现）
			"hot":         t.Hot,                  // 热度值
			"tokenLv":     t.TokenLv,              // 代币等级
			"tokenRank":   t.TokenRank,            // 代币排名
			"createdAt":   t.CreatedAt.Format(time.RFC3339), // 创建时间
		}
		// 可选字段：只有非 NULL 时才添加到响应中
		if t.Banner.Valid {
			item["banner"] = t.Banner.String // Banner 图片 URL
		}
		if t.Description.Valid {
			item["description"] = t.Description.String // 代币描述
		}
		result = append(result, item)
	}

	// 使用统一分页格式返回
	return types.Success(types.NewPageResponse(req.PageNo, req.PageSize, total, result)), nil
}

// ==================== 代币详情 ====================

// GetTokenDetailLogic 代币详情查询逻辑
type GetTokenDetailLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetTokenDetailLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetTokenDetailLogic {
	return &GetTokenDetailLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetTokenDetail 获取代币详情
// 通过合约地址查询单个代币的完整信息，包括24小时交易统计
func (l *GetTokenDetailLogic) GetTokenDetail(req *types.TokenDetailRequest) (*types.Response, error) {
	// 根据合约地址查询代币基本信息
	token, err := l.svcCtx.TokenModel.FindByAddress(l.ctx, req.TokenAddress)
	if err != nil {
		// 代币不存在，返回 404
		return types.Error(404, "token not found"), nil
	}

	// 获取24小时交易统计（买入次数、卖出次数、总交易量）
	// 忽略错误，统计信息失败不影响详情展示
	stats, _ := l.svcCtx.TradeModel.Get24HStats(l.ctx, req.TokenAddress)

	// 计算众筹进度百分比（与列表查询相同的计算逻辑）
	progressPct := "0"
	if token.BnbTarget != "" && token.BnbTarget != "0" {
		current, _, err := new(big.Float).SetPrec(256).Parse(token.BnbCurrent, 10)
		if err == nil {
			target, _, err := new(big.Float).SetPrec(256).Parse(token.BnbTarget, 10)
			if err == nil && target.Sign() > 0 {
				percent := new(big.Float).Quo(current, target)
				percent = percent.Mul(percent, big.NewFloat(100))
				if percent.Cmp(big.NewFloat(100)) > 0 {
					percent = big.NewFloat(100)
				}
				progressPct = percent.Text('f', 2)
			}
		}
	}

	// 构建详情响应数据（比列表包含更多字段）
	result := map[string]interface{}{
		"id":                   token.ID,                   // 代币 ID
		"name":                 token.Name,                 // 名称
		"symbol":               token.Symbol,               // 符号
		"logo":                 token.Logo,                 // Logo URL
		"tokenContractAddress": token.TokenContractAddress, // 合约地址
		"creatorAddress":       token.CreatorAddress,       // 创建者地址
		"launchMode":           token.LaunchMode,           // 发行模式
		"launchTime":           token.LaunchTime,           // 上线时间
		"bnbCurrent":           token.BnbCurrent,           // 当前 BNB
		"bnbTarget":            token.BnbTarget,            // 目标 BNB
		"progressPct":          progressPct,                // 进度百分比
		"totalSupply":          token.TotalSupply,          // 总供应量
		"status":               token.Status,               // 状态（1=预售中, 2=已上线, 3=已毕业）
		"buyCount24H":          stats["buyCount"],          // 24h 买入次数
		"sellCount24H":         stats["sellCount"],         // 24h 卖出次数
		"totalVolume24H":       stats["totalVolume"],       // 24h 总交易量
		"nonce":                token.Nonce,                // CREATE2 nonce
	}

	// 可选字段处理
	if token.Banner.Valid {
		result["banner"] = token.Banner.String
	}
	if token.Description.Valid {
		result["description"] = token.Description.String
	}
	if token.Website.Valid {
		result["website"] = token.Website.String
	}
	if token.Twitter.Valid {
		result["twitter"] = token.Twitter.String
	}
	if token.Telegram.Valid {
		result["telegram"] = token.Telegram.String
	}

	return types.Success(result), nil
}

// ==================== 热门推荐 ====================

// GetHotPickLogic 热门推荐查询逻辑
type GetHotPickLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetHotPickLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetHotPickLogic {
	return &GetHotPickLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetHotPick 获取热门推荐代币
// 查询热度最高且状态为预售中或已上线的代币，限制返回数量
func (l *GetHotPickLogic) GetHotPick() (*types.Response, error) {
	// 查询热门代币，限制最多 10 条
	tokens, err := l.svcCtx.TokenModel.GetHotPick(l.ctx, 10)
	if err != nil {
		return types.Error(500, "failed to get hot picks"), nil
	}

	// 组装响应数据
	var result []map[string]interface{}
	for _, t := range tokens {
		result = append(result, map[string]interface{}{
			"tokenID":     t.ID,                   // 代币 ID
			"tokenName":   t.Name,                 // 代币名称
			"tokenSymbol": t.Symbol,               // 代币符号
			"tokenAddr":   t.TokenContractAddress, // 合约地址
			"tokenLogo":   t.Logo,                 // Logo URL
			"tokenPrice":  "0",                    // 当前价格（占位）
			"priceChange": "0",                    // 价格变化（占位）
			"marketCap":   "0",                    // 市值（占位）
			"isFavorite":  false,                  // 是否已收藏（占位）
		})
	}

	return types.Success(result), nil
}

// ==================== 趋势代币 ====================

// GetTrendingTokenLogic 趋势代币查询逻辑
type GetTrendingTokenLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetTrendingTokenLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetTrendingTokenLogic {
	return &GetTrendingTokenLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetTrendingToken 获取趋势代币
// 按 hot 字段降序排列，返回热度最高的代币
func (l *GetTrendingTokenLogic) GetTrendingToken(req *types.TokenListRequest) (*types.Response, error) {
	// 强制设置排序方式为 hot（热度排序）
	params := map[string]interface{}{
		"pageNo":   req.PageNo,
		"pageSize": req.PageSize,
		"sort":     "hot", // 固定按热度排序
	}

	tokens, total, err := l.svcCtx.TokenModel.FindList(l.ctx, params)
	if err != nil {
		return types.Error(500, "failed to get trending tokens"), nil
	}

	// 组装响应
	var result []map[string]interface{}
	for _, t := range tokens {
		result = append(result, map[string]interface{}{
			"id":         t.ID,
			"name":       t.Name,
			"symbol":     t.Symbol,
			"logo":       t.Logo,
			"tokenAddr":  t.TokenContractAddress,
			"launchMode": t.LaunchMode,
			"hot":        t.Hot,
		})
	}

	return types.Success(types.NewPageResponse(req.PageNo, req.PageSize, total, result)), nil
}

// ==================== 代币持有者 ====================

// GetTokenHoldersLogic 代币持有者查询逻辑
type GetTokenHoldersLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetTokenHoldersLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetTokenHoldersLogic {
	return &GetTokenHoldersLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetTokenHolders 获取代币持有者列表
// 查询持有指定代币的用户列表，包含持仓数量和占比
func (l *GetTokenHoldersLogic) GetTokenHolders(req *types.TokenHoldersRequest) (*types.Response, error) {
	holders, total, err := l.svcCtx.TokenModel.GetTokenHolders(l.ctx, req.TokenAddress, req.PageNo, req.PageSize)
	if err != nil {
		return types.Error(500, "failed to get holders"), nil
	}

	return types.Success(map[string]interface{}{
		"holders": holders, // 持有者列表
		"total":   total,   // 持有者总数
	}), nil
}

// ==================== 创建代币 ====================

// CreateTokenLogic 创建代币逻辑
type CreateTokenLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewCreateTokenLogic(ctx context.Context, svcCtx *svc.ServiceContext) *CreateTokenLogic {
	return &CreateTokenLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// CreateToken 创建代币的核心业务逻辑
// 这是整个平台最核心的操作，涉及：
//   - 用户身份验证
//   - CREATE2 地址预测（支持靓号搜索）
//   - 后端签名（合约验证签名后才执行创建）
//   - 请求持久化（保存创建请求到数据库）
func (l *CreateTokenLogic) CreateToken(req *types.CreateTokenRequest) (*types.Response, error) {
	// 从认证中间件注入的 Context 中获取当前用户信息
	userID := middleware.GetUserIDFromCtx(l.ctx)
	address := middleware.GetAddressFromCtx(l.ctx)

	// 验证用户是否已登录
	if userID == 0 || address == "" {
		return types.Error(401, "unauthorized"), nil
	}

	// 检查 TokenService 是否可用
	// TokenService 包含签名器和 CREATE2 计算器，是创建代币的必要条件
	if l.svcCtx.TokenService == nil {
		l.Logger.Error("TokenService is not initialized")
		return types.Error(500, "service not available"), nil
	}

	// 调用 TokenService 创建代币
	// 将 HTTP 请求参数转换为服务层参数，包括：
	//   - 基本信息（名称、符号、描述、Logo、Banner）
	//   - 发行参数（发行模式、上线时间、预购比例）
	//   - 链上参数（保证金、归属分配）
	//   - 社交链接（网站、Twitter、Telegram、Discord）
	resp, err := l.svcCtx.TokenService.CreateToken(l.ctx, &tokenservice.CreateTokenRequest{
		Name:                 req.Name,
		Symbol:               req.Symbol,
		Description:          req.Description,
		Logo:                 req.Logo,
		Banner:               req.Banner,
		Creator:              address,   // 创建者地址，从认证信息获取
		LaunchMode:           req.LaunchMode,
		LaunchTime:           req.LaunchTime,
		InitialBuyPercentage: int(req.PreBuyPercent * 10000), // 转换为 basis points（万分比）
		                     // 例如 0.5 -> 5000 (50%)
		Website:              req.Website,
		Twitter:              req.Twitter,
		Telegram:             req.Telegram,
		Discord:              req.Discord,
		Whitepaper:           req.Whitepaper,
		ContactEmail:         req.ContractEmail,
		ContactTg:            req.ContractTg,
		Tags:                 req.Tags,
		Digits:               req.Digits,           // 靓号后缀
		PredictedAddress:     req.PredictedAddress, // 预先计算的地址
	})

	if err != nil {
		l.Logger.Errorf("failed to create token: %v", err)
		return types.Error(500, "failed to create token: "+err.Error()), nil
	}

	// 返回创建结果，包含链上部署所需的所有参数
	return types.Success(types.CreateTokenResponse{
		Create2Salt:      resp.Create2Salt,      // CREATE2 salt 值
		CreateArg:        resp.CreateArg,        // ABI 编码的创建参数
		Nonce:            int(resp.Nonce),       // CREATE2 nonce
		PredictedAddress: resp.PredictedAddress, // 预测的合约地址
		RequestID:        resp.RequestID,        // 请求唯一标识
		Signature:        resp.Signature,        // 后端签名
		Timestamp:        resp.Timestamp,        // 签名时间戳
	}), nil
}

// ==================== 计算地址 ====================

// CalculateAddressLogic 计算 CREATE2 地址逻辑
type CalculateAddressLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewCalculateAddressLogic(ctx context.Context, svcCtx *svc.ServiceContext) *CalculateAddressLogic {
	return &CalculateAddressLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// CalculateAddress 计算 CREATE2 预测地址
// 用户在创建代币前可以预先知道代币合约地址
func (l *CalculateAddressLogic) CalculateAddress(req *types.CalculateAddressRequest) (*types.Response, error) {
	// 检查 TokenService 是否可用
	if l.svcCtx.TokenService == nil {
		l.Logger.Error("TokenService is not initialized")
		return types.Error(500, "service not available"), nil
	}

	// 调用 TokenService 计算预测地址
	resp, err := l.svcCtx.TokenService.CalculateAddress(l.ctx, &tokenservice.CalculateAddressRequest{
		Name:   req.Name,   // 代币名称
		Symbol: req.Symbol, // 代币符号
		Digits: req.Digits, // 靓号后缀（可选）
	})

	if err != nil {
		l.Logger.Errorf("failed to calculate address: %v", err)
		return types.Error(500, "failed to calculate address: "+err.Error()), nil
	}

	return types.Success(types.CalculateAddressResponse{
		PredictedAddress: resp.PredictedAddress, // 预测的合约地址
		Salt:             resp.Salt,             // CREATE2 salt 值
	}), nil
}

// ==================== 收藏代币 ====================

// FavoriteTokenLogic 收藏代币逻辑
type FavoriteTokenLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewFavoriteTokenLogic(ctx context.Context, svcCtx *svc.ServiceContext) *FavoriteTokenLogic {
	return &FavoriteTokenLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// FavoriteToken 收藏代币
// 将代币添加到用户的收藏列表（user_favorites 表）
func (l *FavoriteTokenLogic) FavoriteToken(req *types.FavoriteTokenRequest) (*types.Response, error) {
	// 获取当前用户 ID
	userID := middleware.GetUserIDFromCtx(l.ctx)
	if userID == 0 {
		return types.Error(401, "unauthorized"), nil
	}

	// 添加收藏记录（ON CONFLICT DO NOTHING 防止重复收藏）
	if err := l.svcCtx.TokenModel.AddFavorite(l.ctx, userID, req.TokenID); err != nil {
		return types.Error(500, "failed to add favorite"), nil
	}

	return types.Success(nil), nil
}

// ==================== 取消收藏 ====================

// UnfavoriteTokenLogic 取消收藏逻辑
type UnfavoriteTokenLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewUnfavoriteTokenLogic(ctx context.Context, svcCtx *svc.ServiceContext) *UnfavoriteTokenLogic {
	return &UnfavoriteTokenLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// UnfavoriteToken 取消收藏代币
// 从用户的收藏列表中移除指定代币
func (l *UnfavoriteTokenLogic) UnfavoriteToken(req *types.FavoriteTokenRequest) (*types.Response, error) {
	userID := middleware.GetUserIDFromCtx(l.ctx)
	if userID == 0 {
		return types.Error(401, "unauthorized"), nil
	}

	// 从 user_favorites 表删除记录
	if err := l.svcCtx.TokenModel.RemoveFavorite(l.ctx, userID, req.TokenID); err != nil {
		return types.Error(500, "failed to remove favorite"), nil
	}

	return types.Success(nil), nil
}

// ==================== 我的 IDO 列表 ====================

// GetMyIdoListLogic 我的 IDO 列表逻辑（占位实现）
type GetMyIdoListLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetMyIdoListLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetMyIdoListLogic {
	return &GetMyIdoListLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetMyIdoList 获取我的 IDO 列表（待实现）
func (l *GetMyIdoListLogic) GetMyIdoList(req *types.MyTokenListRequest) (*types.Response, error) {
	// TODO: 实现 IDO 列表查询
	return types.Success(types.NewPageResponse(req.PageNo, req.PageSize, 0, []interface{}{})), nil
}

// ==================== 我创建的代币 ====================

// GetMyCreatedTokenListLogic 我创建的代币列表逻辑（占位实现）
type GetMyCreatedTokenListLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetMyCreatedTokenListLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetMyCreatedTokenListLogic {
	return &GetMyCreatedTokenListLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetMyCreatedTokenList 获取我创建的代币列表（待实现）
func (l *GetMyCreatedTokenListLogic) GetMyCreatedTokenList(req *types.MyTokenListRequest) (*types.Response, error) {
	// TODO: 实现我创建的代币列表
	return types.Success(types.NewPageResponse(req.PageNo, req.PageSize, 0, []interface{}{})), nil
}

// ==================== 我持有的代币 ====================

// GetMyOwnedTokenListLogic 我持有的代币列表逻辑（占位实现）
type GetMyOwnedTokenListLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetMyOwnedTokenListLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetMyOwnedTokenListLogic {
	return &GetMyOwnedTokenListLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetMyOwnedTokenList 获取我持有的代币列表（待实现）
func (l *GetMyOwnedTokenListLogic) GetMyOwnedTokenList(req *types.MyTokenListRequest) (*types.Response, error) {
	// TODO: 实现我拥有的代币列表
	return types.Success(types.NewPageResponse(req.PageNo, req.PageSize, 0, []interface{}{})), nil
}

// ==================== 我的收藏代币 ====================

// GetMyFavoriteTokensLogic 我的收藏代币列表逻辑
type GetMyFavoriteTokensLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetMyFavoriteTokensLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetMyFavoriteTokensLogic {
	return &GetMyFavoriteTokensLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetMyFavoriteTokens 获取我收藏的代币列表
// 通过 JOIN user_favorites 和 tokens 表查询当前用户收藏的代币
func (l *GetMyFavoriteTokensLogic) GetMyFavoriteTokens(req *types.MyTokenListRequest) (*types.Response, error) {
	// 从 context 获取用户 ID
	// 注意：由于 JWT 解析的 Claims 类型可能是 int64 或 float64，
	// 需要尝试两种类型转换
	userId, ok := l.ctx.Value("userId").(int64)
	if !ok {
		// 尝试 float64 类型（JWT JSON 解析默认使用 float64）
		userIdFloat, ok := l.ctx.Value("userId").(float64)
		if ok {
			userId = int64(userIdFloat)
		}
	}
	if userId == 0 {
		return types.Error(401, "unauthorized"), nil
	}

	// 分页参数校验和默认值处理
	pageNo := req.PageNo
	pageSize := req.PageSize
	if pageNo < 1 {
		pageNo = 1 // 页码最小为 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20 // 每页数量限制在 1-100 之间，默认 20
	}
	offset := (pageNo - 1) * pageSize // 计算 SQL 偏移量

	// 查询总数：统计用户收藏的代币数量
	var total int
	err := l.svcCtx.DB.QueryRow(l.ctx, `
		SELECT COUNT(*) FROM user_favorites uf
		JOIN tokens t ON uf.token_id = t.id
		WHERE uf.user_id = $1
	`, userId).Scan(&total)
	if err != nil {
		l.Logger.Errorf("failed to count favorites: %v", err)
		return types.Error(500, "database error"), nil
	}

	// 查询收藏的代币详情
	// JOIN user_favorites 和 tokens 表，按收藏时间倒序排列
	rows, err := l.svcCtx.DB.Query(l.ctx, `
		SELECT t.id, t.name, t.symbol, COALESCE(t.logo, ''), t.token_contract_address,
			t.creator_address, t.launch_mode, t.launch_time,
			COALESCE(t.bnb_current, 0)::text, COALESCE(t.bnb_target, 0)::text,
			COALESCE(t.total_supply, 0)::text, COALESCE(t.status, 1),
			t.created_at, uf.created_at as favorited_at
		FROM user_favorites uf
		JOIN tokens t ON uf.token_id = t.id
		WHERE uf.user_id = $1
		ORDER BY uf.created_at DESC
		LIMIT $2 OFFSET $3
	`, userId, pageSize, offset)
	if err != nil {
		l.Logger.Errorf("failed to query favorites: %v", err)
		return types.Error(500, "database error"), nil
	}
	defer rows.Close() // 确保关闭行迭代器

	// 遍历查询结果，构建响应数据
	var tokens []map[string]interface{}
	for rows.Next() {
		var id int64
		var name, symbol, logo, tokenAddress, creatorAddress string
		var launchMode, status int
		var launchTime int64
		var bnbCurrent, bnbTarget, totalSupply string
		var createdAt, favoritedAt interface{}

		if err := rows.Scan(&id, &name, &symbol, &logo, &tokenAddress,
			&creatorAddress, &launchMode, &launchTime,
			&bnbCurrent, &bnbTarget, &totalSupply, &status,
			&createdAt, &favoritedAt); err != nil {
			l.Logger.Errorf("failed to scan row: %v", err)
			continue // 跳过扫描失败的行
		}

		tokens = append(tokens, map[string]interface{}{
			"id":                   id,
			"name":                 name,
			"symbol":               symbol,
			"logo":                 logo,
			"tokenContractAddress": tokenAddress,
			"creatorAddress":       creatorAddress,
			"launchMode":           launchMode,
			"launchTime":           launchTime,
			"bnbCurrent":           bnbCurrent,
			"bnbTarget":            bnbTarget,
			"totalSupply":          totalSupply,
			"status":               status,
			"isFavorite":           true, // 既然是收藏列表，此字段始终为 true
		})
	}

	// 确保返回非 nil 的空切片（而非 nil）
	if tokens == nil {
		tokens = []map[string]interface{}{}
	}

	return types.Success(types.NewPageResponse(pageNo, pageSize, total, tokens)), nil
}

// ==================== 排行榜代币 ====================

// GetRankingTokenListLogic 排行榜代币列表逻辑（占位实现）
type GetRankingTokenListLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetRankingTokenListLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetRankingTokenListLogic {
	return &GetRankingTokenListLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetRankingTokenList 获取排行榜代币列表（待实现）
func (l *GetRankingTokenListLogic) GetRankingTokenList(req *types.RankingTokenListRequest) (*types.Response, error) {
	// TODO: 实现排行榜代币列表
	return types.Success(types.NewPageResponse(req.PageNo, req.PageSize, 0, []interface{}{})), nil
}

// ==================== 概览排行榜 ====================

// GetOverviewRankingsLogic 概览排行榜逻辑
type GetOverviewRankingsLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetOverviewRankingsLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetOverviewRankingsLogic {
	return &GetOverviewRankingsLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetOverviewRankings 获取概览排行榜
// 返回多个维度的排行榜数据（热门、最新、涨幅最大、交易量最大、市值最大）
func (l *GetOverviewRankingsLogic) GetOverviewRankings(req *types.OverviewRankingsRequest) (*types.Response, error) {
	// 当前返回空列表，待后续实现各维度的数据查询
	return types.Success(map[string]interface{}{
		"hot":          []interface{}{}, // 热门排行
		"new":          []interface{}{}, // 最新排行
		"topGainer":    []interface{}{}, // 涨幅最大排行
		"topVolume":    []interface{}{}, // 交易量最大排行
		"topMarketCap": []interface{}{}, // 市值最大排行
	}), nil
}

// ==================== 高级筛选 ====================

// GetAdvancedTokenListLogic 高级筛选代币列表逻辑（占位实现）
type GetAdvancedTokenListLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetAdvancedTokenListLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetAdvancedTokenListLogic {
	return &GetAdvancedTokenListLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetAdvancedTokenList 获取高级筛选代币列表（待实现）
func (l *GetAdvancedTokenListLogic) GetAdvancedTokenList(req *types.AdvancedTokenListRequest) (*types.Response, error) {
	// TODO: 实现高级筛选代币列表
	return types.Success(types.NewPageResponse(req.PageNo, req.PageSize, 0, []interface{}{})), nil
}

// ==================== 交易排行榜 ====================

// GetTradeRankingsListLogic 交易排行榜列表逻辑（占位实现）
type GetTradeRankingsListLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

func NewGetTradeRankingsListLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetTradeRankingsListLogic {
	return &GetTradeRankingsListLogic{Logger: logx.WithContext(ctx), ctx: ctx, svcCtx: svcCtx}
}

// GetTradeRankingsList 获取交易排行榜列表（待实现）
func (l *GetTradeRankingsListLogic) GetTradeRankingsList(req *types.RankingTokenListRequest) (*types.Response, error) {
	// TODO: 实现交易排行榜
	return types.Success(types.NewPageResponse(req.PageNo, req.PageSize, 0, []interface{}{})), nil
}
