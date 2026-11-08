// events.go - 链上事件数据服务
// 本文件封装了对链上事件表（token_created_events、token_bought_events、
// token_sold_events、token_graduated_events）的查询操作
// 提供代币创建、买入、卖出、毕业等链上事件的查询和统计功能
package chain

import (
	"context" // 上下文包
	"time"    // 时间包

	"github.com/jackc/pgx/v5/pgxpool" // PostgreSQL 连接池
	"github.com/meme-launchpad/api/internal/model" // 数据模型
)

// EventService 链上事件服务
type EventService struct {
	db           *pgxpool.Pool       // 数据库连接池
	rpcURL       string              // RPC 节点地址（预留，可用于实时监听链上事件）
	coreContract string              // 核心合约地址（预留）
	tokenModel   *model.TokenModel   // 代币模型
	tradeModel   *model.TradeModel   // 交易模型
}

// NewEventService 创建链上事件服务实例
func NewEventService(
	rpcURL string,
	coreContract string,
	tokenModel *model.TokenModel,
	tradeModel *model.TradeModel,
) *EventService {
	var db *pgxpool.Pool
	if tokenModel != nil {
		db = tokenModel.GetDB() // 从 TokenModel 获取数据库连接
	}

	return &EventService{
		db:           db,
		rpcURL:       rpcURL,
		coreContract: coreContract,
		tokenModel:   tokenModel,
		tradeModel:   tradeModel,
	}
}

// TokenCreatedEvent 代币创建事件
// 对应 token_created_events 表
type TokenCreatedEvent struct {
	ID              int64     `json:"id"`              // 事件 ID
	TokenAddress    string    `json:"tokenAddress"`    // 代币合约地址
	CreatorAddress  string    `json:"creatorAddress"`  // 创建者地址
	Name            string    `json:"name"`            // 代币名称
	Symbol          string    `json:"symbol"`          // 代币符号
	TotalSupply     string    `json:"totalSupply"`     // 总供应量
	RequestID       string    `json:"requestId"`       // 请求 ID
	TransactionHash string    `json:"transactionHash"` // 交易哈希
	BlockNumber     int64     `json:"blockNumber"`     // 区块高度
	BlockTimestamp  time.Time `json:"blockTimestamp"`  // 区块时间
	LogIndex        int       `json:"logIndex"`        // 日志索引
	CreatedAt       time.Time `json:"createdAt"`       // 记录创建时间
}

// TokenBoughtEvent 代币购买事件
// 对应 token_bought_events 表
type TokenBoughtEvent struct {
	ID                  int64     `json:"id"`                  // 事件 ID
	TokenAddress        string    `json:"tokenAddress"`        // 代币地址
	BuyerAddress        string    `json:"buyerAddress"`        // 买家地址
	BnbAmount           string    `json:"bnbAmount"`           // BNB 金额
	TokenAmount         string    `json:"tokenAmount"`         // 代币数量
	TradingFee          string    `json:"tradingFee"`          // 交易手续费
	VirtualBnbReserve   string    `json:"virtualBnbReserve"`   // 虚拟 BNB 储备
	VirtualTokenReserve string    `json:"virtualTokenReserve"` // 虚拟代币储备
	AvailableTokens     string    `json:"availableTokens"`     // 可用代币数
	CollectedBnb        string    `json:"collectedBnb"`        // 已筹集 BNB
	TransactionHash     string    `json:"transactionHash"`     // 交易哈希
	BlockNumber         int64     `json:"blockNumber"`         // 区块高度
	BlockTimestamp      time.Time `json:"blockTimestamp"`      // 区块时间
	LogIndex            int       `json:"logIndex"`            // 日志索引
	CreatedAt           time.Time `json:"createdAt"`           // 创建时间
}

// TokenSoldEvent 代币卖出事件
// 对应 token_sold_events 表
type TokenSoldEvent struct {
	ID                  int64     `json:"id"`                  // 事件 ID
	TokenAddress        string    `json:"tokenAddress"`        // 代币地址
	SellerAddress       string    `json:"sellerAddress"`       // 卖家地址
	TokenAmount         string    `json:"tokenAmount"`         // 代币数量
	BnbAmount           string    `json:"bnbAmount"`           // BNB 金额
	TradingFee          string    `json:"tradingFee"`          // 交易手续费
	VirtualBnbReserve   string    `json:"virtualBnbReserve"`   // 虚拟 BNB 储备
	VirtualTokenReserve string    `json:"virtualTokenReserve"` // 虚拟代币储备
	AvailableTokens     string    `json:"availableTokens"`     // 可用代币数
	CollectedBnb        string    `json:"collectedBnb"`        // 已筹集 BNB
	TransactionHash     string    `json:"transactionHash"`     // 交易哈希
	BlockNumber         int64     `json:"blockNumber"`         // 区块高度
	BlockTimestamp      time.Time `json:"blockTimestamp"`      // 区块时间
	LogIndex            int       `json:"logIndex"`            // 日志索引
	CreatedAt           time.Time `json:"createdAt"`           // 创建时间
}

