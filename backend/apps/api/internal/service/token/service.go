// service.go - 代币业务服务
// 本文件实现了代币创建和地址计算的核心业务逻辑
// 主要功能包括：
//   1. 创建代币：获取 nonce、计算 CREATE2 预测地址、后端签名、保存创建请求
//   2. 计算地址：使用 CREATE2 确定性预测代币合约地址，支持靓号搜索
//   3. nonce 管理：通过数据库序列确保 nonce 唯一性
package token

import (
	"context"      // 上下文包
	"encoding/hex" // 十六进制编解码
	"fmt"          // 格式化输出
	"math/big"     // 大数运算包
	"strings"      // 字符串处理
	"time"         // 时间包

	"github.com/ethereum/go-ethereum/common" // 以太坊通用工具包
	"github.com/meme-launchpad/api/internal/model" // 数据模型
	"github.com/meme-launchpad/api/internal/service/crypto" // 加密服务（签名、CREATE2）
)

// 默认的代币经济参数
// 这些值与智能合约中的默认值保持一致
var (
	// DefaultTotalSupply 默认代币总供应量：10亿 * 10^18（18 位小数）
	DefaultTotalSupply = new(big.Int).Mul(big.NewInt(1e9), big.NewInt(1e18))
	// DefaultSaleAmount 默认销售数量：8亿 * 10^18（80% 用于销售）
	DefaultSaleAmount = new(big.Int).Mul(big.NewInt(8e8), big.NewInt(1e18))
	// DefaultVirtualBNBReserve 默认虚拟 BNB 储备量：约 8.22 BNB
	// 用于 Bonding Curve 定价曲线的初始参数
	DefaultVirtualBNBReserve = big.NewInt(8219178082191780000)
	// DefaultVirtualTokenReserve 默认虚拟代币储备量
	// 用于 Bonding Curve 定价曲线的初始参数
	DefaultVirtualTokenReserve = new(big.Int).Mul(big.NewInt(1073972602), big.NewInt(1e18))

	// DefaultTokenBytecode 默认代币字节码（空字符串表示未配置）
	// 实际生产中应从配置文件中读取
	DefaultTokenBytecode = ""
)

// TokenService 代币服务结构体
// 封装了代币创建和地址计算所需的所有依赖
type TokenService struct {
	tokenModel      *model.TokenModel       // 代币数据模型，用于数据库操作
	signer          *crypto.Signer          // 签名器，用于对创建参数进行 ECDSA 签名
	create2Calc     *crypto.Create2Calculator // CREATE2 计算器，用于预测合约地址
	coreContract    common.Address          // 核心合约地址，签名的合约参数
	factoryContract common.Address          // 工厂合约地址，CREATE2 的 deployer
	rpcURL          string                  // RPC 节点地址（预留）
	chainID         int64                   // 区块链网络 ID
}

// NewTokenService 创建代币服务实例
// 参数：
//   - signerPrivateKey: 后端签名者私钥（hex 格式）
//   - coreContract: 核心合约地址
//   - factoryContract: 工厂合约地址
//   - tokenBytecode: 代币合约字节码（用于 CREATE2 地址计算）
//   - rpcURL: RPC 节点地址
//   - chainID: 链 ID
//   - tokenModel: 代币数据模型
func NewTokenService(
	signerPrivateKey string,
	coreContract string,
	factoryContract string,
	tokenBytecode string,
	rpcURL string,
	chainID int64,
	tokenModel *model.TokenModel,
) *TokenService {
	var signer *crypto.Signer
	var create2Calc *crypto.Create2Calculator

	// 初始化签名器（需要有效的私钥）
	if signerPrivateKey != "" {
		var err error
		signer, err = crypto.NewSigner(signerPrivateKey)
		if err != nil {
			fmt.Printf("Warning: Failed to create signer: %v\n", err)
		}
	}

	// 初始化 CREATE2 计算器（需要工厂合约地址和代币字节码）
	bytecode := tokenBytecode
	if bytecode == "" {
		bytecode = DefaultTokenBytecode // 使用默认字节码
	}

	if factoryContract != "" && bytecode != "" {
		var err error
		create2Calc, err = crypto.NewCreate2Calculator(factoryContract, bytecode)
		if err != nil {
			fmt.Printf("Warning: Failed to create CREATE2 calculator: %v\n", err)
		}
	}

	return &TokenService{
		tokenModel:      tokenModel,
		signer:          signer,
		create2Calc:     create2Calc,
		coreContract:    common.HexToAddress(coreContract),
		factoryContract: common.HexToAddress(factoryContract),
		rpcURL:          rpcURL,
		chainID:         chainID,
	}
}

