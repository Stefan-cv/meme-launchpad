// comment.go - 评论数据模型
// 本文件封装了对 comments 表的数据库操作，提供评论的查询、创建、删除等功能
package model

import (
	"context"     // 上下文包
	"database/sql" // SQL 类型包，提供 NullString
	"time"        // 时间包

	"github.com/jackc/pgx/v5/pgxpool" // PostgreSQL 连接池
)

// Comment 评论数据模型
// 对应数据库中的 comments 表
type Comment struct {
	ID            int64          `json:"id"`            // 评论 ID（主键）
	TokenID       int64          `json:"tokenId"`       // 关联的代币 ID
	UserID        int64          `json:"userId"`        // 评论者用户 ID
	WalletAddress string         `json:"walletAddress"` // 评论者钱包地址（通过 JOIN users 获取）
	Content       sql.NullString `json:"content"`       // 评论文本内容（可为 NULL）
	Img           sql.NullString `json:"img"`           // 评论图片 URL（可为 NULL）
	HoldingAmount string         `json:"holdingAmount"` // 评论者的持仓数量
	CreatedAt     time.Time      `json:"createdAt"`     // 创建时间
	UpdatedAt     time.Time      `json:"updatedAt"`     // 更新时间
}

// CommentModel 评论数据访问模型
type CommentModel struct {
	db *pgxpool.Pool
}

// NewCommentModel 创建评论模型实例
func NewCommentModel(db *pgxpool.Pool) *CommentModel {
	return &CommentModel{db: db}
}

// FindList 获取评论列表
// 支持按代币 ID 筛选、时间筛选和分页
// 使用 LEFT JOIN users 获取评论者的钱包地址
// 使用 pageSize+1 技巧判断是否还有更多数据（hasMore）
// 参数：
//   - tokenID: 代币 ID
//   - pageNo/pageSize: 分页参数
//   - startTime: 时间筛选（查询此时间之前的评论，用于无限滚动）
// 返回：评论列表、总数、是否有更多数据、错误
func (m *CommentModel) FindList(ctx context.Context, tokenID int64, pageNo, pageSize int, startTime int64) ([]*Comment, int, bool, error) {
	// 查询评论总数
	var total int
	err := m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM comments WHERE token_id = $1
	`, tokenID).Scan(&total)
	if err != nil {
		return nil, 0, false, err
	}

	// 计算分页偏移量
	offset := (pageNo - 1) * pageSize
	// 构建 SQL 查询，JOIN users 表获取评论者地址
	query := `
		SELECT c.id, c.token_id, c.user_id, u.address, c.content, c.img, c.holding_amount, c.created_at
		FROM comments c
		LEFT JOIN users u ON c.user_id = u.id
		WHERE c.token_id = $1
	`
	args := []interface{}{tokenID}

	// 如果指定了 startTime，添加时间筛选条件
	// 用于"加载更多"场景：查询比指定时间更早的评论
	if startTime > 0 {
		query += ` AND c.created_at < to_timestamp($2)`
		args = append(args, startTime)
	}

	// 添加分页子句
	// 注意：LIMIT 使用 pageSize+1，多查一条用于判断是否有更多数据
	query += ` ORDER BY c.created_at DESC LIMIT $` + string(rune('0'+len(args)+1)) + ` OFFSET $` + string(rune('0'+len(args)+2))
	args = append(args, pageSize+1, offset) // +1 用于 hasMore 判断

	rows, err := m.db.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, false, err
	}
	defer rows.Close()

	// 遍历查询结果
	var comments []*Comment
	for rows.Next() {
		var c Comment
		err := rows.Scan(
			&c.ID, &c.TokenID, &c.UserID, &c.WalletAddress,
			&c.Content, &c.Img, &c.HoldingAmount, &c.CreatedAt,
		)
		if err != nil {
			return nil, 0, false, err
		}
		comments = append(comments, &c)
	}

	// 判断是否还有更多数据
	// 如果查询结果数 > pageSize，说明还有更多数据
	hasMore := len(comments) > pageSize
	if hasMore {
		comments = comments[:pageSize] // 截断多余的那一条
	}

	return comments, total, hasMore, nil
}

// Create 创建评论
func (m *CommentModel) Create(ctx context.Context, comment *Comment) error {
	return m.db.QueryRow(ctx, `
		INSERT INTO comments (token_id, user_id, content, img, holding_amount, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, NOW(), NOW())
		RETURNING id, created_at
	`, comment.TokenID, comment.UserID, comment.Content, comment.Img, comment.HoldingAmount).Scan(&comment.ID, &comment.CreatedAt)
}

// Delete 删除评论
// 同时验证 user_id，确保只能删除自己的评论
func (m *CommentModel) Delete(ctx context.Context, commentID, userID int64) error {
	_, err := m.db.Exec(ctx, `
		DELETE FROM comments WHERE id = $1 AND user_id = $2
	`, commentID, userID)
	return err
}

// FindByID 根据 ID 查找评论
func (m *CommentModel) FindByID(ctx context.Context, id int64) (*Comment, error) {
	var c Comment
	err := m.db.QueryRow(ctx, `
		SELECT id, token_id, user_id, content, img, holding_amount, created_at
		FROM comments WHERE id = $1
	`, id).Scan(&c.ID, &c.TokenID, &c.UserID, &c.Content, &c.Img, &c.HoldingAmount, &c.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &c, nil
}
