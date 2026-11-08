// invite.go - 邀请/代理数据模型
// 本文件封装了对 invites、agents、rebate_records 表的数据库操作
// 提供邀请状态查询、佣金查询、邀请列表查询和返利记录管理等功能
package model

import (
	"context" // 上下文包
	"time"    // 时间包

	"github.com/jackc/pgx/v5/pgxpool" // PostgreSQL 连接池
)

// Invite 邀请记录模型
// 对应数据库中的 invites 表，记录邀请人与被邀请人的关系
type Invite struct {
	ID             int64     `json:"id"`             // 邀请记录 ID
	InviterID      int64     `json:"inviterId"`      // 邀请人用户 ID
	InviteeID      int64     `json:"inviteeId"`      // 被邀请人用户 ID
	InviterAddress string    `json:"inviterAddress"` // 邀请人钱包地址
	InviteeAddress string    `json:"inviteeAddress"` // 被邀请人钱包地址
	InvitationCode string    `json:"invitationCode"` // 邀请码
	CreatedAt      time.Time `json:"createdAt"`      // 创建时间
}

// Agent 代理模型
// 对应数据库中的 agents 表，记录代理（推广员）的信息
type Agent struct {
	ID             int64     `json:"id"`             // 代理 ID
	UserID         int64     `json:"userId"`         // 关联的用户 ID
	Address        string    `json:"address"`        // 代理钱包地址
	InvitationCode string    `json:"invitationCode"` // 代理的邀请码
	Level          int       `json:"level"`          // 代理等级
	ParentID       int64     `json:"parentId"`       // 上级代理 ID
	IsActive       bool      `json:"isActive"`       // 是否激活
	CreatedAt      time.Time `json:"createdAt"`      // 创建时间
}

// InviteModel 邀请数据访问模型
type InviteModel struct {
	db *pgxpool.Pool
}

// NewInviteModel 创建邀请模型实例
func NewInviteModel(db *pgxpool.Pool) *InviteModel {
	return &InviteModel{db: db}
}

// GetUserStatus 获取用户邀请状态
// 查询 agents 表判断用户是否为代理，以及其邀请码和激活状态
// 参数：address - 用户钱包地址
// 返回：包含 isAgent、invitationCode、address 的 map
func (m *InviteModel) GetUserStatus(ctx context.Context, address string) (map[string]interface{}, error) {
	// 初始化默认返回值（非代理用户）
	result := map[string]interface{}{
		"isAgent":        false,       // 默认不是代理
		"invitationCode": "",          // 默认无邀请码
		"address":        address,     // 用户地址
	}

	// 查询 agents 表
	var invitationCode string
	var isActive bool
	err := m.db.QueryRow(ctx, `
		SELECT invitation_code, is_active FROM agents
		WHERE LOWER(address) = LOWER($1)
	`, address).Scan(&invitationCode, &isActive)

	if err == nil {
		// 查询成功，说明用户是代理
		result["isAgent"] = isActive          // 使用 is_active 字段判断代理是否激活
		result["invitationCode"] = invitationCode // 返回邀请码
	}
	// 查询失败（通常是 ErrNoRows），保持默认值

	return result, nil
}

// GetUserCommission 获取用户佣金信息
// 查询邀请人数和佣金总额
// 参数：address - 用户钱包地址
// 返回：包含 address、totalFee、inviteUserCount、tradingUserCount、totalRebateFee 的 map
func (m *InviteModel) GetUserCommission(ctx context.Context, address string) (map[string]interface{}, error) {
	// 初始化默认返回值
	result := map[string]interface{}{
		"address":          address,  // 用户地址
		"totalFee":         0.0,      // 累计佣金总额
		"inviteUserCount":  0,        // 邀请人数
		"tradingUserCount": 0,        // 交易用户数（待实现）
		"totalRebateFee":   0.0,      // 累计返利总额
	}

	// 查询邀请人数
	// 从 invites 表统计该用户作为邀请人的记录数
	var inviteCount int
	m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM invites
		WHERE LOWER(inviter_address) = LOWER($1)
	`, address).Scan(&inviteCount)
	result["inviteUserCount"] = inviteCount

	// 查询佣金总额
	// 从 rebate_records 表统计状态为已完成(status=1)的佣金总和
	var totalFee float64
	m.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(amount), 0) FROM rebate_records
		WHERE LOWER(user_address) = LOWER($1) AND status = 1
	`, address).Scan(&totalFee)
	result["totalFee"] = totalFee
	result["totalRebateFee"] = totalFee // 暂时与 totalFee 相同

	return result, nil
}

// GetUserInvites 获取用户邀请列表
// 查询指定用户邀请的所有下线用户
// 参数：address - 邀请人地址，page/size - 分页参数
// 返回：邀请记录列表、总数、错误
func (m *InviteModel) GetUserInvites(ctx context.Context, address string, page, size int) ([]map[string]interface{}, int, error) {
	// 查询邀请总数
	var total int
	err := m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM invites
		WHERE LOWER(inviter_address) = LOWER($1)
	`, address).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// 查询邀请列表
	// LEFT JOIN users 获取被邀请人的用户名
	offset := (page - 1) * size
	rows, err := m.db.Query(ctx, `
		SELECT i.id, i.invitee_address, u.username, i.created_at
		FROM invites i
		LEFT JOIN users u ON i.invitee_id = u.id
		WHERE LOWER(i.inviter_address) = LOWER($1)
		ORDER BY i.created_at DESC
		LIMIT $2 OFFSET $3
	`, address, size, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	// 构建邀请列表
	var invites []map[string]interface{}
	for rows.Next() {
		var id int64
		var inviteeAddress, username string
		var createdAt time.Time
		if err := rows.Scan(&id, &inviteeAddress, &username, &createdAt); err != nil {
			return nil, 0, err
		}
		invites = append(invites, map[string]interface{}{
			"id":             id,                               // 邀请记录 ID
			"inviteeAddress": inviteeAddress,                   // 被邀请人地址
			"username":       username,                         // 被邀请人用户名
			"createdAt":      createdAt.Format(time.RFC3339),   // 邀请时间
		})
	}

	return invites, total, nil
}

// CreateRebateRecord 创建返佣记录
// 当被邀请人产生交易时，为其邀请人创建返佣记录
// 参数：userID - 邀请人用户 ID，traderID - 交易者用户 ID，userAddr - 邀请人地址，amount - 返佣金额，status - 状态
func (m *InviteModel) CreateRebateRecord(ctx context.Context, userID, traderID int64, userAddr string, amount float64, status int) error {
	_, err := m.db.Exec(ctx, `
		INSERT INTO rebate_records (user_id, trader_id, user_address, amount, status, created_at)
		VALUES ($1, $2, $3, $4, $5, NOW())
	`, userID, traderID, userAddr, amount, status)
	return err
}

// CheckRebateRecordStatus 检查返佣记录状态
// 查询指定地址是否有待处理的返佣记录（status=0 表示待处理）
// 参数：address - 用户钱包地址
// 返回：是否有待处理的记录（bool）
func (m *InviteModel) CheckRebateRecordStatus(ctx context.Context, address string) (bool, error) {
	var count int
	err := m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM rebate_records
		WHERE LOWER(user_address) = LOWER($1) AND status = 0
	`, address).Scan(&count)
	return count > 0, err
}
