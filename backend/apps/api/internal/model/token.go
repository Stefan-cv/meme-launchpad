// token.go - 代币数据模型
// 本文件封装了对 tokens 表及相关表（user_favorites、token_balances、nonce_sequence）的数据库操作
// 提供代币的 CRUD、列表查询、热门推荐、持有者查询、收藏管理等功能
package model

import (
	"context"     // 上下文包
	"database/sql" // SQL 类型包，提供 NullString 等可空类型
	"time"        // 时间包

	"github.com/jackc/pgx/v5/pgxpool" // PostgreSQL 连接池
)

// Token 代币数据模型
// 对应数据库中的 tokens 表，存储代币的基本信息和发行参数
type Token struct {
	ID                   int64          `json:"id"`                   // 代币 ID（主键，自增）
	Name                 string         `json:"name"`                 // 代币名称（如 "Test Token"）
	Symbol               string         `json:"symbol"`               // 代币符号（如 "TEST"）
	Logo                 string         `json:"logo"`                 // Logo 图片 URL
	Banner               sql.NullString `json:"banner"`               // Banner 图片 URL（可为 NULL）
	Description          sql.NullString `json:"description"`          // 代币描述（可为 NULL）
	TokenContractAddress string         `json:"tokenContractAddress"` // 代币合约地址（CREATE2 部署后填入）
	CreatorAddress       string         `json:"creatorAddress"`       // 创建者钱包地址
	LaunchMode           int            `json:"launchMode"`           // 发行模式（1=公平发射, 2=IDO 等）
	LaunchTime           int64          `json:"launchTime"`           // 上线时间（Unix 秒级时间戳）
	BnbCurrent           string         `json:"bnbCurrent"`           // 当前已筹集的 BNB 数量（字符串存储大数）
	BnbTarget            string         `json:"bnbTarget"`            // 目标筹集 BNB 数量
	MarginBnb            string         `json:"marginBnb"`            // 保证金 BNB 数量
	TotalSupply          string         `json:"totalSupply"`          // 代币总供应量
	Status               int            `json:"status"`               // 状态：1=预售中, 2=已上线, 3=已毕业
	Website              sql.NullString `json:"website"`              // 官网链接（可为 NULL）
	Twitter              sql.NullString `json:"twitter"`              // Twitter 链接（可为 NULL）
	Telegram             sql.NullString `json:"telegram"`             // Telegram 链接（可为 NULL）
	Discord              sql.NullString `json:"discord"`              // Discord 链接（可为 NULL）
	Whitepaper           sql.NullString `json:"whitepaper"`           // 白皮书链接（可为 NULL）
	Tags                 []string       `json:"tags"`                 // 标签列表（PostgreSQL 数组类型）
	Hot                  int            `json:"hot"`                  // 热度值（用于排序）
	TokenLv              int            `json:"tokenLv"`              // 代币等级
	TokenRank            int            `json:"tokenRank"`            // 代币排名
	RequestID            string         `json:"requestId"`            // 创建请求 ID（与链上事件关联）
	Nonce                int            `json:"nonce"`                // CREATE2 nonce（用于地址预测）
	Salt                 string         `json:"salt"`                 // CREATE2 salt 值
	PreBuyPercent        float64        `json:"preBuyPercent"`        // 预购比例
	MarginTime           int64          `json:"marginTime"`           // 保证金锁定时间（秒）
	ContactEmail         sql.NullString `json:"contactEmail"`         // 联系人邮箱（可为 NULL）
	ContactTg            sql.NullString `json:"contactTg"`            // 联系人 Telegram（可为 NULL）
	CreatedAt            time.Time      `json:"createdAt"`            // 创建时间
	UpdatedAt            time.Time      `json:"updatedAt"`            // 更新时间
}

// TokenModel 代币数据访问模型
// 封装了数据库连接池，提供代币相关的数据库操作方法
type TokenModel struct {
	db *pgxpool.Pool // PostgreSQL 连接池
}

// NewTokenModel 创建代币模型实例
func NewTokenModel(db *pgxpool.Pool) *TokenModel {
	return &TokenModel{db: db}
}

// GetDB 获取数据库连接池
// 供其他服务（如 TokenService）需要直接操作数据库时使用
func (m *TokenModel) GetDB() *pgxpool.Pool {
	return m.db
}