// CreateTokenRequest 创建代币请求参数
type CreateTokenRequest struct {
	Name                 string // 代币名称
	Symbol               string // 代币符号
	Description          string // 代币描述
	Logo                 string // Logo URL
	Banner               string // Banner URL
	Creator              string // 创建者地址
	LaunchMode           int    // 发行模式
	LaunchTime           int64  // 上线时间
	InitialBuyPercentage int    // 初始购买比例（basis points, 0-9990）
	MarginBnb            *big.Int // 保证金 BNB
	MarginTime           int64  // 保证金锁定时间（秒）
	VestingAllocations   []VestingAllocationInput // 归属分配列表
	Website              string // 官网
	Twitter              string // Twitter
	Telegram             string // Telegram
	Discord              string // Discord
	Whitepaper           string // 白皮书
	ContactEmail         string // 联系邮箱
	ContactTg            string // 联系 Telegram
	Tags                 []string // 标签
	Digits           string // 靓号目标后缀
	PredictedAddress string // 预先计算的地址（可选）
}

// VestingAllocationInput 归属分配输入
type VestingAllocationInput struct {
	Amount    int   // 分配数量（basis points, 0-10000）
	LaunchTime int64 // 归属起始时间（0 表示使用代币创建时间）
	Duration  int64 // 归属期限（秒）
	Mode      int   // 归属模式：0=BURN, 1=CLIFF, 2=LINEAR
}

// CreateTokenResponse 创建代币响应
type CreateTokenResponse struct {
	RequestID        string `json:"requestId"`        // 请求 ID（链上链下关联用）
	Create2Salt      string `json:"create2Salt"`      // CREATE2 salt 值
	CreateArg        string `json:"createArg"`        // ABI 编码的创建参数
	Nonce            int64  `json:"nonce"`             // CREATE2 nonce
	PredictedAddress string `json:"predictedAddress"` // 预测的合约地址
	Signature        string `json:"signature"`         // 后端签名
	Timestamp        int64  `json:"timestamp"`         // 签名时间戳
}

