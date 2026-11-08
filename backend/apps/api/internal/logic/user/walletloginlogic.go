// walletloginlogic.go - 钱包登录的业务逻辑
// 本文件实现了 Web3 钱包登录的核心流程：
// 验证以太坊签名 -> 查找或创建用户 -> 生成 JWT Token
package user

import (
	"context"  // 上下文包
	"crypto/rand" // 加密安全的随机数生成器
	"encoding/hex" // 十六进制编解码
	"errors"   // 错误处理包
	"fmt"      // 格式化输出
	"strings"  // 字符串处理
	"time"     // 时间包

	"github.com/ethereum/go-ethereum/common"     // 以太坊通用工具包
	"github.com/ethereum/go-ethereum/common/hexutil" // 以太坊十六进制工具包
	"github.com/ethereum/go-ethereum/crypto"      // 以太坊加密工具包（签名验证等）
	"github.com/golang-jwt/jwt/v5"               // JWT 库
	"github.com/jackc/pgx/v5"                    // PostgreSQL 驱动
	"github.com/meme-launchpad/api/internal/model" // 数据模型
	"github.com/meme-launchpad/api/internal/svc"   // 服务上下文
	"github.com/meme-launchpad/api/internal/types"  // 请求/响应类型
	"github.com/zeromicro/go-zero/core/logx"       // 日志库
)

// WalletLoginLogic 钱包登录业务逻辑结构体
type WalletLoginLogic struct {
	logx.Logger              // 嵌入日志器
	ctx    context.Context   // 请求上下文
	svcCtx *svc.ServiceContext // 服务上下文
}

// NewWalletLoginLogic 创建钱包登录逻辑实例
func NewWalletLoginLogic(ctx context.Context, svcCtx *svc.ServiceContext) *WalletLoginLogic {
	return &WalletLoginLogic{
		Logger: logx.WithContext(ctx),
		ctx:    ctx,
		svcCtx: svcCtx,
	}
}

