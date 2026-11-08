// refreshtokenlogic.go - 刷新令牌的业务逻辑
// 本文件实现了使用 Refresh Token 换取新 Access Token 的逻辑
// 令牌刷新机制允许用户在 Access Token 过期后无需重新登录即可继续使用
package user

import (
	"context" // 上下文包
	"time"    // 时间包

	"github.com/golang-jwt/jwt/v5"             // JWT 库
	"github.com/meme-launchpad/api/internal/svc"   // 服务上下文
	"github.com/meme-launchpad/api/internal/types"  // 请求/响应类型
	"github.com/zeromicro/go-zero/core/logx"       // 日志库
)

// RefreshTokenLogic 刷新令牌业务逻辑结构体
type RefreshTokenLogic struct {
	logx.Logger              // 嵌入日志器
	ctx    context.Context   // 请求上下文
	svcCtx *svc.ServiceContext // 服务上下文
}

// NewRefreshTokenLogic 创建刷新令牌逻辑实例
func NewRefreshTokenLogic(ctx context.Context, svcCtx *svc.ServiceContext) *RefreshTokenLogic {
	return &RefreshTokenLogic{
		Logger: logx.WithContext(ctx),
		ctx:    ctx,
		svcCtx: svcCtx,
	}
}

// RefreshToken 刷新令牌的核心业务逻辑
// 参数：req - 包含 Refresh Token 的请求
// 返回：包含新 Access Token 和 Refresh Token 的响应
// 执行流程：
//   1. 解析 Refresh Token 并验证签名
//   2. 验证 Token 类型是否为 "refresh"
//   3. 提取用户 ID 和地址
//   4. 生成新的 Access Token 和 Refresh Token
//   5. 返回新的 Token 对
func (l *RefreshTokenLogic) RefreshToken(req *types.RefreshTokenRequest) (*types.Response, error) {
	// 解析 Refresh Token
	// 使用配置的密钥验证 Token 的签名
	token, err := jwt.Parse(req.RefreshToken, func(token *jwt.Token) (interface{}, error) {
		// 提供签名密钥用于验证
		return []byte(l.svcCtx.Config.Auth.AccessSecret), nil
	})

	if err != nil || !token.Valid {
		// Token 无效或已过期，返回 401 未认证错误
		return types.Error(401, "invalid or expired refresh token"), nil
	}

	// 将 Token 的 Claims 转换为 MapClaims 类型
	claims, ok := token.Claims.(jwt.MapClaims)
	if !ok {
		// Claims 类型断言失败，Token 结构不符合预期
		return types.Error(401, "invalid token claims"), nil
	}

	// 验证 Token 类型是否为 "refresh"
	// 这一步至关重要：防止攻击者使用 Access Token 来刷新令牌
	tokenType, ok := claims["type"].(string)
	if !ok || tokenType != "refresh" {
		// Token 类型不是 "refresh"，拒绝刷新
		return types.Error(401, "invalid token type"), nil
	}

	// 从 Claims 中提取用户 ID
	// JWT 解析 JSON 数字时默认使用 float64 类型，需要转换
	userIDFloat, ok := claims["userId"].(float64)
	if !ok {
		// Claims 中没有有效的用户 ID
		return types.Error(401, "invalid user id in token"), nil
	}
	userID := int64(userIDFloat) // float64 -> int64

	// 从 Claims 中提取钱包地址
	address, ok := claims["address"].(string)
	if !ok {
		// Claims 中没有有效的地址
		return types.Error(401, "invalid address in token"), nil
	}

	// 生成新的 Access Token
	newAccessToken, err := l.generateAccessToken(userID, address)
	if err != nil {
		return types.Error(500, "failed to generate new token"), nil
	}

	// 生成新的 Refresh Token
	// 同时刷新 Refresh Token 可以实现"滑动窗口"过期策略
	newRefreshToken, err := l.generateRefreshToken(userID, address)
	if err != nil {
		return types.Error(500, "failed to generate new refresh token"), nil
	}

	// 返回新的 Token 对
	return types.Success(map[string]interface{}{
		"token":        newAccessToken,                      // 新的 Access Token
		"refreshToken": newRefreshToken,                     // 新的 Refresh Token
		"expiresIn":    l.svcCtx.Config.Auth.AccessExpire,   // Access Token 有效期（秒）
		"tokenType":    "Bearer",                             // Token 类型
	}), nil
}

// generateAccessToken 生成 Access Token
// 参数：userID - 用户 ID，address - 钱包地址
// 返回：JWT Token 字符串和错误
func (l *RefreshTokenLogic) generateAccessToken(userID int64, address string) (string, error) {
	// 构建 JWT Claims
	claims := jwt.MapClaims{
		"userId":  userID,   // 用户 ID
		"address": address,  // 钱包地址
		"exp":     time.Now().Add(time.Duration(l.svcCtx.Config.Auth.AccessExpire) * time.Second).Unix(), // 过期时间
		"iat":     time.Now().Unix(), // 签发时间
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(l.svcCtx.Config.Auth.AccessSecret))
}

// generateRefreshToken 生成 Refresh Token
// 参数：userID - 用户 ID，address - 钱包地址
// 返回：JWT Token 字符串和错误
func (l *RefreshTokenLogic) generateRefreshToken(userID int64, address string) (string, error) {
	// 构建 JWT Claims，包含 "type": "refresh" 标识
	claims := jwt.MapClaims{
		"userId":  userID,   // 用户 ID
		"address": address,  // 钱包地址
		"type":    "refresh", // Token 类型标识
		"exp":     time.Now().Add(time.Duration(l.svcCtx.Config.Auth.RefreshExpire) * time.Second).Unix(), // 过期时间（较长）
		"iat":     time.Now().Unix(), // 签发时间
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(l.svcCtx.Config.Auth.AccessSecret))
}