// FindList 获取代币列表
// 支持动态筛选条件、排序和分页
// 参数：
//   - ctx: 上下文
//   - params: 查询参数 map，包含 pageNo、pageSize、sort、launchMode 等
// 返回：代币列表、总数、错误
// SQL 说明：
//   - WHERE 1=1 是动态条件拼接的基础，方便后续添加 AND 条件
//   - 使用参数化查询（$1, $2...）防止 SQL 注入
func (m *TokenModel) FindList(ctx context.Context, params map[string]interface{}) ([]*Token, int, error) {
	// 构建查询 SQL，查询代币的所有字段
	query := `
		SELECT id, name, symbol, logo, banner, description,
			token_contract_address, creator_address, launch_mode, launch_time,
			bnb_current, bnb_target, margin_bnb, total_supply, status,
			website, twitter, telegram, discord, whitepaper, tags,
			hot, token_lv, token_rank, created_at
		FROM tokens
		WHERE 1=1
	`
	// 构建计数 SQL，用于计算满足条件的总记录数
	countQuery := `SELECT COUNT(*) FROM tokens WHERE 1=1`
	args := []interface{}{}  // SQL 参数列表
	argIdx := 1              // 参数索引（PostgreSQL 参数从 $1 开始）

	// 添加发行模式筛选条件
	if launchMode, ok := params["launchMode"].(int); ok && launchMode > 0 {
		// 动态拼接 AND 条件到查询和计数 SQL
		query += ` AND launch_mode = $` + string(rune('0'+argIdx))
		countQuery += ` AND launch_mode = $` + string(rune('0'+argIdx))
		args = append(args, launchMode) // 添加参数值
		argIdx++                        // 递增参数索引
	}

	// 添加排序条件
	if sort, ok := params["sort"].(string); ok && sort != "" {
		switch sort {
		case "hot":
			query += " ORDER BY hot DESC" // 按热度降序
		case "new":
			query += " ORDER BY created_at DESC" // 按创建时间降序（最新优先）
		case "marketCap":
			query += " ORDER BY bnb_current DESC" // 按当前 BNB 数量降序（近似市值）
		default:
			query += " ORDER BY created_at DESC" // 默认按创建时间降序
		}
	} else {
		query += " ORDER BY created_at DESC" // 未指定排序时默认按创建时间降序
	}

	// 分页参数处理
	pageNo := 1   // 默认第 1 页
	pageSize := 10 // 默认每页 10 条
	if pn, ok := params["pageNo"].(int); ok && pn > 0 {
		pageNo = pn
	}
	if ps, ok := params["pageSize"].(int); ok && ps > 0 {
		pageSize = ps
	}
	offset := (pageNo - 1) * pageSize // 计算 OFFSET 偏移量
	// 拼接 LIMIT 和 OFFSET 子句
	query += ` LIMIT $` + string(rune('0'+argIdx)) + ` OFFSET $` + string(rune('0'+argIdx+1))
	args = append(args, pageSize, offset) // 添加分页参数

	// 执行计数查询，获取总记录数
	var total int
	// 注意：args[:argIdx-1] 只取筛选条件的参数，不包含分页参数
	err := m.db.QueryRow(ctx, countQuery, args[:argIdx-1]...).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// 执行列表查询
	rows, err := m.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close() // 确保关闭行迭代器

	// 遍历查询结果，将每行映射为 Token 结构体
	var tokens []*Token
	for rows.Next() {
		var t Token
		err := rows.Scan(
			&t.ID, &t.Name, &t.Symbol, &t.Logo, &t.Banner, &t.Description,
			&t.TokenContractAddress, &t.CreatorAddress, &t.LaunchMode, &t.LaunchTime,
			&t.BnbCurrent, &t.BnbTarget, &t.MarginBnb, &t.TotalSupply, &t.Status,
			&t.Website, &t.Twitter, &t.Telegram, &t.Discord, &t.Whitepaper, &t.Tags,
			&t.Hot, &t.TokenLv, &t.TokenRank, &t.CreatedAt,
		)
		if err != nil {
			return nil, 0, err
		}
		tokens = append(tokens, &t)
	}

	return tokens, total, nil
}

