// types.go - API 请求/响应类型定义
// 本文件定义了所有 HTTP 接口的请求参数结构体和响应格式
// 是前端与后端之间的数据契约
package types

// Response 通用 API 响应结构体
// 所有接口统一使用此结构体返回数据，保证前端处理逻辑一致
type Response struct {
	Code    int         `json:"code"`              // 业务状态码：200=成功，400=参数错误，401=未认证，500=服务端错误
	Message string      `json:"message"`           // 状态描述信息，成功时为 "success"，失败时为具体错误信息
	Data    interface{} `json:"data,omitempty"`    // 响应数据，成功时携带业务数据，失败时省略（omitempty）
}

// Success 创建成功响应
// 参数：data - 业务数据（可以是任意类型）
// 返回：状态码 200，消息 "success"，携带数据的 Response
func Success(data interface{}) *Response {
	return &Response{
		Code:    200,        // 200 表示业务成功
		Message: "success",  // 成功消息
		Data:    data,       // 业务数据
	}
}

// Error 创建错误响应
// 参数：code - 业务错误码，message - 错误描述
// 返回：携带错误码和消息的 Response，不包含 Data 字段
func Error(code int, message string) *Response {
	return &Response{
		Code:    code,    // 业务错误码
		Message: message, // 错误描述信息
	}
}

// PageResponse 分页响应结构体
// 用于统一所有分页查询接口的响应格式
type PageResponse struct {
	PageNo    int         `json:"pageNo"`              // 当前页码（从 1 开始）
	PageSize  int         `json:"pageSize"`            // 每页数量
	Total     int         `json:"total"`               // 总记录数
	TotalPage int         `json:"totalPage"`           // 总页数（由总数和每页数量计算得出）
	Result    interface{} `json:"result,omitempty"`    // 分页数据（兼容旧字段名）
	List      interface{} `json:"list,omitempty"`      // 分页数据（推荐使用此字段名）
}

// NewPageResponse 创建分页响应
// 参数：pageNo - 当前页码，pageSize - 每页数量，total - 总记录数，data - 当前页数据
// 返回：计算好总页数的分页响应实例
func NewPageResponse(pageNo, pageSize, total int, data interface{}) *PageResponse {
	// 计算总页数：总数除以每页数量，有余数则加 1
	totalPage := total / pageSize
	if total%pageSize > 0 {
		totalPage++ // 有余数，总页数加 1
	}
	return &PageResponse{
		PageNo:    pageNo,    // 当前页码
		PageSize:  pageSize,  // 每页数量
		Total:     total,     // 总记录数
		TotalPage: totalPage, // 计算得出的总页数
		Result:    data,      // 分页数据（兼容字段）
	}
}

// ==================== 请求/响应类型 ====================

// GetSignMsgRequest 获取签名消息请求
// 用于 Web3 钱包登录的第一步：获取待签名的消息
type GetSignMsgRequest struct {
	Address string `form:"address"` // 用户钱包地址（以太坊格式，0x 开头的 42 字符字符串）
}

// GetSignMsgResponse 获取签名消息响应
// 返回给前端的待签名消息和相关信息
type GetSignMsgResponse struct {
	Message string `json:"message"` // 完整的签名消息文本，用户需在钱包中签名此消息
	Nonce   string `json:"nonce"`   // 随机 nonce 值，防止重放攻击，登录时需与签名一起提交
	Expiry  int64  `json:"expiry"`  // 消息过期时间（Unix 时间戳），5 分钟后 nonce 失效
}

// WalletLoginRequest 钱包登录请求
// 用户使用 Web3 钱包签名后提交
type WalletLoginRequest struct {
	Address   string `json:"address"`   // 用户钱包地址
	Signature string `json:"signature"` // 用户对签名消息的以太坊签名（65 字节，hex 编码）
}

// LoginResponse 登录响应
// 登录成功后返回的 Token 和用户信息
type LoginResponse struct {
	Token        string      `json:"token"`        // Access Token，用于日常 API 访问认证
	RefreshToken string      `json:"refreshToken"` // Refresh Token，用于无感刷新 Access Token
	ExpiresIn    int64       `json:"expiresIn"`    // Access Token 的有效期（秒）
	TokenType    string      `json:"tokenType"`    // Token 类型，固定为 "Bearer"
	User         interface{} `json:"user"`         // 用户基本信息（ID、地址、用户名等）
}