// CreateToken 创建代币的核心业务逻辑
// 执行流程：
//   1. 获取下一个 nonce（确保唯一性）
//   2. 准备创建参数（时间戳、创建者地址等）
//   3. 计算 CREATE2 预测地址（支持靓号搜索）
//   4. 生成请求 ID
//   5. 准备归属分配参数
//   6. 使用签名器对参数进行 ECDSA 签名
//   7. 保存创建请求到数据库
//   8. 返回创建结果
func (s *TokenService) CreateToken(ctx context.Context, req *CreateTokenRequest) (*CreateTokenResponse, error) {
	// 1. 获取下一个 nonce
	// nonce 是 CREATE2 地址计算的关键输入，必须保证唯一性
	nonce, err := s.getNextNonce(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get nonce: %w", err)
	}

	// 2. 准备参数
	timestamp := uint64(time.Now().Unix()) // 当前时间戳
	creator := common.HexToAddress(req.Creator) // 创建者地址

	// 3. 计算预测地址
	var salt [32]byte
	var predictedAddress common.Address

	if req.Digits != "" {
		// 如果指定了靓号后缀，尝试寻找满足条件的 nonce
		foundNonce, addr, found := s.create2Calc.FindVanityAddress(
			req.Name, req.Symbol,
			DefaultTotalSupply,
			s.coreContract, // owner 是 Core 合约
			timestamp,
			req.Digits,
			1000000, // 最大尝试次数
		)
		if found {
			nonce = int64(foundNonce) // 使用找到靓号的 nonce
			predictedAddress = addr
		}
		// 无论是否找到靓号，都重新计算 salt 和地址
		salt, predictedAddress = s.create2Calc.PredictAddress(
			req.Name, req.Symbol,
			DefaultTotalSupply,
			s.coreContract,
			timestamp, uint64(nonce),
		)
	} else {
		// 未指定靓号，直接使用当前 nonce 计算地址
		salt, predictedAddress = s.create2Calc.PredictAddress(
			req.Name, req.Symbol,
			DefaultTotalSupply,
			s.coreContract,
			timestamp, uint64(nonce),
		)
	}

	// 4. 生成请求 ID
	// 请求 ID 用于链上链下关联，确保创建请求的唯一性
	requestID := crypto.GenerateRequestID("mainnet_", creator, timestamp, uint64(nonce))

	// 5. 准备归属分配参数
	vestingAllocations := make([]crypto.VestingAllocation, len(req.VestingAllocations))
	for i, v := range req.VestingAllocations {
		launchTime := big.NewInt(v.LaunchTime)
		if v.LaunchTime == 0 {
			launchTime = big.NewInt(0) // 0 表示使用代币创建时间
		}

		vestingAllocations[i] = crypto.VestingAllocation{
			Amount:    big.NewInt(int64(v.Amount)),
			LaunchTime: launchTime,
			Duration:  big.NewInt(v.Duration),
			Mode:      uint8(v.Mode), // 0=BURN, 1=CLIFF, 2=LINEAR
		}
	}

	// 处理保证金默认值
	marginBnb := req.MarginBnb
	if marginBnb == nil {
		marginBnb = big.NewInt(0)
	}

	// 构建 CreateTokenParams 结构体（与合约接口完全对应）
	params := &crypto.CreateTokenParams{
		Name:                 req.Name,
		Symbol:               req.Symbol,
		TotalSupply:          DefaultTotalSupply,
		SaleAmount:           DefaultSaleAmount,
		VirtualBNBReserve:    DefaultVirtualBNBReserve,
		VirtualTokenReserve:  DefaultVirtualTokenReserve,
		LaunchTime:           uint64(req.LaunchTime),
		CreationFee:          big.NewInt(0),
		Creator:              creator,
		Timestamp:            timestamp,
		RequestID:            requestID,
		Nonce:                uint64(nonce),
		InitialBuyPercentage: uint64(req.InitialBuyPercentage),
		MarginBnb:            marginBnb,
		MarginTime:           uint64(req.MarginTime),
		VestingAllocations:   vestingAllocations,
	}

	// 6. 使用签名器对创建参数进行签名
	if s.signer == nil {
		return nil, fmt.Errorf("signer not initialized")
	}

	// 调试日志输出
	fmt.Printf("[CreateToken] Signer address: %s\n", s.signer.Address().Hex())
	fmt.Printf("[CreateToken] Creator: %s\n", creator.Hex())
	fmt.Printf("[CreateToken] Timestamp: %d\n", timestamp)
	fmt.Printf("[CreateToken] Nonce: %d\n", nonce)
	fmt.Printf("[CreateToken] RequestID: %s\n", crypto.Bytes32ToHex(requestID))
	fmt.Printf("[CreateToken] ChainID: %d\n", s.chainID)
	fmt.Printf("[CreateToken] CoreContract: %s\n", s.coreContract.Hex())

	// 执行签名（ABI 编码 + keccak256 哈希 + secp256k1 签名）
	encodedData, signature, err := s.signer.SignCreateTokenParams(params, s.chainID, s.coreContract)
	if err != nil {
		return nil, fmt.Errorf("failed to sign params: %w", err)
	}

	fmt.Printf("[CreateToken] EncodedData length: %d\n", len(encodedData))
	fmt.Printf("[CreateToken] Signature length: %d\n", len(signature))

	// 7. 保存创建请求到数据库
	err = s.saveCreationRequest(ctx, req, params, encodedData, signature, salt, predictedAddress)
	if err != nil {
		return nil, fmt.Errorf("failed to save creation request: %w", err)
	}

	// 8. 返回创建结果
	return &CreateTokenResponse{
		RequestID:        crypto.Bytes32ToHex(requestID),
		Create2Salt:      crypto.Bytes32ToHex(salt),
		CreateArg:        "0x" + hex.EncodeToString(encodedData),
		Nonce:            nonce,
		PredictedAddress: predictedAddress.Hex(),
		Signature:        "0x" + hex.EncodeToString(signature),
		Timestamp:        int64(timestamp),
	}, nil
}

