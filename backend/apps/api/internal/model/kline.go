// kline.go - K线数据模型
// 本文件封装了对 klines 表的数据库操作，提供 K 线数据的查询功能
// 支持两种查询模式：游标分页和时间范围查询
package model

import (
	"context" // 上下文包
	"time"    // 时间包

	"github.com/jackc/pgx/v5/pgxpool" // PostgreSQL 连接池
)

// Kline K线数据模型
// 对应数据库中的 klines 表，存储代币的 K 线历史数据
type Kline struct {
	ID           int64     `json:"id"`           // K 线 ID（主键）
	TokenAddress string    `json:"tokenAddress"` // 代币合约地址
	Interval     string    `json:"interval"`     // 时间间隔（1m/5m/15m/30m/1h/4h/1d/1w）
	OpenTime     time.Time `json:"openTime"`     // 开盘时间
	OpenPrice    string    `json:"openPrice"`    // 开盘价
	HighPrice    string    `json:"highPrice"`    // 最高价
	LowPrice     string    `json:"lowPrice"`     // 最低价
	ClosePrice   string    `json:"closePrice"`   // 收盘价
	Volume       string    `json:"volume"`       // 成交量
	CreatedAt    time.Time `json:"createdAt"`    // 记录创建时间
}

// KlineModel K线数据访问模型
type KlineModel struct {
	db *pgxpool.Pool
}

// NewKlineModel 创建 K 线模型实例
func NewKlineModel(db *pgxpool.Pool) *KlineModel {
	return &KlineModel{db: db}
}

// GetDB 获取数据库连接池
func (m *KlineModel) GetDB() *pgxpool.Pool {
	return m.db
}

// FindByTokenAndInterval 根据代币地址和间隔查询 K 线数据（带游标分页）
// 用于"加载更多"场景：前端传入游标（上一页最早数据的时间），获取更早的数据
// 参数：
//   - tokenAddress: 代币合约地址
//   - interval: 时间间隔
//   - cursorTime: 游标时间（nil 表示从最新数据开始查询）
//   - limit: 返回数量限制
// 返回：K 线列表（按时间倒序）、错误
func (m *KlineModel) FindByTokenAndInterval(ctx context.Context, tokenAddress, interval string, cursorTime *time.Time, limit int) ([]*Kline, error) {
	// 限制查询数量范围
	if limit <= 0 {
		limit = 300 // 默认 300 条
	}
	if limit > 1000 {
		limit = 1000 // 最大 1000 条
	}

	// 构建 SQL 查询，数值字段使用 ::text 转换为字符串
	query := `
		SELECT id, token_address, interval, open_time,
			open_price::text, high_price::text, low_price::text, close_price::text,
			volume::text, created_at
		FROM klines
		WHERE LOWER(token_address) = LOWER($1) AND interval = $2
	`
	args := []interface{}{tokenAddress, interval}
	argIdx := 3

	// 如果有游标，添加时间条件（查询游标时间之前的数据）
	if cursorTime != nil {
		query += ` AND open_time < $` + string(rune('0'+argIdx))
		args = append(args, *cursorTime)
		argIdx++
	}

	// 按时间倒序排列（最新的数据在前），并限制返回数量
	query += ` ORDER BY open_time DESC LIMIT $` + string(rune('0'+argIdx))
	args = append(args, limit)

	rows, err := m.db.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	// 遍历查询结果
	var klines []*Kline
	for rows.Next() {
		var k Kline
		err := rows.Scan(
			&k.ID, &k.TokenAddress, &k.Interval, &k.OpenTime,
			&k.OpenPrice, &k.HighPrice, &k.LowPrice, &k.ClosePrice,
			&k.Volume, &k.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		klines = append(klines, &k)
	}

	return klines, nil
}

// FindByTokenAndIntervalRange 根据代币地址、间隔和时间范围查询 K 线数据
// 用于已知时间范围的场景：前端指定起止时间获取 K 线数据
// 参数：
//   - tokenAddress: 代币合约地址
//   - interval: 时间间隔
//   - from/to: 起止时间（Unix 时间戳）
// 返回：K 线列表（按时间正序）、错误
func (m *KlineModel) FindByTokenAndIntervalRange(ctx context.Context, tokenAddress, interval string, from, to int64) ([]*Kline, error) {
	// 将 Unix 时间戳转换为 time.Time
	fromTime := time.Unix(from, 0)
	toTime := time.Unix(to, 0)

	// 查询指定时间范围内的 K 线数据
	// 按时间正序排列（从早到晚）
	rows, err := m.db.Query(ctx, `
		SELECT id, token_address, interval, open_time,
			open_price::text, high_price::text, low_price::text, close_price::text,
			volume::text, created_at
		FROM klines
		WHERE LOWER(token_address) = LOWER($1)
		AND interval = $2
		AND open_time >= $3
		AND open_time <= $4
		ORDER BY open_time ASC
	`, tokenAddress, interval, fromTime, toTime)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var klines []*Kline
	for rows.Next() {
		var k Kline
		err := rows.Scan(
			&k.ID, &k.TokenAddress, &k.Interval, &k.OpenTime,
			&k.OpenPrice, &k.HighPrice, &k.LowPrice, &k.ClosePrice,
			&k.Volume, &k.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		klines = append(klines, &k)
	}

	return klines, nil
}