// WalletLogin 钱包登录的核心业务逻辑
// 参数：req - 包含钱包地址和签名的请求
// 返回：包含 JWT Token 和用户信息的响应
// 执行流程：
//   1. 验证钱包地址格式
//   2. 从 Redis 获取之前存储的 nonce
//   3. 重建签名消息
//   4. 验证以太坊签名（ECDSA 恢复公钥并比对地址）
//   5. 删除已使用的 nonce（防止重放）
//   6. 查找或创建用户
//   7. 生成 Access Token 和 Refresh Token
//   8. 返回 Token 和用户信息
func (l *WalletLoginLogic) WalletLogin(req *types.WalletLoginRequest) (*types.Response, error) {
	// 将地址转为小写，确保一致性
	address := strings.ToLower(req.Address)

	// 验证地址格式：必须是 0x 开头的 42 字符字符串
	if len(address) != 42 || !strings.HasPrefix(address, "0x") {
		return types.Error(400, "invalid address format"), nil
	}

	// 从 Redis 获取之前通过 GetSignMsg 存储的 nonce
	// 如果 nonce 不存在或已过期，说明用户没有先获取签名消息，或消息已过期
	cacheKey := fmt.Sprintf("sign_msg:%s", address)
	nonce, err := l.svcCtx.Redis.Get(l.ctx, cacheKey).Result()
	if err != nil {
		// nonce 不存在或 Redis 出错，要求用户重新获取签名消息
		return types.Error(400, "nonce expired or not found, please request sign message again"), nil
	}

	// 重建签名消息（必须与 GetSignMsg 中构建的消息完全一致）
	message := fmt.Sprintf(
		"Welcome to Coinroll!\n\nClick to sign in and accept the Terms of Service.\n\nThis request will not trigger a blockchain transaction or cost any gas fees.\n\nWallet address:\n%s\n\nNonce:\n%s",
		address,
		nonce,
	)

	// 验证签名：使用以太坊签名恢复算法验证签名是否有效
	if !verifySignature(address, message, req.Signature) {
		// 签名验证失败，可能是因为签名不是由该地址的私钥生成的
		return types.Error(400, "invalid signature"), nil
	}

	// 签名验证通过后，立即删除 Redis 中的 nonce
	// 这样可以防止同一个 nonce 被重复使用（防止重放攻击）
	l.svcCtx.Redis.Del(l.ctx, cacheKey)

	// 查找用户：根据钱包地址在数据库中查找
	user, err := l.svcCtx.UserModel.FindByAddress(l.ctx, address)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			// 用户不存在，创建新用户
			newNonce := generateNonce() // 为新用户生成一个新的 nonce，用于下次登录
			user = &model.User{
				Address:  address,                    // 钱包地址
				Username: shortenAddress(address),    // 默认用户名为地址缩写（0x1234...5678）
				Nonce:    newNonce,                   // 新的 nonce 值
			}
			// 将新用户写入数据库
			if err := l.svcCtx.UserModel.Create(l.ctx, user); err != nil {
				l.Logger.Errorf("failed to create user: %v", err)
				return types.Error(500, "failed to create user"), nil
			}
		} else {
			// 数据库查询出错（不是"未找到"错误），记录日志并返回 500
			l.Logger.Errorf("failed to find user: %v", err)
			return types.Error(500, "database error"), nil
		}
	} else {
		// 用户已存在，更新 nonce 值
		// 每次成功登录后都需要更新 nonce，确保下次登录时使用新的 nonce
		newNonce := generateNonce()
		if err := l.svcCtx.UserModel.UpdateNonce(l.ctx, address, newNonce); err != nil {
			// nonce 更新失败，仅记录日志，不阻塞登录流程
			l.Logger.Errorf("failed to update nonce: %v", err)
		}
	}

	// 生成 Access Token（短期令牌，用于日常 API 访问）
	accessToken, err := l.generateAccessToken(user)
	if err != nil {
		return types.Error(500, "failed to generate token"), nil
	}

	// 生成 Refresh Token（长期令牌，用于无感刷新 Access Token）
	refreshToken, err := l.generateRefreshToken(user)
	if err != nil {
		return types.Error(500, "failed to generate refresh token"), nil
	}

	// 返回登录成功响应，包含 Token 和用户信息
	return types.Success(types.LoginResponse{
		Token:        accessToken,                      // Access Token
		RefreshToken: refreshToken,                     // Refresh Token
		ExpiresIn:    l.svcCtx.Config.Auth.AccessExpire, // Access Token 有效期（秒）
		TokenType:    "Bearer",                          // Token 类型
		User: map[string]interface{}{
			"id":        user.ID,                             // 用户 ID
			"address":   user.Address,                        // 钱包地址
			"username":  user.Username,                       // 用户名
			"email":     user.Email,                          // 邮箱
			"avatar":    user.Avatar,                         // 头像 URL
			"createdAt": user.CreatedAt.Format(time.RFC3339), // 注册时间
			"updatedAt": user.UpdatedAt.Format(time.RFC3339), // 更新时间
		},
	}), nil
}

// generateAccessToken 生成 Access Token
// 参数：user - 用户模型实例
// 返回：JWT Token 字符串和错误
// Access Token 用于日常 API 访问认证，有效期较短
func (l *WalletLoginLogic) generateAccessToken(user *model.User) (string, error) {
	// 构建 JWT Claims（声明），包含用户身份信息和标准字段
	claims := jwt.MapClaims{
		"userId":  user.ID,     // 用户 ID，业务层用于识别用户
		"address": user.Address, // 钱包地址，用于代币创建等需要地址的操作
		"exp":     time.Now().Add(time.Duration(l.svcCtx.Config.Auth.AccessExpire) * time.Second).Unix(), // 过期时间
		"iat":     time.Now().Unix(), // 签发时间
	}

	// 使用 HS256 算法创建带 Claims 的 Token
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	// 使用配置的密钥签名 Token
	return token.SignedString([]byte(l.svcCtx.Config.Auth.AccessSecret))
}