// CalculateAddressRequest 计算地址请求
type CalculateAddressRequest struct {
	Name   string // 代币名称
	Symbol string // 代币符号
	Digits string // 靓号后缀
}

// CalculateAddressResponse 计算地址响应
type CalculateAddressResponse struct {
	PredictedAddress string `json:"predictedAddress"`
	Salt             string `json:"salt"`
	Nonce            int64  `json:"nonce"`
}

// CalculateAddress 计算代币预测地址
// 仅计算地址，不签名，用于前端预览
func (s *TokenService) CalculateAddress(ctx context.Context, req *CalculateAddressRequest) (*CalculateAddressResponse, error) {
	timestamp := uint64(time.Now().Unix())

	var nonce uint64 = 0
	var salt [32]byte
	var predictedAddress common.Address

	if req.Digits != "" {
		// 尝试寻找靓号
		foundNonce, addr, found := s.create2Calc.FindVanityAddress(
			req.Name, req.Symbol,
			DefaultTotalSupply,
			s.coreContract,
			timestamp,
			req.Digits,
			100000, // 最大尝试次数（比创建时少，因为只是预览）
		)
		if found {
			nonce = foundNonce
			predictedAddress = addr
			salt = s.create2Calc.CalculateSalt(
				req.Name, req.Symbol,
				DefaultTotalSupply,
				s.coreContract,
				timestamp, nonce,
			)
		} else {
			// 没找到靓号，使用默认 nonce=0
			salt, predictedAddress = s.create2Calc.PredictAddress(
				req.Name, req.Symbol,
				DefaultTotalSupply,
				s.coreContract,
				timestamp, 0,
			)
		}
	} else {
		// 未指定靓号，使用 nonce=0 计算
		salt, predictedAddress = s.create2Calc.PredictAddress(
			req.Name, req.Symbol,
			DefaultTotalSupply,
			s.coreContract,
			timestamp, 0,
		)
	}

	return &CalculateAddressResponse{
		PredictedAddress: predictedAddress.Hex(),
		Salt:             crypto.Bytes32ToHex(salt),
		Nonce:            int64(nonce),
	}, nil
}