// RefreshTokenRequest 刷新令牌请求
// 使用 Refresh Token 换取新的 Token 对
type RefreshTokenRequest struct {
	RefreshToken string `json:"refreshToken"` // 之前签发的 Refresh Token
}

// TokenListRequest 代币列表请求
// 用于查询代币列表，支持分页和排序
type TokenListRequest struct {
	PageNo          int    `form:"pn,default=1"`         // 页码，默认第 1 页
	PageSize        int    `form:"ps,default=10"`        // 每页数量，默认 10 条
	Sort            string `form:"sort,optional"`        // 排序方式：hot=按热度，new=按时间，marketCap=按市值
	LaunchMode      int    `form:"lunchMode,optional"`   // 发行模式筛选（注意：字段名有拼写错误，应为 launchMode）
	Status          string `form:"status,optional"`      // 代币状态筛选
	LaunchTimeStart int64  `form:"launchTimeStart,optional"` // 上线时间范围起始（Unix 时间戳）
	LaunchTimeEnd   int64  `form:"launchTimeEnd,optional"`   // 上线时间范围结束（Unix 时间戳）
}

// TokenDetailRequest 代币详情请求
// 通过代币合约地址查询详情
type TokenDetailRequest struct {
	TokenAddress string `form:"tokenAddress"` // 代币合约地址（0x 开头）
}

// TokenHoldersRequest 代币持有者请求
// 查询某代币的持有者列表，支持分页
type TokenHoldersRequest struct {
	TokenAddress string `form:"tokenAddress"`       // 代币合约地址
	PageNo       int    `form:"pn,default=1"`       // 页码
	PageSize     int    `form:"ps,default=10"`      // 每页数量
}

// CreateTokenRequest 创建代币请求
// 包含创建代币所需的所有参数
type CreateTokenRequest struct {
	Name              string    `json:"name"`                        // 代币名称（如 "Test Token"）
	Symbol            string    `json:"symbol"`                      // 代币符号（如 "TEST"）
	Description       string    `json:"description,optional"`        // 代币描述
	LaunchMode        int       `json:"launchMode"`                  // 发行模式
	LaunchTime        int64     `json:"launchTime"`                  // 上线时间（Unix 时间戳）
	Logo              string    `json:"logo"`                        // Logo 图片 URL
	Banner            string    `json:"banner,optional"`             // Banner 图片 URL
	Website           string    `json:"website,optional"`            // 官网链接
	Twitter           string    `json:"twitter,optional"`            // Twitter 链接
	Telegram          string    `json:"telegram,optional"`           // Telegram 链接
	Discord           string    `json:"discord,optional"`            // Discord 链接
	Whitepaper        string    `json:"whitepaper,optional"`         // 白皮书链接
	AdditionalLink2   string    `json:"additionalLink2,optional"`    // 附加链接
	Tags              []string  `json:"tags,optional"`               // 标签列表
	PreBuyPercent     float64   `json:"preBuyPercent"`               // 预购比例（0-1 之间的小数）
	PreBuyUsedPercent []float64 `json:"preBuyUsedPercent,optional"` // 预购使用比例列表
	PreBuyUsedType    []int     `json:"preBuyUsedType,optional"`     // 预购使用类型列表
	PreBuyLockTime    []float64 `json:"preBuyLockTime,optional"`     // 预购锁定时间列表
	PreBuyUsedName    []string  `json:"preBuyUsedName,optional"`     // 预购使用名称列表
	PreBuyUsedDesc    []string  `json:"preBuyUsedDesc,optional"`     // 预购使用描述列表
	MarginBnb         float64   `json:"marginBnb"`                   // 保证金 BNB 数量
	MarginTime        int64     `json:"marginTime"`                  // 保证金锁定时间（秒）
	ContractTg        string    `json:"contractTg,optional"`         // 联系人 Telegram
	ContractEmail     string    `json:"contractEmail,optional"`      // 联系人邮箱
	Digits            string    `json:"digits,optional"`             // 靓号后缀（用于 CREATE2 靓号搜索）
	PredictedAddress  string    `json:"predictedAddress,optional"`   // 预先计算的地址（可选）
	// IDO 模式字段
	TotalFundsRaised  float64 `json:"totalFundsRaised,optional"`   // IDO 募资总额
	FundraisingCycle  float64 `json:"fundraisingCycle,optional"`   // IDO 募资周期
	PreUserLimit      float64 `json:"preUserLimit,optional"`       // IDO 单用户限额
	UserLockupTime    float64 `json:"userLockupTime,optional"`     // IDO 用户锁仓时间
	AddLiquidity      float64 `json:"addLiquidity,optional"`       // 添加流动性比例
	ProtocolRevenue   float64 `json:"protocolRevenue,optional"`    // 协议收入比例
	CoreTeam          float64 `json:"coreTeam,optional"`           // 核心团队比例
	CommunityTreasury float64 `json:"communityTreasury,optional"`  // 社区国库比例
	BuybackReserve    float64 `json:"buybackReserve,optional"`     // 回购储备比例
}

