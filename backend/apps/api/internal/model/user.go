// user.go - 用户数据模型
// 本文件封装了对 users 表的数据库操作，提供用户的 CRUD 和概览统计功能
package model

import (
	"context" // 上下文包
	"time"    // 时间包

	"github.com/jackc/pgx/v5/pgxpool" // PostgreSQL 连接池
)

// User 用户数据模型
// 对应数据库中的 users 表
type User struct {
	ID        int64     `json:"id"`        // 用户 ID（主键，自增）
	Address   string    `json:"address"`   // 钱包地址（以太坊格式，唯一索引）
	Username  string    `json:"username"`  // 用户名（默认为地址缩写）
	Email     string    `json:"email"`     // 邮箱（可选）
	Avatar    string    `json:"avatar"`    // 头像 URL（可选）
	Nonce     string    `json:"nonce"`     // 登录 nonce（用于 Web3 签名验证，防止重放攻击）
	CreatedAt time.Time `json:"createdAt"` // 创建时间
	UpdatedAt time.Time `json:"updatedAt"` // 更新时间
}

// UserModel 用户数据访问模型
type UserModel struct {
	db *pgxpool.Pool
}

// NewUserModel 创建用户模型实例
func NewUserModel(db *pgxpool.Pool) *UserModel {
	return &UserModel{db: db}
}

// FindByAddress 根据钱包地址查找用户
// 使用 LOWER() 函数实现大小写不敏感的地址查询
// 使用 COALESCE 将 NULL 字段转换为空字符串，简化后续处理
func (m *UserModel) FindByAddress(ctx context.Context, address string) (*User, error) {
	var user User
	err := m.db.QueryRow(ctx, `
		SELECT id, address, COALESCE(username, ''), COALESCE(email, ''),
			COALESCE(avatar, ''), COALESCE(nonce, ''), created_at, updated_at
		FROM users
		WHERE LOWER(address) = LOWER($1)
	`, address).Scan(
		&user.ID, &user.Address, &user.Username, &user.Email,
		&user.Avatar, &user.Nonce, &user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

// FindByID 根据 ID 查找用户
func (m *UserModel) FindByID(ctx context.Context, id int64) (*User, error) {
	var user User
	err := m.db.QueryRow(ctx, `
		SELECT id, address, COALESCE(username, ''), COALESCE(email, ''),
			COALESCE(avatar, ''), COALESCE(nonce, ''), created_at, updated_at
		FROM users
		WHERE id = $1
	`, id).Scan(
		&user.ID, &user.Address, &user.Username, &user.Email,
		&user.Avatar, &user.Nonce, &user.CreatedAt, &user.UpdatedAt,
	)
	if err != nil {
		return nil, err
	}
	return &user, nil
}

// Create 创建用户
// 使用 RETURNING 子句获取自增 ID 和数据库生成的 created_at/updated_at
// 新用户通过钱包登录时自动创建
func (m *UserModel) Create(ctx context.Context, user *User) error {
	return m.db.QueryRow(ctx, `
		INSERT INTO users (address, username, nonce, created_at, updated_at)
		VALUES ($1, $2, $3, NOW(), NOW())
		RETURNING id, created_at, updated_at
	`, user.Address, user.Username, user.Nonce).Scan(&user.ID, &user.CreatedAt, &user.UpdatedAt)
}

// UpdateNonce 更新用户 nonce
// 每次成功登录后更新 nonce，确保下次登录使用新的随机值
// 使用 LOWER() 实现大小写不敏感的地址匹配
func (m *UserModel) UpdateNonce(ctx context.Context, address, nonce string) error {
	_, err := m.db.Exec(ctx, `
		UPDATE users SET nonce = $1, updated_at = NOW()
		WHERE LOWER(address) = LOWER($2)
	`, nonce, address)
	return err
}

// Update 更新用户信息
// 使用 COALESCE(NULLIF($1, ''), username) 实现只更新非空字段
// NULLIF 将空字符串转为 NULL，COALESCE 在 NULL 时保留原值
func (m *UserModel) Update(ctx context.Context, user *User) error {
	_, err := m.db.Exec(ctx, `
		UPDATE users SET
			username = COALESCE(NULLIF($1, ''), username),
			email = COALESCE(NULLIF($2, ''), email),
			avatar = COALESCE(NULLIF($3, ''), avatar),
			updated_at = NOW()
		WHERE id = $4
	`, user.Username, user.Email, user.Avatar, user.ID)
	return err
}

// GetOverviewStats 获取用户概览统计
// 查询用户创建的代币数等统计信息
func (m *UserModel) GetOverviewStats(ctx context.Context, address string) (map[string]interface{}, error) {
	stats := make(map[string]interface{})

	// 查询用户创建的代币数量
	var createdTokens int
	err := m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM tokens WHERE LOWER(creator_address) = LOWER($1)
	`, address).Scan(&createdTokens)
	if err != nil {
		return nil, err
	}
	stats["createdTokens"] = createdTokens

	// 以下统计字段为占位值，待后续实现
	stats["heatedTokens"] = 0           // 被加热的代币数
	stats["ownedTokens"] = 0            // 持有的代币数
	stats["pendingUnlockTokens"] = 0    // 待解锁的代币数
	stats["totalTradeBnb"] = "0"        // 总交易 BNB 数量

	return stats, nil
}
