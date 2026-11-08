// authmiddleware.go - JWT 认证中间件
// 本文件实现了 HTTP 请求的 JWT 认证逻辑，用于保护需要登录才能访问的接口
// 认证流程：从请求头提取 Bearer Token -> 解析 JWT -> 验证签名和有效期 -> 提取用户信息注入 Context
package middleware

import (
	"context"  // 上下文包，用于在请求链中传递用户身份信息
	"net/http" // HTTP 协议包
	"strings"  // 字符串处理包，用于解析 Authorization 头

	"github.com/golang-jwt/jwt/v5" // JWT 库，用于解析和验证 JSON Web Token
	"github.com/zeromicro/go-zero/rest/httpx" // go-zero HTTP 工具包
)

// AuthMiddleware 认证中间件结构体
// 持有 JWT 签名密钥，用于验证 Token 的合法性
type AuthMiddleware struct {
	accessSecret string // JWT 签名密钥，必须与签发 Token 时使用的密钥一致
}

// NewAuthMiddleware 创建认证中间件实例
// 参数：accessSecret - JWT 签名密钥
// 返回：认证中间件实例
func NewAuthMiddleware(accessSecret string) *AuthMiddleware {
	return &AuthMiddleware{accessSecret: accessSecret}
}

// UserClaims JWT claims 结构体
// 定义了 Token 中携带的用户身份信息
type UserClaims struct {
	UserID  int64  `json:"userId"`  // 用户 ID，数据库中的主键
	Address string `json:"address"` // 用户钱包地址（以太坊格式，0x 开头）
	jwt.RegisteredClaims               // 嵌入 JWT 标准字段（exp、iat 等）
}

// ctxKey Context 键的类型定义
// 使用自定义类型可以避免与第三方库的 Context 键冲突
type ctxKey string

const (
	CtxUserIDKey  ctxKey = "userId"  // Context 中存储用户 ID 的键
	CtxAddressKey ctxKey = "address" // Context 中存储钱包地址的键
)

// Handle 认证中间件的处理函数
// 实现了 go-zero 的 Middleware 接口
// 参数：next - 下一个处理函数（认证通过后调用）
// 返回：包装后的处理函数
// 执行流程：
//   1. 从请求头获取 Authorization 字段
//   2. 解析 Bearer Token 格式
//   3. 使用密钥验证 JWT 签名和有效期
//   4. 提取用户信息（ID、地址）注入到请求 Context
//   5. 调用下一个处理函数
func (m *AuthMiddleware) Handle(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// 获取 Authorization 请求头
		// 格式应为：Bearer eyJhbGciOiJIUzI1NiIs...
		authHeader := r.Header.Get("Authorization")
		if authHeader == "" {
			// 缺少 Authorization 头，返回认证错误
			httpx.ErrorCtx(r.Context(), w, NewAuthError("missing authorization header"))
			return
		}

		// 解析 Bearer token
		// 将 "Bearer eyJ..." 拆分为 ["Bearer", "eyJ..."] 两部分
		parts := strings.SplitN(authHeader, " ", 2)
		// 验证格式：必须有且仅有两部分，且第一部分为 "Bearer"（不区分大小写）
		if len(parts) != 2 || strings.ToLower(parts[0]) != "bearer" {
			// Authorization 格式无效，返回认证错误
			httpx.ErrorCtx(r.Context(), w, NewAuthError("invalid authorization format"))
			return
		}

		// 提取 Token 字符串
		tokenString := parts[1]

		// 解析并验证 JWT
		// ParseWithClaims 会验证签名算法、签名值和过期时间
		// keyFunc 返回签名密钥，用于验证签名
		token, err := jwt.ParseWithClaims(tokenString, &UserClaims{}, func(token *jwt.Token) (interface{}, error) {
			// 返回签名密钥的字节切片
			// JWT 库会使用此密钥验证 Token 的签名
			return []byte(m.accessSecret), nil
		})

		if err != nil || !token.Valid {
			// Token 无效（签名错误、过期、格式错误等），返回认证错误
			httpx.ErrorCtx(r.Context(), w, NewAuthError("invalid or expired token"))
			return
		}

		// 将 Token 的 Claims 转换为 UserClaims 类型
		claims, ok := token.Claims.(*UserClaims)
		if !ok {
			// Claims 类型断言失败，说明 Token 结构不符合预期
			httpx.ErrorCtx(r.Context(), w, NewAuthError("invalid token claims"))
			return
		}

		// 将用户信息添加到请求的 Context 中
		// 这样后续的处理函数就可以通过 Context 获取用户身份
		ctx := context.WithValue(r.Context(), CtxUserIDKey, claims.UserID)   // 注入用户 ID
		ctx = context.WithValue(ctx, CtxAddressKey, claims.Address)          // 注入钱包地址

		// 使用新的 Context 调用下一个处理函数
		// r.WithContext(ctx) 创建一个携带新 Context 的请求副本
		next(w, r.WithContext(ctx))
	}
}

// GetUserIDFromCtx 从 Context 获取用户 ID
// 参数：ctx - 请求上下文
// 返回：用户 ID，如果不存在则返回 0
// 用途：在业务逻辑层获取当前登录用户的 ID
func GetUserIDFromCtx(ctx context.Context) int64 {
	if userID, ok := ctx.Value(CtxUserIDKey).(int64); ok {
		// 成功获取用户 ID
		return userID
	}
	// Context 中没有用户 ID，返回 0 表示未认证
	return 0
}

// GetAddressFromCtx 从 Context 获取钱包地址
// 参数：ctx - 请求上下文
// 返回：钱包地址字符串，如果不存在则返回空字符串
// 用途：在业务逻辑层获取当前登录用户的钱包地址
func GetAddressFromCtx(ctx context.Context) string {
	if address, ok := ctx.Value(CtxAddressKey).(string); ok {
		// 成功获取钱包地址
		return address
	}
	// Context 中没有钱包地址，返回空字符串表示未认证
	return ""
}

// AuthError 认证错误结构体
// 实现 error 接口，用于在中间件中返回认证相关的错误信息
type AuthError struct {
	Message string // 错误信息描述
}

// NewAuthError 创建认证错误实例
// 参数：message - 错误信息
// 返回：认证错误实例
func NewAuthError(message string) *AuthError {
	return &AuthError{Message: message}
}

// Error 实现 error 接口的 Error 方法
// 返回错误信息字符串
func (e *AuthError) Error() string {
	return e.Message
}