// CreateTokenResponse 创建代币响应
// 返回创建代币所需的链上部署参数
type CreateTokenResponse struct {
	Create2Salt      string `json:"create2Salt"`      // CREATE2 的 salt 值（hex 编码），用于确定性部署
	CreateArg        string `json:"createArg"`        // ABI 编码的创建参数（hex 编码），传入合约的 data
	Nonce            int    `json:"nonce"`            // 随机数，用于 CREATE2 地址计算
	PredictedAddress string `json:"predictedAddress"` // 预测的代币合约地址
	RequestID        string `json:"requestId"`        // 请求唯一标识，链上链下关联用
	Signature        string `json:"signature"`        // 后端签名（65 字节，hex 编码），合约验证用
	Timestamp        int64  `json:"timestamp"`        // 签名时间戳（Unix 秒级）
}

// CalculateAddressRequest 计算地址请求
// 用于在创建代币前预测合约地址
type CalculateAddressRequest struct {
	Name   string `json:"name"`              // 代币名称
	Symbol string `json:"symbol"`            // 代币符号
	Digits string `json:"digits,optional"`   // 靓号后缀（可选，用于搜索特定后缀的地址）
}

// CalculateAddressResponse 计算地址响应
type CalculateAddressResponse struct {
	PredictedAddress string `json:"predictedAddress"` // 预测的合约地址
	Salt             string `json:"salt"`             // CREATE2 的 salt 值（hex 编码）
}

// FavoriteTokenRequest 收藏/取消收藏代币请求
type FavoriteTokenRequest struct {
	TokenID int64 `json:"tokenId"` // 要收藏/取消收藏的代币 ID
}

// CommentListRequest 评论列表请求
type CommentListRequest struct {
	TokenID   int64 `form:"tokenId"`             // 代币 ID
	PageNo    int   `form:"pn,default=1"`        // 页码
	PageSize  int   `form:"ps,default=20"`       // 每页数量，默认 20 条
	StartTime int64 `form:"startTime,optional"`  // 时间戳筛选，查询此时间之前的评论（用于无限滚动加载更多）
}

// PostCommentRequest 发布评论请求
type PostCommentRequest struct {
	TokenID int64  `json:"tokenId"` // 代币 ID
	Content string `json:"content"` // 评论文本内容
}

// PostImgCommentRequest 发布图片评论请求
type PostImgCommentRequest struct {
	TokenID int64  `json:"tokenId"` // 代币 ID
	Img     string `json:"img"`     // 图片 URL
}

// DeleteCommentRequest 删除评论请求
type DeleteCommentRequest struct {
	CommentID int64 `json:"commentId"` // 要删除的评论 ID
}

