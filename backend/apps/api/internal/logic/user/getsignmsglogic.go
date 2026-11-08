// getsignmsglogic.go - 获取签名消息的业务逻辑
// 本文件实现了 Web3 钱包登录流程的第一步：
// 根据用户钱包地址生成包含随机 nonce 的签名消息，并将 nonce 存入 Redis 用于后续验证
package user

import (
	"context"    // 上下文包，用于请求级别的超时控制和值传递
	"crypto/rand" // 加密安全的随机数生成器，用于生成不可预测的 nonce
	"encoding/hex" // 十六进制编解码，用于将随机字节转换为字符串
	"fmt"        // 格式化输出，用于构建签名消息
	"strings"    // 字符串处理，用于地址格式化
	"time"       // 时间包，用于设置 Redis 过期时间

	"github.com/meme-launchpad/api/internal/svc"   // 服务上下文
	"github.com/meme-launchpad/api/internal/types"  // 请求/响应类型
	"github.com/zeromicro/go-zero/core/logx"       // go-zero 日志库
)

// GetSignMsgLogic 获取签名消息的业务逻辑结构体
type GetSignMsgLogic struct {
	logx.Logger              // 嵌入日志器，支持带上下文的日志输出
	ctx    context.Context   // 请求上下文，用于超时控制和值传递
	svcCtx *svc.ServiceContext // 服务上下文，包含 Redis、数据库等全局依赖
}

// NewGetSignMsgLogic 创建获取签名消息逻辑实例
// 参数：ctx - 请求上下文，svcCtx - 服务上下文
func NewGetSignMsgLogic(ctx context.Context, svcCtx *svc.ServiceContext) *GetSignMsgLogic {
	return &GetSignMsgLogic{
		Logger: logx.WithContext(ctx), // 创建带上下文的日志器
		ctx:    ctx,                   // 保存请求上下文
		svcCtx: svcCtx,               // 保存服务上下文
	}
}

// GetSignMsg 获取签名消息的核心业务逻辑
// 参数：req - 包含钱包地址的请求
// 返回：包含签名消息、nonce 和过期时间的响应，以及错误信息
// 执行流程：
//   1. 验证钱包地址格式（必须是 0x 开头的 42 字符字符串）
//   2. 生成 16 字节随机 nonce（防止重放攻击）
//   3. 构建包含 nonce 的签名消息文本
//   4. 将 nonce 存入 Redis（5 分钟过期，确保 nonce 只能使用一次）
//   5. 返回消息、nonce 和过期时间
func (l *GetSignMsgLogic) GetSignMsg(req *types.GetSignMsgRequest) (*types.Response, error) {
	// 将地址转为小写，确保地址比较时大小写不敏感
	// 以太坊地址是大小写不敏感的（除了 EIP-55 校验和地址）
	address := strings.ToLower(req.Address)

	// 验证地址格式
	// 以太坊地址格式：0x 开头 + 40 个十六进制字符 = 42 字符
	if len(address) != 42 || !strings.HasPrefix(address, "0x") {
		// 地址格式无效，返回 400 错误
		return types.Error(400, "invalid address format"), nil
	}

	// 生成随机 nonce（16 字节 = 32 个十六进制字符）
	// 使用 crypto/rand 而非 math/rand，确保密码学安全性
	nonceBytes := make([]byte, 16) // 分配 16 字节的缓冲区
	if _, err := rand.Read(nonceBytes); err != nil {
		// 随机数生成失败（极端情况，如系统熵不足），返回 500 错误
		return types.Error(500, "failed to generate nonce"), nil
	}
	// 将随机字节编码为十六进制字符串（32 字符）
	nonce := hex.EncodeToString(nonceBytes)

	// 设置过期时间（5 分钟）
	// nonce 必须有有效期，否则用户可能使用旧的签名进行重放攻击
	expiry := time.Now().Add(5 * time.Minute).Unix()

	// 构建签名消息
	// 这个消息会显示在用户的 Web3 钱包（如 MetaMask）中
	// 消息格式遵循 EIP-4361（Sign-In with Ethereum）的精神
	// 包含：欢迎语、免责声明、钱包地址和 nonce
	message := fmt.Sprintf(
		"Welcome to Coinroll!\n\nClick to sign in and accept the Terms of Service.\n\nThis request will not trigger a blockchain transaction or cost any gas fees.\n\nWallet address:\n%s\n\nNonce:\n%s",
		address, // 用户的钱包地址，确保消息与地址绑定
		nonce,   // 随机 nonce，防止重放攻击
	)

	// 存储 nonce 到 Redis，用于后续登录时验证
	// 键格式：sign_msg:{address}，值为 nonce
	// 过期时间 5 分钟，与 expiry 一致
	cacheKey := fmt.Sprintf("sign_msg:%s", address)
	l.svcCtx.Redis.Set(l.ctx, cacheKey, nonce, 5*time.Minute)

	// 返回成功响应，包含签名消息、nonce 和过期时间
	return types.Success(types.GetSignMsgResponse{
		Message: message, // 完整的签名消息文本
		Nonce:   nonce,   // 随机 nonce 值
		Expiry:  expiry,  // 过期时间戳（Unix 秒级）
	}), nil
}
