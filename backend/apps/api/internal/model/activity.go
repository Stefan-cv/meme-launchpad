// activity.go - 活动数据模型
// 本文件封装了对 activities 表的数据库操作，提供活动的创建和查询功能
package model

import (
	"context"     // 上下文包
	"database/sql" // SQL 类型包，提供 NullString/NullInt64
	"time"        // 时间包

	"github.com/jackc/pgx/v5/pgxpool" // PostgreSQL 连接池
)

// Activity 活动数据模型
// 对应数据库中的 activities 表
type Activity struct {
	ID                    int64          `json:"id"`                    // 活动 ID（主键）
	Name                  string         `json:"name"`                  // 活动名称
	Description           string         `json:"description"`           // 活动描述
	CategoryType          int            `json:"categoryType"`          // 活动分类类型
	PlayType              int            `json:"playType"`              // 玩法类型
	RewardTokenType       int            `json:"rewardTokenType"`       // 奖励代币类型
	RewardAmount          string         `json:"rewardAmount"`          // 奖励数量
	RewardSlots           string         `json:"rewardSlots"`           // 奖励名额
	StartAt               time.Time      `json:"startAt"`               // 活动开始时间
	EndAt                 time.Time      `json:"endAt"`                 // 活动结束时间
	CoverImage            string         `json:"coverImage"`            // 封面图片 URL
	TokenID               int64          `json:"tokenId"`               // 关联的代币 ID
	InitiatorType         int            `json:"initiatorType"`         // 发起者类型
	AudienceType          int            `json:"audienceType"`          // 受众类型
	CreatorID             int64          `json:"creatorId"`             // 创建者用户 ID
	Status                int            `json:"status"`                // 状态：1=进行中, 2=已结束, 3=已取消
	MinDailyTradeAmount   sql.NullString `json:"minDailyTradeAmount"`   // 最低日交易量要求（可为 NULL）
	InviteMinCount        sql.NullString `json:"inviteMinCount"`        // 最低邀请人数要求（可为 NULL）
	InviteeMinTradeAmount sql.NullString `json:"inviteeMinTradeAmount"` // 被邀请人最低交易量（可为 NULL）
	HeatVoteTarget        sql.NullString `json:"heatVoteTarget"`        // 热度投票目标（可为 NULL）
	CommentMinCount       sql.NullString `json:"commentMinCount"`       // 最低评论数要求（可为 NULL）
	RewardTokenID         sql.NullInt64  `json:"rewardTokenId"`         // 奖励代币 ID（可为 NULL）
	RewardTokenAddress    sql.NullString `json:"rewardTokenAddress"`    // 奖励代币地址（可为 NULL）
	CreatedAt             time.Time      `json:"createdAt"`             // 创建时间
	UpdatedAt             time.Time      `json:"updatedAt"`             // 更新时间
}

// ActivityModel 活动数据访问模型
type ActivityModel struct {
	db *pgxpool.Pool
}

// NewActivityModel 创建活动模型实例
func NewActivityModel(db *pgxpool.Pool) *ActivityModel {
	return &ActivityModel{db: db}
}

// Create 创建活动
// 将活动信息插入 activities 表
// 创建时状态固定为 1（进行中）
func (m *ActivityModel) Create(ctx context.Context, activity *Activity) error {
	return m.db.QueryRow(ctx, `
		INSERT INTO activities (
			name, description, category_type, play_type,
			reward_token_type, reward_amount, reward_slots,
			start_at, end_at, cover_image, token_id,
			initiator_type, audience_type, creator_id, status,
			min_daily_trade_amount, invite_min_count, invitee_min_trade_amount,
			heat_vote_target, comment_min_count, reward_token_id, reward_token_address,
			created_at, updated_at
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
			$12, $13, $14, 1, $15, $16, $17, $18, $19, $20, $21,
			NOW(), NOW()
		)
		RETURNING id, created_at
	`,
		activity.Name, activity.Description, activity.CategoryType, activity.PlayType,
		activity.RewardTokenType, activity.RewardAmount, activity.RewardSlots,
		activity.StartAt, activity.EndAt, activity.CoverImage, activity.TokenID,
		activity.InitiatorType, activity.AudienceType, activity.CreatorID,
		activity.MinDailyTradeAmount, activity.InviteMinCount, activity.InviteeMinTradeAmount,
		activity.HeatVoteTarget, activity.CommentMinCount, activity.RewardTokenID, activity.RewardTokenAddress,
	).Scan(&activity.ID, &activity.CreatedAt)
}

// FindUserParticipated 获取用户参与的活动
// 当前为简化实现，返回空结果
func (m *ActivityModel) FindUserParticipated(ctx context.Context, userID int64, params map[string]interface{}) ([]*Activity, int, error) {
	// 简化实现，待后续完善
	return nil, 0, nil
}

// FindUserCreated 获取用户创建的活动
// 查询指定用户创建的活动列表，按创建时间倒序排列
func (m *ActivityModel) FindUserCreated(ctx context.Context, userID int64, params map[string]interface{}) ([]*Activity, int, error) {
	// 分页参数处理
	pageNo := 1
	pageSize := 10
	if pn, ok := params["pageNo"].(int); ok && pn > 0 {
		pageNo = pn
	}
	if ps, ok := params["pageSize"].(int); ok && ps > 0 {
		pageSize = ps
	}

	// 查询用户创建的活动总数
	var total int
	err := m.db.QueryRow(ctx, `
		SELECT COUNT(*) FROM activities WHERE creator_id = $1
	`, userID).Scan(&total)
	if err != nil {
		return nil, 0, err
	}

	// 查询活动列表
	offset := (pageNo - 1) * pageSize
	rows, err := m.db.Query(ctx, `
		SELECT id, name, description, category_type, play_type,
			reward_token_type, reward_amount, reward_slots,
			start_at, end_at, cover_image, token_id,
			initiator_type, audience_type, creator_id, status,
			created_at
		FROM activities
		WHERE creator_id = $1
		ORDER BY created_at DESC
		LIMIT $2 OFFSET $3
	`, userID, pageSize, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	// 遍历查询结果
	var activities []*Activity
	for rows.Next() {
		var a Activity
		err := rows.Scan(
			&a.ID, &a.Name, &a.Description, &a.CategoryType, &a.PlayType,
			&a.RewardTokenType, &a.RewardAmount, &a.RewardSlots,
			&a.StartAt, &a.EndAt, &a.CoverImage, &a.TokenID,
			&a.InitiatorType, &a.AudienceType, &a.CreatorID, &a.Status,
			&a.CreatedAt,
		)
		if err != nil {
			return nil, 0, err
		}
		activities = append(activities, &a)
	}

	return activities, total, nil
}