// TradeListRequest 交易列表请求
type TradeListRequest struct {
	TokenAddress string  `form:"tokenAddress"`            // 代币合约地址
	PageNo       int     `form:"pn,default=1"`            // 页码
	PageSize     int     `form:"ps,default=10"`           // 每页数量
	OrderBy      string  `form:"orderBy,optional"`        // 排序字段：usd_amount、token_amount、bnb_amount
	OrderDesc    bool    `form:"orderDesc,optional"`      // 是否降序排序
	MinUsdAmount float64 `form:"minUsdAmount,optional"`   // 最小 USD 金额筛选
	MaxUsdAmount float64 `form:"maxUsdAmount,optional"`   // 最大 USD 金额筛选
}

// KlineHistoryRequest K 线历史请求（普通分页模式）
type KlineHistoryRequest struct {
	TokenAddr string `form:"tokenAddr"` // 代币合约地址
	Interval  string `form:"interval"`  // K 线时间间隔：1m/5m/15m/30m/1h/4h/1d/1w
	From      int64  `form:"from"`      // 查询起始时间（Unix 时间戳）
	To        int64  `form:"to"`        // 查询结束时间（Unix 时间戳）
}

// KlineHistoryWithCursorRequest 带游标的 K 线请求（游标分页模式）
// 适用于大数据量场景，通过 cursor 避免深分页性能问题
type KlineHistoryWithCursorRequest struct {
	TokenAddr string `form:"tokenAddr"`          // 代币合约地址
	Interval  string `form:"interval"`           // K 线时间间隔
	Cursor    string `form:"cursor,optional"`    // 游标（base64 编码的时间戳，表示查询此时间之前的数据）
	Limit     int    `form:"limit,optional"`     // 返回数据条数限制（默认 300，最大 1000）
}

// PresignRequest 预签名上传请求
type PresignRequest struct {
	MimeType string `form:"mimeType"` // 文件 MIME 类型（如 png、jpg）
	ChainID  int    `form:"chainId"`  // 链 ID，用于构建存储路径
}

// UploadConfirmRequest 确认上传请求
type UploadConfirmRequest struct {
	Key         string            `json:"key"`                  // 文件在 COS 中的存储键
	UploadedUrl string            `json:"uploadedUrl"`          // 文件的公开访问 URL
	Metadata    map[string]string `json:"metadata,optional"`    // 附加元数据
}

// UserStatusRequest 用户状态请求
// 用于查询指定地址的代理/邀请相关信息
type UserStatusRequest struct {
	Address string `form:"address"` // 用户钱包地址
}

// UserInvitesRequest 用户邀请列表请求
type UserInvitesRequest struct {
	Address string `form:"address"`          // 钱包地址
	Page    int    `form:"page,default=1"`   // 页码
	Size    int    `form:"size,default=10"`  // 每页数量
}

// CreateEventRequest 创建活动请求
type CreateEventRequest struct {
	Name                  string `json:"name"`                              // 活动名称
	Description           string `json:"description"`                       // 活动描述
	CategoryType          int    `json:"categoryType"`                      // 活动分类类型
	PlayType              int    `json:"playType"`                          // 玩法类型
	RewardTokenType       int    `json:"rewardTokenType"`                   // 奖励代币类型
	RewardAmount          string `json:"rewardAmount"`                      // 奖励数量
	RewardSlots           string `json:"rewardSlots"`                       // 奖励名额
	StartAt               string `json:"startAt"`                           // 开始时间
	EndAt                 string `json:"endAt"`                             // 结束时间
	CoverImage            string `json:"coverImage"`                        // 封面图片 URL
	TokenID               int64  `json:"tokenId"`                           // 关联代币 ID
	InitiatorType         int    `json:"initiatorType"`                     // 发起者类型
	AudienceType          int    `json:"audienceType"`                      // 受众类型
	MinDailyTradeAmount   string `json:"minDailyTradeAmount,optional"`      // 最低日交易量要求
	InviteMinCount        string `json:"inviteMinCount,optional"`           // 最低邀请人数要求
	InviteeMinTradeAmount string `json:"inviteeMinTradeAmount,optional"`    // 被邀请人最低交易量要求
	HeatVoteTarget        string `json:"heatVoteTarget,optional"`           // 热度投票目标
	CommentMinCount       string `json:"commentMinCount,optional"`          // 最低评论数要求
	RewardTokenID         int64  `json:"rewardTokenId,optional"`            // 奖励代币 ID
	RewardTokenAddress    string `json:"rewardTokenAddress,optional"`       // 奖励代币地址
}

