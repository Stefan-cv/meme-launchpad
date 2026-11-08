// trade.go - 交易数据模型
// 本文件封装了对 trades 表的数据库操作，提供交易记录查询和24小时统计功能
package model

import (
	"context" // 上下文包
	"time"    // 时间包

	"github.com/jackc/pgx/v5/pgxpool" // PostgreSQL 连接池
)

// Trade 交易数据模型
// 对应数据库中的 trades 表，记录每笔代币交易的详细信息
type Trade struct {
	ID              int64     `json:"id"`              // 交易 ID（主键）
	TokenAddress    string    `json:"tokenAddress"`    // 代币合约地址
	UserAddress     string    `json:"userAddress"`     // 交易者钱包地址
	TradeType       int       `json:"tradeType"`       // 交易类型：10=买入, 20=卖出
	BnbAmount       string    `json:"bnbAmount"`       // BNB 交易金额（字符串存储大数）
	TokenAmount     string    `json:"tokenAmount"`     // 代币交易数量
	Price           string    `json:"price"`           // 成交价格
	UsdAmount       *string   `json:"usdAmount"`       // 折合 USD 金额（本地链无喂价，可能为 NULL）
	TransactionHash string    `json:"transactionHash"` // 交易哈希（链上唯一标识）
	BlockNumber     int64     `json:"blockNumber"`     // 区块高度
	BlockTimestamp  time.Time `json:"blockTimestamp"`  // 区块时间
	CreatedAt       time.Time `json:"createdAt"`       // 记录创建时间
}

// TradeModel 交易数据访问模型
type TradeModel struct {
	db *pgxpool.Pool
}

// NewTradeModel 创建交易模型实例
func NewTradeModel(db *pgxpool.Pool) *TradeModel {
	return &TradeModel{db: db}
}

// GetDB 获取数据库连接池
func (m *TradeModel) GetDB() *pgxpool.Pool {
	return m.db
}

// FindList 获取交易列表
// 支持按代币地址筛选、多种排序方式和分页
// 参数：
//   - ctx: 上下文
//   - params: 查询参数 map，包含 tokenAddress、pageNo、pageSize、orderBy、orderDesc
// 返回：交易列表、总数、错误
func (m *TradeModel) FindList(ctx context.Context, params map[string]interface{}) ([]*Trade, int, error) {
	// 从参数中提取代币地址
	tokenAddress := params["tokenAddress"].(string)

	// 查询满足条件的总记录数
	var total int
	err := m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM trades
		WHERE LOWER(token_address) = LOWER($1)
	`, tokenAddress).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// 构建排序条件
	// 默认按区块时间降序（最新交易在前）
	orderBy := "block_timestamp DESC"
	if ob, ok := params["orderBy"].(string); ok && ob != "" {
		// 根据前端指定的排序字段构建排序子句
		switch ob {
		case "usd_amount":
			orderBy = "usd_amount" // 按 USD 金额排序
		case "token_amount":
			orderBy = "token_amount" // 按代币数量排序
		case "bnb_amount":
			orderBy = "bnb_amount" // 按 BNB 金额排序
		}
		// 如果指定了降序排序，追加 DESC 关键字
		if desc, ok := params["orderDesc"].(bool); ok && desc {
			orderBy += " DESC"
		}
	}

	// 分页参数处理
	pageNo := 1
	pageSize := 10
	if pn, ok := params["pageNo"].(int); ok && pn > 0 {
		pageNo = pn
	}
	if ps, ok := params["pageSize"].(int); ok && ps > 0 {
		pageSize = ps
	}
	offset := (pageNo - 1) * pageSize

	// 执行交易列表查询
	rows, err := m.db.Query(ctx, `
		SELECT id, token_address, user_address, trade_type,
			bnb_amount, token_amount, price, usd_amount,
			transaction_hash, block_number, block_timestamp, created_at
		FROM trades
		WHERE LOWER(token_address) = LOWER($1)
		ORDER BY `+orderBy+`
		LIMIT $2 OFFSET $3
	`, tokenAddress, pageSize, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	// 遍历查询结果
	var trades []*Trade
	for rows.Next() {
		var t Trade
		err := rows.Scan(
			&t.ID, &t.TokenAddress, &t.UserAddress, &t.TradeType,
			&t.BnbAmount, &t.TokenAmount, &t.Price, &t.UsdAmount,
			&t.TransactionHash, &t.BlockNumber, &t.BlockTimestamp, &t.CreatedAt,
		)
		if err != nil {
			return nil, 0, err
		}
		trades = append(trades, &t)
	}

	return trades, total, nil
}

// Get24HStats 获取24小时交易统计
// 统计指定代币在过去24小时内的买入次数、卖出次数和总交易量
// 参数：tokenAddress - 代币合约地址
// 返回：包含 buyCount、sellCount、totalVolume 的 map
func (m *TradeModel) Get24HStats(ctx context.Context, tokenAddress string) (map[string]interface{}, error) {
	// 初始化默认统计值
	stats := map[string]interface{}{
		"buyCount":    0,    // 买入次数
		"sellCount":   0,    // 卖出次数
		"totalVolume": "0",  // 总交易量（BNB）
	}

	// 计算24小时前的时间点
	since := time.Now().Add(-24 * time.Hour)

	// 查询买入次数
	// trade_type = 10 表示买入
	var buyCount int
	m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM trades
		WHERE LOWER(token_address) = LOWER($1)
		AND trade_type = 10
		AND block_timestamp >= $2
	`, tokenAddress, since).Scan(&buyCount)
	stats["buyCount"] = buyCount

	// 查询卖出次数
	// trade_type = 20 表示卖出
	var sellCount int
	m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM trades
		WHERE LOWER(token_address) = LOWER($1)
		AND trade_type = 20
		AND block_timestamp >= $2
	`, tokenAddress, since).Scan(&sellCount)
	stats["sellCount"] = sellCount

	// 查询总交易量（BNB）
	// COALESCE 将 NULL 转换为 0，SUM 计算总金额
	var totalVolume string
	m.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(bnb_amount::numeric), 0)::text FROM trades
		WHERE LOWER(token_address) = LOWER($1)
		AND block_timestamp >= $2
	`, tokenAddress, since).Scan(&totalVolume)
	stats["totalVolume"] = totalVolume

	return stats, nil
}