// FindByAddress 根据合约地址查找代币
// 使用 COALESCE 函数处理可能为 NULL 的字段，提供默认值
// 参数：address - 代币合约地址
// 返回：代币信息或错误
func (m *TokenModel) FindByAddress(ctx context.Context, address string) (*Token, error) {
	var t Token
	err := m.db.QueryRow(ctx, `
		SELECT id, name, symbol, COALESCE(logo, ''), banner, description,
			token_contract_address, creator_address, launch_mode, launch_time,
			COALESCE(bnb_current, 0)::text, COALESCE(bnb_target, 0)::text,
			COALESCE(margin_bnb, 0)::text, COALESCE(total_supply, 0)::text, COALESCE(status, 1),
			website, twitter, telegram, discord, whitepaper, COALESCE(tags, ARRAY[]::text[]),
			COALESCE(hot, 0), COALESCE(token_lv, 0), COALESCE(token_rank, 0),
			COALESCE(request_id, ''), COALESCE(nonce, 0), COALESCE(salt, ''),
			COALESCE(pre_buy_percent, 0), COALESCE(margin_time, 0), contact_email, contact_tg,
			created_at, updated_at
		FROM tokens
		WHERE LOWER(token_contract_address) = LOWER($1)
	`, address).Scan(
		&t.ID, &t.Name, &t.Symbol, &t.Logo, &t.Banner, &t.Description,
		&t.TokenContractAddress, &t.CreatorAddress, &t.LaunchMode, &t.LaunchTime,
		&t.BnbCurrent, &t.BnbTarget, &t.MarginBnb, &t.TotalSupply, &t.Status,
		&t.Website, &t.Twitter, &t.Telegram, &t.Discord, &t.Whitepaper, &t.Tags,
		&t.Hot, &t.TokenLv, &t.TokenRank, &t.RequestID, &t.Nonce, &t.Salt,
		&t.PreBuyPercent, &t.MarginTime, &t.ContactEmail, &t.ContactTg,
		&t.CreatedAt, &t.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

// FindByID 根据 ID 查找代币
// 使用 COALESCE 处理 NULL 字段，与 FindByAddress 查询逻辑类似
func (m *TokenModel) FindByID(ctx context.Context, id int64) (*Token, error) {
	var t Token
	err := m.db.QueryRow(ctx, `
		SELECT id, name, symbol, COALESCE(logo, ''), banner, description,
			token_contract_address, creator_address, launch_mode, launch_time,
			COALESCE(bnb_current, 0)::text, COALESCE(bnb_target, 0)::text,
			COALESCE(margin_bnb, 0)::text, COALESCE(total_supply, 0)::text, COALESCE(status, 1),
			website, twitter, telegram, discord, whitepaper, COALESCE(tags, ARRAY[]::text[]),
			COALESCE(hot, 0), COALESCE(token_lv, 0), COALESCE(token_rank, 0),
			COALESCE(request_id, ''), COALESCE(nonce, 0), COALESCE(salt, ''),
			COALESCE(pre_buy_percent, 0), COALESCE(margin_time, 0), contact_email, contact_tg,
			created_at, updated_at
		FROM tokens
		WHERE id = $1
	`, id).Scan(
		&t.ID, &t.Name, &t.Symbol, &t.Logo, &t.Banner, &t.Description,
		&t.TokenContractAddress, &t.CreatorAddress, &t.LaunchMode, &t.LaunchTime,
		&t.BnbCurrent, &t.BnbTarget, &t.MarginBnb, &t.TotalSupply, &t.Status,
		&t.Website, &t.Twitter, &t.Telegram, &t.Discord, &t.Whitepaper, &t.Tags,
		&t.Hot, &t.TokenLv, &t.TokenRank, &t.RequestID, &t.Nonce, &t.Salt,
		&t.PreBuyPercent, &t.MarginTime, &t.ContactEmail, &t.ContactTg,
		&t.CreatedAt, &t.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &t, nil
}

// Create 创建代币记录
// 将代币信息插入 tokens 表，使用 RETURNING 子句获取自增 ID 和时间戳
func (m *TokenModel) Create(ctx context.Context, token *Token) error {
	return m.db.QueryRow(ctx, `
		INSERT INTO tokens (
			name, symbol, logo, banner, description,
			token_contract_address, creator_address, launch_mode, launch_time,
			bnb_target, margin_bnb, total_supply, status,
			website, twitter, telegram, discord, whitepaper, tags,
			request_id, nonce, salt, pre_buy_percent, margin_time,
			contact_email, contact_tg, created_at, updated_at
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10,
			$11, $12, $13, $14, $15, $16, $17, $18, $19, $20,
			$21, $22, $23, $24, $25, NOW(), NOW()
		)
		RETURNING id, created_at, updated_at
	`,
		token.Name, token.Symbol, token.Logo, token.Banner, token.Description,
		token.TokenContractAddress, token.CreatorAddress, token.LaunchMode, token.LaunchTime,
		token.BnbTarget, token.MarginBnb, token.TotalSupply, token.Status,
		token.Website, token.Twitter, token.Telegram, token.Discord, token.Whitepaper, token.Tags,
		token.RequestID, token.Nonce, token.Salt, token.PreBuyPercent, token.MarginTime,
		token.ContactEmail, token.ContactTg,
	).Scan(&token.ID, &token.CreatedAt, &token.UpdatedAt) // RETURNING 子句回填 ID 和时间戳
}

// GetHotPick 获取热门代币
// 查询状态为预售中(1)或已上线(2)的代币，按热度和创建时间降序排列
// 参数：limit - 返回数量限制
func (m *TokenModel) GetHotPick(ctx context.Context, limit int) ([]*Token, error) {
	rows, err := m.db.Query(ctx, `
		SELECT id, name, symbol, logo, token_contract_address, bnb_current, hot
		FROM tokens
		WHERE status IN (1, 2)           -- 筛选预售中或已上线的代币
		ORDER BY hot DESC, created_at DESC -- 先按热度降序，再按创建时间降序
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []*Token
	for rows.Next() {
		var t Token
		// 只扫描热门推荐需要的字段
		err := rows.Scan(&t.ID, &t.Name, &t.Symbol, &t.Logo, &t.TokenContractAddress, &t.BnbCurrent, &t.Hot)
		if err != nil {
			return nil, err
		}
		tokens = append(tokens, &t)
	}
	return tokens, nil
}

// GetTokenHolders 获取代币持有者
// 查询 token_balances 表中持有指定代币的用户列表
// 参数：tokenAddress - 代币地址，pageNo/pageSize - 分页参数
// 返回：持有者列表（包含地址、余额、占比）、总数、错误
func (m *TokenModel) GetTokenHolders(ctx context.Context, tokenAddress string, pageNo, pageSize int) ([]map[string]interface{}, int, error) {
	// 查询总持有者数量
	countQuery := `SELECT COUNT(*) FROM token_balances WHERE LOWER(token_address) = LOWER($1) AND balance > 0`
	var total int
	err := m.db.QueryRow(ctx, countQuery, tokenAddress).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// 计算分页偏移量
	offset := (pageNo - 1) * pageSize
	// 查询持有者列表，包含持仓占比的计算
	// ROUND(balance * 100.0 / NULLIF(SUM, 0), 2) 计算持仓占比（百分比）
	// NULLIF 防止除以零错误
	rows, err := m.db.Query(ctx, `
		SELECT holder_address, balance,
			ROUND(balance * 100.0 / NULLIF((SELECT SUM(balance) FROM token_balances WHERE LOWER(token_address) = LOWER($1)), 0), 2) as percentage
		FROM token_balances
		WHERE LOWER(token_address) = LOWER($1) AND balance > 0
		ORDER BY balance DESC     -- 按余额降序排列
		LIMIT $2 OFFSET $3
	`, tokenAddress, pageSize, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	// 构建持有者列表
	var holders []map[string]interface{}
	for rows.Next() {
		var address, balance string
		var percentage float64
		if err := rows.Scan(&address, &balance, &percentage); err != nil {
			return nil, 0, err
		}
		holders = append(holders, map[string]interface{}{
			"address":    address,    // 持有者地址
			"balance":    balance,    // 持仓数量
			"percentage": percentage, // 持仓占比（%）
		})
	}

	return holders, total, nil
}

// IsFavorite 检查用户是否收藏了某代币
// 查询 user_favorites 表中是否存在该用户和代币的关联记录
func (m *TokenModel) IsFavorite(ctx context.Context, userID, tokenID int64) (bool, error) {
	var count int
	err := m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM user_favorites
		WHERE user_id = $1 AND token_id = $2
	`, userID, tokenID).Scan(&count)
	// count > 0 表示已收藏
	return count > 0, err
}

// AddFavorite 添加收藏
// 使用 ON CONFLICT DO NOTHING 防止重复收藏
// 如果 (user_id, token_id) 组合已存在，则不执行任何操作
func (m *TokenModel) AddFavorite(ctx context.Context, userID, tokenID int64) error {
	_, err := m.db.Exec(ctx, `
		INSERT INTO user_favorites (user_id, token_id, created_at)
		VALUES ($1, $2, NOW())
		ON CONFLICT (user_id, token_id) DO NOTHING
	`, userID, tokenID)
	return err
}

// RemoveFavorite 移除收藏
// 从 user_favorites 表中删除指定的用户-代币关联记录
func (m *TokenModel) RemoveFavorite(ctx context.Context, userID, tokenID int64) error {
	_, err := m.db.Exec(ctx, `
		DELETE FROM user_favorites WHERE user_id = $1 AND token_id = $2
	`, userID, tokenID)
	return err
}

// GetNextNonce 获取下一个 nonce 值
// 查询当前最大 nonce 并加 1，用于 CREATE2 地址预测
// 注意：在高并发场景下可能产生竞争条件，生产环境应使用数据库序列或事务
func (m *TokenModel) GetNextNonce(ctx context.Context) (int, error) {
	var nonce int
	err := m.db.QueryRow(ctx, `
		SELECT COALESCE(MAX(nonce), 0) + 1 FROM tokens
	`).Scan(&nonce)
	return nonce, err
}