// UserActivityListRequest 用户活动列表请求
type UserActivityListRequest struct {
	PageNo    int    `form:"pn,default=1"`          // 页码
	PageSize  int    `form:"ps,default=10"`         // 每页数量
	UserID    int64  `form:"userId,optional"`       // 用户 ID（可选）
	Status    int    `form:"status,optional"`       // 活动状态筛选（可选）
	SortField string `form:"sortField,optional"`    // 排序字段（可选）
	SortType  string `form:"sortType,optional"`     // 排序方向（可选）
}

// RankingTokenListRequest 排行榜代币请求
type RankingTokenListRequest struct {
	PageNo      int    `form:"pn,default=1"`            // 页码
	PageSize    int    `form:"ps,default=10"`           // 每页数量
	Platform    int    `form:"platform,optional"`       // 平台筛选（可选）
	Category    string `form:"category,optional"`       // 分类筛选（可选）
	TokenSymbol string `form:"tokenSymbol,optional"`    // 代币符号搜索（可选）
	PageType    int    `form:"pageType,optional"`       // 页面类型（可选）
	SortField   string `form:"sortField,optional"`      // 排序字段（可选）
	SortType    string `form:"sortType,optional"`       // 排序方向（可选）
}

// OverviewRankingsRequest 概览排行榜请求
type OverviewRankingsRequest struct {
	Top int `form:"top,default=5"` // 每个排行榜返回的代币数量，默认 5
}

// AdvancedTokenListRequest 高级代币列表请求
// 支持多维度筛选条件
type AdvancedTokenListRequest struct {
	PageNo               int     `form:"pn,default=1"`                     // 页码
	PageSize             int     `form:"ps,default=10"`                    // 每页数量
	VolumeStatisticsType  int     `form:"volumeStatisticsType,optional"`    // 交易量统计类型（可选）
	MarketCapMin         float64 `form:"marketCapMin,optional"`            // 最小市值筛选（可选）
	MarketCapMax         float64 `form:"marketCapMax,optional"`            // 最大市值筛选（可选）
	HoldersMin           int     `form:"holdersMin,optional"`              // 最小持有者数（可选）
	HoldersMax           int     `form:"holdersMax,optional"`              // 最大持有者数（可选）
	VolumeMin            float64 `form:"volumeMin,optional"`               // 最小交易量（可选）
	VolumeMax            float64 `form:"volumeMax,optional"`               // 最大交易量（可选）
	TokenIssuanceMode    int     `form:"tokenIssuanceMode,optional"`       // 代币发行模式（可选）
	IsTop10              bool    `form:"isTop10,optional"`                 // 是否前10（可选）
	IsSign               bool    `form:"isSign,optional"`                  // 是否已签约（可选）
	IsPancakeV3          bool    `form:"isPancakeV3,optional"`             // 是否 PancakeSwap V3（可选）
	SortType             int     `form:"sortType,optional"`                // 排序类型（可选）
}

// OverviewStatsRequest 概览统计请求
type OverviewStatsRequest struct {
	Address string `form:"address,optional"` // 用户钱包地址（可选，默认使用当前登录用户地址）
}

// MyTokenListRequest 我的代币列表请求
type MyTokenListRequest struct {
	PageNo    int    `form:"pn,default=1"`          // 页码
	PageSize  int    `form:"ps,default=10"`         // 每页数量
	SortField string `form:"sortField,optional"`    // 排序字段（可选）
	SortType  string `form:"sortType,optional"`     // 排序方向（可选）
	Search    string `form:"search,optional"`       // 搜索关键词（可选）
}

// PageRequest 通用分页请求
type PageRequest struct {
	PageNo   int `form:"pn,default=1"`   // 页码，默认第 1 页
	PageSize int `form:"ps,default=10"`  // 每页数量，默认 10 条
}
