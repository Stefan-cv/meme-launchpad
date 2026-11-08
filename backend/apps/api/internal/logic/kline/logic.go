// logic.go - K线数据查询业务逻辑
// 本文件实现了代币 K 线（蜡烛图）历史数据的查询功能
// 支持两种分页模式：普通分页（基于时间范围）和游标分页（基于 cursor）
package kline

import (
	"context"         // 上下文包
	"encoding/base64" // Base64 编解码，用于游标的编码/解码
	"time"            // 时间包

	"github.com/meme-launchpad/api/internal/svc"   // 服务上下文
	"github.com/meme-launchpad/api/internal/types"  // 请求/响应类型
	"github.com/zeromicro/go-zero/core/logx"       // 日志库
)

// ==================== 游标分页模式 ====================

// GetKlineHistoryWithCursorLogic 游标分页 K 线查询逻辑
type GetKlineHistoryWithCursorLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

// NewGetKlineHistoryWithCursorLogic 创建游标分页 K 线查询逻辑实例
func NewGetKlineHistoryWithCursorLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetKlineHistoryWithCursorLogic {
	return &GetKlineHistoryWithCursorLogic{
		Logger: logx.WithContext(ctx),
		ctx:    ctx,
		svcCtx: svcCtx,
	}
}

// GetKlineHistoryWithCursor 使用游标分页获取 K 线数据
// 游标分页的优势：避免深分页的性能问题（传统 OFFSET 分页在数据量大时很慢）
// 参数：req - 包含代币地址、时间间隔、游标和数量限制的请求
// 返回：K 线数据和下一个游标
// 执行流程：
//   1. 验证必填参数（代币地址、时间间隔）
//   2. 验证时间间隔格式是否合法
//   3. 设置默认和最大限制
//   4. 解码游标（base64 编码的时间戳）
//   5. 查询数据库
//   6. 构建响应数据（时间、开高低收、成交量）
//   7. 生成下一个游标
func (l *GetKlineHistoryWithCursorLogic) GetKlineHistoryWithCursor(req *types.KlineHistoryWithCursorRequest) (*types.Response, error) {
	// 参数验证：代币地址必填
	if req.TokenAddr == "" {
		return types.Error(400, "tokenAddr is required"), nil
	}
	// 参数验证：时间间隔必填
	if req.Interval == "" {
		return types.Error(400, "interval is required"), nil
	}

	// 验证时间间隔格式是否合法
	// 只支持预定义的几种时间间隔
	validIntervals := map[string]bool{
		"1m": true, "5m": true, "15m": true, "30m": true, // 分钟级
		"1h": true, "4h": true, "1d": true, "1w": true,  // 小时/天/周级
	}
	if !validIntervals[req.Interval] {
		return types.Error(400, "invalid interval"), nil
	}

	// 设置默认 limit 和限制范围
	limit := req.Limit
	if limit <= 0 {
		limit = 300 // 默认返回 300 条 K 线数据
	}
	if limit > 1000 {
		limit = 1000 // 最大返回 1000 条，防止一次性返回过多数据
	}

	// 解码游标（base64 编码的 RFC3339 时间戳）
	// 游标表示"从哪个时间点开始查询更早的数据"
	var cursorTime *time.Time
	if req.Cursor != "" {
		// Base64 解码游标字符串
		decoded, err := base64.StdEncoding.DecodeString(req.Cursor)
		if err == nil {
			// 尝试将解码后的字符串解析为时间
			if t, err := time.Parse(time.RFC3339, string(decoded)); err == nil {
				cursorTime = &t // 解析成功，设置游标时间
			}
		}
	}

	// 查询 K 线数据
	// 查询条件：指定代币地址、时间间隔、游标时间之前的数据
	// 按时间倒序排列（最新的数据在前）
	klines, err := l.svcCtx.KlineModel.FindByTokenAndInterval(l.ctx, req.TokenAddr, req.Interval, cursorTime, limit)
	if err != nil {
		l.Logger.Errorf("failed to get kline data: %v", err)
		return types.Error(500, "failed to get kline data"), nil
	}

	// 构建响应数据
	// K 线数据需要按时间顺序返回（从早到晚），但数据库查询是倒序的
	// 所以需要反转数组
	timestamps := make([]int64, 0, len(klines))  // 时间戳数组
	opens := make([]string, 0, len(klines))      // 开盘价数组
	highs := make([]string, 0, len(klines))      // 最高价数组
	lows := make([]string, 0, len(klines))       // 最低价数组
	closes := make([]string, 0, len(klines))     // 收盘价数组
	volumes := make([]string, 0, len(klines))    // 成交量数组

	// 反转遍历：由于查询是按时间倒序（DESC），klines[0]是最新的数据
	// 需要反转数组以符合 K 线图的时间顺序（从早到晚）
	for i := len(klines) - 1; i >= 0; i-- {
		k := klines[i]
		timestamps = append(timestamps, k.OpenTime.Unix()) // 开盘时间的 Unix 时间戳
		opens = append(opens, k.OpenPrice)                  // 开盘价
		highs = append(highs, k.HighPrice)                  // 最高价
		lows = append(lows, k.LowPrice)                     // 最低价
		closes = append(closes, k.ClosePrice)               // 收盘价
		volumes = append(volumes, k.Volume)                  // 成交量
	}

	// 生成下一个游标
	// 使用查询结果中最早的数据时间作为下一个游标
	// 前端下次请求使用此游标，就能获取更早的 K 线数据
	var nextCursor string
	if len(klines) > 0 {
		// klines[len-1] 是最早的数据（反转前是最后一个）
		earliestTime := klines[len(klines)-1].OpenTime
		// 将时间编码为 base64 字符串作为游标
		nextCursor = base64.StdEncoding.EncodeToString([]byte(earliestTime.Format(time.RFC3339)))
	}

	// 构建 K 线图专用的响应格式
	// "s" 字段：状态码，空字符串表示成功
	// "t" 字段：时间戳数组
	// "o" 字段：开盘价数组
	// "h" 字段：最高价数组
	// "l" 字段：最低价数组
	// "c" 字段：收盘价数组
	// "v" 字段：成交量数组
	response := map[string]interface{}{
		"cursor": nextCursor, // 下一页的游标
		"klines": map[string]interface{}{
			"s": "",          // 状态：空字符串表示成功
			"t": timestamps,  // 时间戳
			"o": opens,       // 开盘价
			"h": highs,       // 最高价
			"l": lows,        // 最低价
			"c": closes,      // 收盘价
			"v": volumes,     // 成交量
		},
	}

	return types.Success(response), nil
}