// generateRefreshToken 生成 Refresh Token
// 参数：user - 用户模型实例
// 返回：JWT Token 字符串和错误
// Refresh Token 用于在 Access Token 过期后获取新的 Token 对，有效期较长
func (l *WalletLoginLogic) generateRefreshToken(user *model.User) (string, error) {
	// 构建 JWT Claims，包含 "type": "refresh" 标识用于区分 Token 类型
	claims := jwt.MapClaims{
		"userId":  user.ID,     // 用户 ID
		"address": user.Address, // 钱包地址
		"type":    "refresh",   // Token 类型标识，用于刷新时验证
		"exp":     time.Now().Add(time.Duration(l.svcCtx.Config.Auth.RefreshExpire) * time.Second).Unix(), // 过期时间（较长）
		"iat":     time.Now().Unix(), // 签发时间
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString([]byte(l.svcCtx.Config.Auth.AccessSecret))
}

// verifySignature 验证以太坊签名
// 参数：address - 预期签名者地址，message - 原始消息，signature - 签名（hex 编码）
// 返回：签名是否有效
// 验证流程：
//   1. 添加以太坊签名前缀（\x19Ethereum Signed Message:\n{length}）
//   2. 计算前缀消息的 keccak256 哈希
//   3. 从签名中恢复公钥
//   4. 从公钥推导地址并与预期地址比较
func verifySignature(address, message, signature string) bool {
	// 添加以太坊签名前缀
	// MetaMask 等钱包在签名时会自动添加此前缀（EIP-191 个人签名规范）
	prefix := fmt.Sprintf("\x19Ethereum Signed Message:\n%d", len(message))
	prefixedMessage := prefix + message

	// 计算带前缀消息的 keccak256 哈希
	hash := crypto.Keccak256Hash([]byte(prefixedMessage))

	// 解码签名的十六进制字符串为字节切片
	sigBytes, err := hexutil.Decode(signature)
	if err != nil {
		// 签名格式无效
		return false
	}

	// 检查签名长度必须为 65 字节（r=32 + s=32 + v=1）
	if len(sigBytes) != 65 {
		return false
	}

	// 调整 v 值
	// 以太坊签名恢复 ID：MetaMask 返回 v=27 或 v=28
	// go-ethereum 的 SigToPub 需要 v=0 或 v=1
	// 所以如果 v >= 27，需要减去 27
	if sigBytes[64] >= 27 {
		sigBytes[64] -= 27
	}

	// 从签名和消息哈希恢复公钥
	pubKey, err := crypto.SigToPub(hash.Bytes(), sigBytes)
	if err != nil {
		// 公钥恢复失败（签名可能已损坏）
		return false
	}

	// 从公钥推导出以太坊地址
	recoveredAddress := crypto.PubkeyToAddress(*pubKey)

	// 比较恢复出的地址与预期地址（忽略大小写）
	return strings.EqualFold(recoveredAddress.Hex(), address)
}

// generateNonce 生成随机 nonce
// 返回：32 字符的十六进制随机字符串
// 用于防止签名重放攻击
func generateNonce() string {
	nonceBytes := make([]byte, 16) // 16 字节 = 32 个十六进制字符
	rand.Read(nonceBytes)          // 使用加密安全的随机数填充
	return hex.EncodeToString(nonceBytes)
}

// shortenAddress 缩短钱包地址显示
// 将 "0x1234567890abcdef...1234" 缩短为 "0x1234...1234"
// 用于默认用户名显示
func shortenAddress(address string) string {
	if len(address) < 10 {
		// 地址太短，直接返回（不应该出现这种情况）
		return address
	}
	// 取前 6 个字符 + "..." + 后 4 个字符
	return address[:6] + "..." + address[len(address)-4:]
}

// _ 是一个编译期类型断言函数，确保 common.Address 类型可用
// 这个函数永远不会被调用，仅用于确保 import 的类型正确
func _ (address string) common.Address {
	return common.HexToAddress(address)
}