// TokenGraduatedEvent 代币毕业事件
// 代币从 Bonding Curve 毕业到 DEX（如 PancakeSwap）时触发
type TokenGraduatedEvent struct {
	ID              int64     `json:"id"`              // 事件 ID
	TokenAddress    string    `json:"tokenAddress"`    // 代币地址
	LiquidityBnb    string    `json:"liquidityBnb"`    // 添加的 BNB 流动性
	LiquidityTokens string    `json:"liquidityTokens"` // 添加的代币流动性
	LiquidityResult string    `json:"liquidityResult"` // 流动性添加结果
	TransactionHash string    `json:"transactionHash"` // 交易哈希
	BlockNumber     int64     `json:"blockNumber"`     // 区块高度
	BlockTimestamp  time.Time `json:"blockTimestamp"`  // 区块时间
	LogIndex        int       `json:"logIndex"`        // 日志索引
	CreatedAt       time.Time `json:"createdAt"`       // 创建时间
}

// GetTokenCreatedByAddress 根据地址获取代币创建事件
func (s *EventService) GetTokenCreatedByAddress(ctx context.Context, tokenAddress string) (*TokenCreatedEvent, error) {
	var e TokenCreatedEvent
	err := s.db.QueryRow(ctx, `
		SELECT id, token_address, creator_address, name, symbol, total_supply,
			request_id, transaction_hash, block_number, block_timestamp, log_index, created_at
		FROM token_created_events
		WHERE LOWER(token_address) = LOWER($1)
		LIMIT 1
	`, tokenAddress).Scan(
		&e.ID, &e.TokenAddress, &e.CreatorAddress, &e.Name, &e.Symbol, &e.TotalSupply,
		&e.RequestID, &e.TransactionHash, &e.BlockNumber, &e.BlockTimestamp, &e.LogIndex, &e.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &e, nil
}

// GetTokenCreatedByRequestID 根据 requestID 获取代币创建事件
func (s *EventService) GetTokenCreatedByRequestID(ctx context.Context, requestID string) (*TokenCreatedEvent, error) {
	var e TokenCreatedEvent
	err := s.db.QueryRow(ctx, `
		SELECT id, token_address, creator_address, name, symbol, total_supply,
			request_id, transaction_hash, block_number, block_timestamp, log_index, created_at
		FROM token_created_events
		WHERE request_id = $1
		LIMIT 1
	`, requestID).Scan(
		&e.ID, &e.TokenAddress, &e.CreatorAddress, &e.Name, &e.Symbol, &e.TotalSupply,
		&e.RequestID, &e.TransactionHash, &e.BlockNumber, &e.BlockTimestamp, &e.LogIndex, &e.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &e, nil
}

// GetRecentTokenCreated 获取最近创建的代币事件
func (s *EventService) GetRecentTokenCreated(ctx context.Context, limit int) ([]*TokenCreatedEvent, error) {
	rows, err := s.db.Query(ctx, `
		SELECT id, token_address, creator_address, name, symbol, total_supply,
			request_id, transaction_hash, block_number, block_timestamp, log_index, created_at
		FROM token_created_events
		ORDER BY block_timestamp DESC
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []*TokenCreatedEvent
	for rows.Next() {
		var e TokenCreatedEvent
		if err := rows.Scan(
			&e.ID, &e.TokenAddress, &e.CreatorAddress, &e.Name, &e.Symbol, &e.TotalSupply,
			&e.RequestID, &e.TransactionHash, &e.BlockNumber, &e.BlockTimestamp, &e.LogIndex, &e.CreatedAt,
		); err != nil {
			return nil, err
		}
		events = append(events, &e)
	}
	return events, nil
}

// GetTokenBuyEvents 获取代币买入事件列表
func (s *EventService) GetTokenBuyEvents(ctx context.Context, tokenAddress string, limit, offset int) ([]*TokenBoughtEvent, int, error) {
	// 查询总数
	var total int
	err := s.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM token_bought_events WHERE LOWER(token_address) = LOWER($1)
	`, tokenAddress).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// 查询买入事件列表
	rows, err := s.db.Query(ctx, `
		SELECT id, token_address, buyer_address, bnb_amount, token_amount,
			trading_fee, virtual_bnb_reserve, virtual_token_reserve, available_tokens, collected_bnb,
			transaction_hash, block_number, block_timestamp, log_index, created_at
		FROM token_bought_events
		WHERE LOWER(token_address) = LOWER($1)
		ORDER BY block_timestamp DESC
		LIMIT $2 OFFSET $3
	`, tokenAddress, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var events []*TokenBoughtEvent
	for rows.Next() {
		var e TokenBoughtEvent
		if err := rows.Scan(
			&e.ID, &e.TokenAddress, &e.BuyerAddress, &e.BnbAmount, &e.TokenAmount,
			&e.TradingFee, &e.VirtualBnbReserve, &e.VirtualTokenReserve, &e.AvailableTokens, &e.CollectedBnb,
			&e.TransactionHash, &e.BlockNumber, &e.BlockTimestamp, &e.LogIndex, &e.CreatedAt,
		); err != nil {
			return nil, 0, err
		}
		events = append(events, &e)
	}
	return events, total, nil
}

// GetTokenSellEvents 获取代币卖出事件列表
func (s *EventService) GetTokenSellEvents(ctx context.Context, tokenAddress string, limit, offset int) ([]*TokenSoldEvent, int, error) {
	// 查询总数
	var total int
	err := s.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM token_sold_events WHERE LOWER(token_address) = LOWER($1)
	`, tokenAddress).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// 查询卖出事件列表
	rows, err := s.db.Query(ctx, `
		SELECT id, token_address, seller_address, token_amount, bnb_amount,
			trading_fee, virtual_bnb_reserve, virtual_token_reserve, available_tokens, collected_bnb,
			transaction_hash, block_number, block_timestamp, log_index, created_at
		FROM token_sold_events
		WHERE LOWER(token_address) = LOWER($1)
		ORDER BY block_timestamp DESC
		LIMIT $2 OFFSET $3
	`, tokenAddress, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var events []*TokenSoldEvent
	for rows.Next() {
		var e TokenSoldEvent
		if err := rows.Scan(
			&e.ID, &e.TokenAddress, &e.SellerAddress, &e.TokenAmount, &e.BnbAmount,
			&e.TradingFee, &e.VirtualBnbReserve, &e.VirtualTokenReserve, &e.AvailableTokens, &e.CollectedBnb,
			&e.TransactionHash, &e.BlockNumber, &e.BlockTimestamp, &e.LogIndex, &e.CreatedAt,
		); err != nil {
			return nil, 0, err
		}
		events = append(events, &e)
	}
	return events, total, nil
}

// GetTokenTrades 获取代币所有交易（买入和卖出合并）
// 使用 UNION ALL 合并买入和卖出事件表，统一返回交易记录
func (s *EventService) GetTokenTrades(ctx context.Context, tokenAddress string, limit, offset int) ([]map[string]interface{}, int, error) {
	// 计算总交易数（买入 + 卖出）
	var total int
	err := s.db.QueryRow(ctx, `
		SELECT
			(SELECT COUNT(*) FROM token_bought_events WHERE LOWER(token_address) = LOWER($1)) +
			(SELECT COUNT(*) FROM token_sold_events WHERE LOWER(token_address) = LOWER($1))
	`, tokenAddress).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// 使用 UNION ALL 合并买入和卖出事件
	rows, err := s.db.Query(ctx, `
		SELECT * FROM (
			SELECT
				'buy' as trade_type,
				token_address,
				buyer_address as user_address,
				bnb_amount,
				token_amount,
				trading_fee,
				transaction_hash,
				block_number,
				block_timestamp
			FROM token_bought_events
			WHERE LOWER(token_address) = LOWER($1)

			UNION ALL

			SELECT
				'sell' as trade_type,
				token_address,
				seller_address as user_address,
				bnb_amount,
				token_amount,
				trading_fee,
				transaction_hash,
				block_number,
				block_timestamp
			FROM token_sold_events
			WHERE LOWER(token_address) = LOWER($1)
		) combined
		ORDER BY block_timestamp DESC
		LIMIT $2 OFFSET $3
	`, tokenAddress, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	var trades []map[string]interface{}
	for rows.Next() {
		var tradeType, tokenAddr, userAddr, bnbAmount, tokenAmount, tradingFee, txHash string
		var blockNumber int64
		var blockTimestamp time.Time

		if err := rows.Scan(&tradeType, &tokenAddr, &userAddr, &bnbAmount, &tokenAmount,
			&tradingFee, &txHash, &blockNumber, &blockTimestamp); err != nil {
			return nil, 0, err
		}

		// 将字符串类型转换为数字类型（与 trades 表格式一致）
		tradeTypeInt := 10 // 买入
		if tradeType == "sell" {
			tradeTypeInt = 20 // 卖出
		}

		trades = append(trades, map[string]interface{}{
			"tradeType":       tradeTypeInt,
			"tokenAddress":    tokenAddr,
			"userAddress":     userAddr,
			"bnbAmount":       bnbAmount,
			"tokenAmount":     tokenAmount,
			"tradingFee":      tradingFee,
			"transactionHash": txHash,
			"blockNumber":     blockNumber,
			"blockTimestamp":  blockTimestamp.Format(time.RFC3339),
		})
	}
	return trades, total, nil
}

// GetToken24HStats 获取代币24小时统计（基于链上事件）
func (s *EventService) GetToken24HStats(ctx context.Context, tokenAddress string) (map[string]interface{}, error) {
	since := time.Now().Add(-24 * time.Hour)

	stats := map[string]interface{}{
		"buyCount":       0,
		"sellCount":      0,
		"totalVolumeBnb": "0",
		"totalVolumeUsd": "0",
	}

	// 买入次数和金额
	var buyCount int
	var buyVolume string
	err := s.db.QueryRow(ctx, `
		SELECT COUNT(*), COALESCE(SUM(bnb_amount::numeric), 0)::text
		FROM token_bought_events
		WHERE LOWER(token_address) = LOWER($1) AND block_timestamp >= $2
	`, tokenAddress, since).Scan(&buyCount, &buyVolume)
	if err == nil {
		stats["buyCount"] = buyCount
	}

	// 卖出次数和金额
	var sellCount int
	var sellVolume string
	err = s.db.QueryRow(ctx, `
		SELECT COUNT(*), COALESCE(SUM(bnb_amount::numeric), 0)::text
		FROM token_sold_events
		WHERE LOWER(token_address) = LOWER($1) AND block_timestamp >= $2
	`, tokenAddress, since).Scan(&sellCount, &sellVolume)
	if err == nil {
		stats["sellCount"] = sellCount
	}

	// 总交易量（简化处理：仅使用买入量）
	stats["totalVolumeBnb"] = buyVolume

	return stats, nil
}

// GetTokenIsGraduated 检查代币是否已毕业
// 查询 token_graduated_events 表
func (s *EventService) GetTokenIsGraduated(ctx context.Context, tokenAddress string) (bool, *TokenGraduatedEvent, error) {
	var e TokenGraduatedEvent
	err := s.db.QueryRow(ctx, `
		SELECT id, token_address, liquidity_bnb, liquidity_tokens, liquidity_result,
			transaction_hash, block_number, block_timestamp, log_index, created_at
		FROM token_graduated_events
		WHERE LOWER(token_address) = LOWER($1)
		LIMIT 1
	`, tokenAddress).Scan(
		&e.ID, &e.TokenAddress, &e.LiquidityBnb, &e.LiquidityTokens, &e.LiquidityResult,
		&e.TransactionHash, &e.BlockNumber, &e.BlockTimestamp, &e.LogIndex, &e.CreatedAt,
	)
	if err != nil {
		return false, nil, nil // 未找到记录表示未毕业
	}
	return true, &e, nil
}

// GetUserTradeStats 获取用户交易统计
// 统计用户的买入/卖出次数和金额，以及交易过的不同代币数量
func (s *EventService) GetUserTradeStats(ctx context.Context, userAddress string) (map[string]interface{}, error) {
	stats := map[string]interface{}{
		"totalBuyCount":    0,
		"totalSellCount":   0,
		"totalBuyBnb":      "0",
		"totalSellBnb":     "0",
		"tradedTokenCount": 0,
	}

	// 买入统计
	var buyCount int
	var buyBnb string
	s.db.QueryRow(ctx, `
		SELECT COUNT(*), COALESCE(SUM(bnb_amount::numeric), 0)::text
		FROM token_bought_events
		WHERE LOWER(buyer_address) = LOWER($1)
	`, userAddress).Scan(&buyCount, &buyBnb)
	stats["totalBuyCount"] = buyCount
	stats["totalBuyBnb"] = buyBnb

	// 卖出统计
	var sellCount int
	var sellBnb string
	s.db.QueryRow(ctx, `
		SELECT COUNT(*), COALESCE(SUM(bnb_amount::numeric), 0)::text
		FROM token_sold_events
		WHERE LOWER(seller_address) = LOWER($1)
	`, userAddress).Scan(&sellCount, &sellBnb)
	stats["totalSellCount"] = sellCount
	stats["totalSellBnb"] = sellBnb

	// 交易过的不同代币数量
	var tokenCount int
	s.db.QueryRow(ctx, `
		SELECT COUNT(DISTINCT token_address) FROM (
			SELECT token_address FROM token_bought_events WHERE LOWER(buyer_address) = LOWER($1)
			UNION
			SELECT token_address FROM token_sold_events WHERE LOWER(seller_address) = LOWER($1)
		) t
	`, userAddress).Scan(&tokenCount)
	stats["tradedTokenCount"] = tokenCount

	return stats, nil
}
