// getoverviewstatslogic.go - 获取用户概览统计的业务逻辑
// 本文件实现了查询用户概览统计信息的功能，包括创建代币数、加热代币数等
package user

import (
	"context" // 上下文包

	"github.com/meme-launchpad/api/internal/middleware" // 认证中间件，用于从 Context 获取用户信息
	"github.com/meme-launchpad/api/internal/svc"       // 服务上下文
	"github.com/meme-launchpad/api/internal/types"      // 请求/响应类型
	"github.com/zeromicro/go-zero/core/logx"           // 日志库
)

// GetOverviewStatsLogic 获取用户概览统计业务逻辑结构体
type GetOverviewStatsLogic struct {
	logx.Logger              // 嵌入日志器
	ctx    context.Context   // 请求上下文
	svcCtx *svc.ServiceContext // 服务上下文
}

// NewGetOverviewStatsLogic 创建获取概览统计逻辑实例
func NewGetOverviewStatsLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetOverviewStatsLogic {
	return &GetOverviewStatsLogic{
		Logger: logx.WithContext(ctx),
		ctx:    ctx,
		svcCtx: svcCtx,
	}
}

// GetOverviewStats 获取用户概览统计的核心业务逻辑
// 参数：req - 概览统计请求（可选包含地址参数）
// 返回：包含统计信息的响应
// 执行流程：
//   1. 确定查询地址：优先使用请求参数中的地址，其次使用当前登录用户地址
//   2. 调用 UserModel 获取统计数据
//   3. 返回统计结果
func (l *GetOverviewStatsLogic) GetOverviewStats(req *types.OverviewStatsRequest) (*types.Response, error) {
	// 获取查询地址
	// 优先使用请求参数中指定的地址（允许查看其他用户的统计）
	address := req.Address
	if address == "" {
		// 请求参数未指定地址，使用当前登录用户的地址
		// 从 JWT 认证中间件注入的 Context 中获取
		address = middleware.GetAddressFromCtx(l.ctx)
	}

	if address == "" {
		// 既没有请求参数，也没有登录用户，返回 400 错误
		return types.Error(400, "address is required"), nil
	}

	// 调用 UserModel 获取用户概览统计数据
	// 包括：创建的代币数、加热代币数、持有代币数、待解锁代币数、总交易 BNB 等
	stats, err := l.svcCtx.UserModel.GetOverviewStats(l.ctx, address)
	if err != nil {
		// 查询失败，记录错误日志并返回 500
		l.Logger.Errorf("failed to get overview stats: %v", err)
		return types.Error(500, "failed to get stats"), nil
	}

	// 返回统计数据
	return types.Success(stats), nil
}