// getNextNonce 获取下一个 nonce
// 使用数据库的 nonce_sequence 表实现原子递增
// 支持 UPSERT 模式：如果记录不存在则创建，存在则递增
func (s *TokenService) getNextNonce(ctx context.Context) (int64, error) {
	if s.tokenModel == nil {
		return 0, fmt.Errorf("token model is not initialized")
	}

	db := s.tokenModel.GetDB()
	if db == nil {
		return 0, fmt.Errorf("database connection is not available")
	}

	// 原子递增 nonce：UPDATE ... RETURNING
	var nonce int64
	err := db.QueryRow(ctx, `
		UPDATE nonce_sequence
		SET current_nonce = current_nonce + 1, updated_at = NOW()
		WHERE chain_id = $1
		RETURNING current_nonce
	`, s.chainID).Scan(&nonce)
	if err != nil {
		// 记录不存在，尝试创建初始记录
		_, _ = db.Exec(ctx, `
			INSERT INTO nonce_sequence (chain_id, current_nonce, created_at, updated_at)
			VALUES ($1, 1, NOW(), NOW())
			ON CONFLICT (chain_id) DO UPDATE SET current_nonce = nonce_sequence.current_nonce + 1, updated_at = NOW()
		`, s.chainID)
		// 再次查询获取 nonce
		err = db.QueryRow(ctx, `SELECT current_nonce FROM nonce_sequence WHERE chain_id = $1`, s.chainID).Scan(&nonce)
		if err != nil {
			return 0, err
		}
	}
	return nonce, nil
}

// saveCreationRequest 保存创建请求到数据库
// 将所有创建参数、签名和编码数据持久化，用于后续的链上事件关联和审计
func (s *TokenService) saveCreationRequest(
	ctx context.Context,
	req *CreateTokenRequest,
	params *crypto.CreateTokenParams,
	encodedData, signature []byte,
	salt [32]byte,
	predictedAddress common.Address,
) error {
	if s.tokenModel == nil {
		return fmt.Errorf("token model is not initialized")
	}

	db := s.tokenModel.GetDB()
	if db == nil {
		return fmt.Errorf("database connection is not available")
	}

	// 构建归属分配的 JSON 字符串
	vestingJSON := "[]"
	if len(req.VestingAllocations) > 0 {
		parts := make([]string, len(req.VestingAllocations))
		for i, v := range req.VestingAllocations {
			parts[i] = fmt.Sprintf(`{"amount":%d,"duration":%d}`, v.Amount, v.Duration)
		}
		vestingJSON = "[" + strings.Join(parts, ",") + "]"
	}

	// 插入 token_creation_requests 表
	_, err := db.Exec(ctx, `
		INSERT INTO token_creation_requests (
			request_id, creator_address, name, symbol, description, logo, banner,
			total_supply, sale_amount, virtual_bnb_reserve, virtual_token_reserve,
			launch_mode, launch_time, creation_fee, nonce, salt, predicted_address,
			signature, encoded_data, initial_buy_percentage, margin_bnb, margin_time,
			vesting_allocations, website, twitter, telegram, discord, whitepaper,
			contact_email, contact_tg, tags, status, timestamp, created_at, updated_at
		) VALUES (
			$1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16,
			$17, $18, $19, $20, $21, $22, $23::jsonb, $24, $25, $26, $27, $28, $29, $30, $31,
			0, $32, NOW(), NOW()
		)
	`,
		crypto.Bytes32ToHex(params.RequestID), // 请求 ID（hex）
		strings.ToLower(req.Creator),          // 创建者地址（小写）
		req.Name, req.Symbol, req.Description, req.Logo, req.Banner,
		params.TotalSupply.String(), params.SaleAmount.String(),
		params.VirtualBNBReserve.String(), params.VirtualTokenReserve.String(),
		req.LaunchMode, req.LaunchTime,
		params.CreationFee.String(),
		params.Nonce,                               // nonce
		crypto.Bytes32ToHex(salt),                  // salt（hex）
		strings.ToLower(predictedAddress.Hex()),    // 预测地址（小写）
		"0x"+hex.EncodeToString(signature),         // 签名（hex）
		"0x"+hex.EncodeToString(encodedData),       // 编码数据（hex）
		req.InitialBuyPercentage,
		params.MarginBnb.String(),
		req.MarginTime,
		vestingJSON,                                // 归属分配（JSON）
		req.Website, req.Twitter, req.Telegram, req.Discord, req.Whitepaper,
		req.ContactEmail, req.ContactTg,
		req.Tags,
		params.Timestamp,                           // 签名时间戳
	)
	return err
}