// ==================== 普通分页模式 ====================

// GetKlineHistoryLogic 普通 K 线查询逻辑
type GetKlineHistoryLogic struct {
	logx.Logger
	ctx    context.Context
	svcCtx *svc.ServiceContext
}

// NewGetKlineHistoryLogic 创建普通 K 线查询逻辑实例
func NewGetKlineHistoryLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetKlineHistoryLogic {
	return &GetKlineHistoryLogic{
		Logger: logx.WithContext(ctx),
		ctx:    ctx,
		svcCtx: svcCtx,
	}
}

// GetKlineHistory 使用普通分页获取 K 线数据
// 需要指定时间范围（from/to），适用于已知时间范围的场景
// 参数：req - 包含代币地址、时间间隔、起止时间的请求
// 返回：K 线数据
func (l *GetKlineHistoryLogic) GetKlineHistory(req *types.KlineHistoryRequest) (*types.Response, error) {
	// 参数验证：代币地址必填
	if req.TokenAddr == "" {
		return types.Error(400, "tokenAddr is required"), nil
	}
	// 参数验证：时间间隔必填
	if req.Interval == "" {
		return types.Error(400, "interval is required"), nil
	}
	// 参数验证：起止时间必须有效
	if req.From <= 0 || req.To <= 0 {
		return types.Error(400, "from and to are required"), nil
	}
	// 参数验证：起始时间不能大于结束时间
	if req.From > req.To {
		return types.Error(400, "from must be less than to"), nil
	}

	// 验证时间间隔格式
	validIntervals := map[string]bool{
		"1m": true, "5m": true, "15m": true, "30m": true,
		"1h": true, "4h": true, "1d": true, "1w": true,
	}
	if !validIntervals[req.Interval] {
		return types.Error(400, "invalid interval"), nil
	}

	// 查询指定时间范围内的 K 线数据
	// 数据按时间正序排列（从早到晚）
	klines, err := l.svcCtx.KlineModel.FindByTokenAndIntervalRange(l.ctx, req.TokenAddr, req.Interval, req.From, req.To)
	if err != nil {
		l.Logger.Errorf("failed to get kline data: %v", err)
		return types.Error(500, "failed to get kline data"), nil
	}

	// 构建响应数据
	timestamps := make([]int64, 0, len(klines))
	opens := make([]string, 0, len(klines))
	highs := make([]string, 0, len(klines))
	lows := make([]string, 0, len(klines))
	closes := make([]string, 0, len(klines))
	volumes := make([]string, 0, len(klines))

	// 普通分页模式下数据已经是正序，直接遍历即可
	for _, k := range klines {
		timestamps = append(timestamps, k.OpenTime.Unix())
		opens = append(opens, k.OpenPrice)
		highs = append(highs, k.HighPrice)
		lows = append(lows, k.LowPrice)
		closes = append(closes, k.ClosePrice)
		volumes = append(volumes, k.Volume)
	}

	// 构建 K 线数据响应
	// "s" 字段：状态码，"ok" 表示成功
	response := map[string]interface{}{
		"s": "ok",          // 状态："ok" 表示成功
		"t": timestamps,    // 时间戳
		"o": opens,         // 开盘价
		"h": highs,         // 最高价
		"l": lows,          // 最低价
		"c": closes,        // 收盘价
		"v": volumes,       // 成交量
	}

	return types.Success(response), nil
}
