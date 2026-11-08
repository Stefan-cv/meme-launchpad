package crypto

import (
	"crypto/ecdsa"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
)

/*
 * 本文件为 MEME Token Launchpad 的后端签名服务，负责与智能合约交互所需的消息签名。
 * 核心功能包括：
 *   1. 管理后端签名者的私钥与地址
 *   2. 对创建代币参数进行 ABI 编码与 EIP-191 风格签名
 *   3. 生成请求 ID（RequestID）用于链上链下关联
 *   4. 提供签名验证、辅助编码等工具函数
 *
 * 安全说明：
 * - 私钥由环境变量或配置中心注入，严禁硬编码
 * - 签名过程在服务端完成，前端仅接收最终签名结果
 * - 合约通过 SIGNER_ROLE 校验签名者身份，确保只有授权地址的签名有效
 *
 * 编码兼容性：
 * - 同时支持 Go (go-ethereum/abi) 与 Node.js (ethers.js) 两种编码方式
 * - 用于调试和验证与 Solidity abi.encode 的一致性
 */

// Signer 签名服务结构体
// 封装了后端签名者的私钥与派生地址，所有合约交互签名均由此实例完成
type Signer struct {
	privateKey *ecdsa.PrivateKey // ECDSA 私钥，用于生成签名
	address    common.Address    // 派生的以太坊地址，对应合约中的 SIGNER_ROLE 地址
}

// NewSigner 创建签名服务实例
// 参数：
//   - privateKeyHex: 十六进制格式的私钥字符串，支持带 0x 前缀或不带前缀
// 返回：
//   - *Signer: 签名服务实例
//   - error: 私钥解析失败时返回错误
// 执行流程：
//   1. 去除 0x 前缀
//   2. 使用 crypto.HexToECDSA 解析私钥
//   3. 从私钥派生公钥并计算以太坊地址
// 错误处理：
//   - 私钥格式非法时返回 fmt.Errorf("invalid private key: ...")
//   - 公钥类型断言失败时返回错误
func NewSigner(privateKeyHex string) (*Signer, error) {
	privateKeyHex = strings.TrimPrefix(privateKeyHex, "0x")
	privateKey, err := crypto.HexToECDSA(privateKeyHex)
	if err != nil {
		return nil, fmt.Errorf("invalid private key: %w", err)
	}

	publicKey := privateKey.Public()
	publicKeyECDSA, ok := publicKey.(*ecdsa.PublicKey)
	if !ok {
		return nil, fmt.Errorf("error casting public key to ECDSA")
	}

	address := crypto.PubkeyToAddress(*publicKeyECDSA)

	return &Signer{
		privateKey: privateKey,
		address:    address,
	}, nil
}

// Address 获取签名者地址
// 返回：签名者对应的以太坊地址（common.Address）
// 用途：用于在合约中配置 SIGNER_ROLE，以及日志记录
func (s *Signer) Address() common.Address {
	return s.address
}

// CreateTokenParams 创建代币参数结构体
// 与智能合约 IMEMECore.CreateTokenParams 结构完全对应
// 字段顺序必须与 Solidity 接口定义严格一致，否则 ABI 编码会出错
// 字段说明：
//   - Name: 代币名称（如 "Test Token"）
//   - Symbol: 代币符号（如 "TEST"）
//   - TotalSupply: 代币总供应量（wei 单位）
//   - SaleAmount: 用于销售的代币数量
//   - VirtualBNBReserve: 虚拟 BNB 储备量（用于定价曲线）
//   - VirtualTokenReserve: 虚拟代币储备量（用于定价曲线）
//   - LaunchTime: 上线时间（Unix 秒级时间戳）
//   - CreationFee: 创建费用（不在 ABI tuple 中，单独处理）
//   - Creator: 代币创建者地址
//   - Timestamp: 签名时间戳（Unix 秒级，用于防重放）
//   - RequestID: 请求唯一标识（32 字节，链上链下关联用）
//   - Nonce: 随机数，用于 CREATE2 地址预测
//   - InitialBuyPercentage: 初始购买比例（basis points，0-9990）
//   - MarginBnb: 保证金 BNB 数量
//   - MarginTime: 保证金锁定时间
//   - VestingAllocations: 代币归属分配计划（如团队锁仓、线性释放等）
type CreateTokenParams struct {
	Name                 string
	Symbol               string
	TotalSupply          *big.Int
	SaleAmount           *big.Int
	VirtualBNBReserve    *big.Int
	VirtualTokenReserve  *big.Int
	LaunchTime           uint64
	CreationFee          *big.Int
	Creator              common.Address
	Timestamp            uint64
	RequestID            [32]byte
	Nonce                uint64
	InitialBuyPercentage uint64
	MarginBnb            *big.Int
	MarginTime           uint64
	VestingAllocations   []VestingAllocation
}

// VestingAllocation 代币归属分配结构体
// 与合约 IVestingParams.VestingAllocation 结构一致
// 用于定义代币的锁仓与释放规则，支持多种模式：
//   - Mode=0 (BURN): 直接销毁
//   - Mode=1 (CLIFF): 悬崖模式，到期一次性释放
//   - Mode=2 (LINEAR): 线性释放，按时间均匀解锁
// 字段说明：
//   - Amount: 分配数量（basis points，0-10000，表示万分比）
//   - LaunchTime: 归属起始时间（Unix 时间戳，0 表示使用代币创建时间）
//   - Duration: 归属期限（秒）
//   - Mode: 归属模式（uint8）
type VestingAllocation struct {
	Amount     *big.Int // basis points (0-10000)
	LaunchTime *big.Int // 归属起始时间（Unix 时间戳，0 表示使用代币创建时间）
	Duration   *big.Int // 归属期限（秒）
	Mode       uint8    // 归属模式：0=BURN, 1=CLIFF, 2=LINEAR
}

// SignCreateTokenParams 对创建代币参数进行签名
// 参数：
//   - params: 创建代币参数结构体指针
//   - chainID: 区块链网络 ID（如 56=BSC 主网，97=BSC 测试网）
//   - contractAddress: MEMECore 合约地址
// 返回：
//   - encodedData: ABI 编码后的参数数据（bytes），可直接传入合约
//   - signature: 签名结果（65 字节，r||s||v，v=27/28 符合 OpenZeppelin 标准）
//   - error: 编码或签名过程中的错误
// 签名算法：
//   messageHash = keccak256(abi.encodePacked(encodedData, CHAIN_ID, address(this)))
//   signature = secp256k1_sign(messageHash, privateKey)
// 注意：
//   - 合约端使用 OpenZeppelin ECDSA.recover 验证签名，要求 v=27/28
//   - 本函数内部自动将 v 从 0/1 转换为 27/28
func (s *Signer) SignCreateTokenParams(params *CreateTokenParams, chainID int64, contractAddress common.Address) ([]byte, []byte, error) {
	// 使用 Go 编码（默认），如需 JS 编码可调用 signCreateTokenParamsWithJS 并设置 useJSEncoding=true
	return s.signCreateTokenParamsWithJS(params, chainID, contractAddress, false)
}

// CreateTokenParamsTuple 用于 ABI 编码的 tuple 结构体
// 字段标签 `abi:"..."` 定义了 ABI 编码时的字段名与顺序
// 注意：此结构体不包含 CreationFee，因为合约的 CreateTokenParams tuple 中也没有该字段
// 字段顺序必须与 Solidity 接口完全一致：
//   name, symbol, totalSupply, saleAmount, virtualBNBReserve, virtualTokenReserve,
//   launchTime, creator, timestamp, requestId, nonce, initialBuyPercentage,
//   marginBnb, marginTime, vestingAllocations
type CreateTokenParamsTuple struct {
	Name                 string         `abi:"name"`
	Symbol               string         `abi:"symbol"`
	TotalSupply          *big.Int       `abi:"totalSupply"`
	SaleAmount           *big.Int       `abi:"saleAmount"`
	VirtualBNBReserve    *big.Int       `abi:"virtualBNBReserve"`
	VirtualTokenReserve  *big.Int       `abi:"virtualTokenReserve"`
	LaunchTime           *big.Int       `abi:"launchTime"`
	Creator              common.Address `abi:"creator"`
	Timestamp            *big.Int       `abi:"timestamp"`
	RequestId            [32]byte       `abi:"requestId"`
	Nonce                *big.Int       `abi:"nonce"`
	InitialBuyPercentage *big.Int       `abi:"initialBuyPercentage"`
	MarginBnb            *big.Int       `abi:"marginBnb"`
	MarginTime           *big.Int       `abi:"marginTime"`
	VestingAllocations   []VestingTuple `abi:"vestingAllocations"`
}

// VestingTuple 用于 ABI 编码的 vesting tuple 结构体
// 与 VestingAllocation 对应，但字段类型全部适配 ABI 编码需求
type VestingTuple struct {
	Amount     *big.Int `abi:"amount"`
	LaunchTime *big.Int `abi:"launchTime"`
	Duration   *big.Int `abi:"duration"`
	Mode       uint8    `abi:"mode"`
}

// signCreateTokenParamsWithJS 支持使用 JS 脚本生成编码数据的签名方法
// 参数：
//   - params: 创建代币参数
//   - chainID: 链 ID
//   - contractAddress: 合约地址
//   - useJSEncoding: 是否使用 Node.js/ethers.js 进行 ABI 编码（用于调试对比）
// 返回：encodedData（ABI 编码数据）、signature（签名）、error
// 执行流程：
//   1. 定义 ABI tuple 类型（与 Solidity CreateTokenParams 结构对应）
//   2. 转换 vesting allocations 为 ABI 兼容的 VestingTuple 切片
//   3. 时间戳单位校验与转换（毫秒转秒）
//   4. 构建 CreateTokenParamsTuple 结构体
//   5. ABI 编码（Go 或 JS 方式）
//   6. 编码数据校验（外层偏移量、字段偏移量范围检查）
//   7. 构造 abi.encodePacked 数据：encodedData + chainID(uint256, 32字节) + contractAddress(20字节)
//   8. 计算 keccak256 消息哈希
//   9. 使用 secp256k1 签名
//   10. 调整 v 值为 27/28（OpenZeppelin 兼容）
//   11. 验证签名可恢复性
func (s *Signer) signCreateTokenParamsWithJS(params *CreateTokenParams, chainID int64, contractAddress common.Address, useJSEncoding bool) ([]byte, []byte, error) {
	// 定义 CreateTokenParams tuple 类型
	// 与 Solidity 的 abi.encode((CreateTokenParams)) 保持一致
	// CreateTokenParams struct: (string, string, uint256, uint256, uint256, uint256, uint256, uint256, address, uint256, bytes32, uint256, uint256, uint256, uint256, (uint256,uint256)[])

	tupleType, errType := abi.NewType("tuple", "", []abi.ArgumentMarshaling{
		{Name: "name", Type: "string"},
		{Name: "symbol", Type: "string"},
		{Name: "totalSupply", Type: "uint256"},
		{Name: "saleAmount", Type: "uint256"},
		{Name: "virtualBNBReserve", Type: "uint256"},
		{Name: "virtualTokenReserve", Type: "uint256"},
		{Name: "launchTime", Type: "uint256"},
		{Name: "creator", Type: "address"},
		{Name: "timestamp", Type: "uint256"},
		{Name: "requestId", Type: "bytes32"},
		{Name: "nonce", Type: "uint256"},
		{Name: "initialBuyPercentage", Type: "uint256"},
		{Name: "marginBnb", Type: "uint256"},
		{Name: "marginTime", Type: "uint256"},
		{Name: "vestingAllocations", Type: "tuple[]", Components: []abi.ArgumentMarshaling{
			{Name: "amount", Type: "uint256"},
			{Name: "launchTime", Type: "uint256"},
			{Name: "duration", Type: "uint256"},
			{Name: "mode", Type: "uint8"},
		}},
	})
	if errType != nil {
		return nil, nil, fmt.Errorf("failed to create tuple type: %w", errType)
	}

	// 转换 vesting allocations 为 VestingTuple 切片
	// 与合约 IVestingParams.VestingAllocation 结构一致
	// 注意：Mode 必须是 uint8，不能是自定义类型
	vestingData := make([]VestingTuple, len(params.VestingAllocations))
	for i, v := range params.VestingAllocations {
		amount := v.Amount
		launchTime := v.LaunchTime
		duration := v.Duration
		mode := v.Mode // 已经是 uint8 类型

		if amount == nil {
			amount = big.NewInt(0)
		}
		if launchTime == nil {
			launchTime = big.NewInt(0) // 0 表示使用代币创建时间
		}
		if duration == nil {
			duration = big.NewInt(0)
		}
		vestingData[i] = VestingTuple{
			Amount:     amount,
			LaunchTime: launchTime,
			Duration:   duration,
			Mode:       mode, // uint8 类型，直接使用
		}
	}

	// 构建 tuple 结构体（与 Solidity 接口定义完全一致，不包含 creationFee）
	// 字段顺序必须与 IMEMECore.CreateTokenParams 完全一致：
	// name, symbol, totalSupply, saleAmount, virtualBNBReserve, virtualTokenReserve,
	// launchTime, creator, timestamp, requestId, nonce, initialBuyPercentage,
	// marginBnb, marginTime, vestingAllocations
	marginBnb := params.MarginBnb
	if marginBnb == nil {
		marginBnb = big.NewInt(0)
	}

	// 验证时间戳单位：Solidity 使用秒级 Unix 时间戳
	// 如果 LaunchTime 或 Timestamp 看起来像毫秒（> 10^10），需要转换为秒
	launchTime := params.LaunchTime
	timestamp := params.Timestamp

	// 检查是否是毫秒级时间戳（通常 > 10^10，例如 1733459260000）
	// Unix 秒级时间戳在 2024 年大约是 1.7e9，毫秒级是 1.7e12
	if launchTime > 1e10 {
		fmt.Printf("[SignCreateTokenParams] WARNING: LaunchTime (%d) looks like milliseconds, converting to seconds\n", launchTime)
		launchTime = launchTime / 1000
	}
	if timestamp > 1e10 {
		fmt.Printf("[SignCreateTokenParams] WARNING: Timestamp (%d) looks like milliseconds, converting to seconds\n", timestamp)
		timestamp = timestamp / 1000
	}

	// 验证时间戳是否合理（应该在 2020-2100 年之间，即 1577836800 到 4102444800）
	if launchTime > 0 && (launchTime < 1577836800 || launchTime > 4102444800) {
		fmt.Printf("[SignCreateTokenParams] WARNING: LaunchTime (%d) seems out of reasonable range (2020-2100)\n", launchTime)
	}
	if timestamp < 1577836800 || timestamp > 4102444800 {
		fmt.Printf("[SignCreateTokenParams] WARNING: Timestamp (%d) seems out of reasonable range (2020-2100)\n", timestamp)
	}

	fmt.Printf("[SignCreateTokenParams] Time values: LaunchTime=%d (seconds, %s), Timestamp=%d (seconds, %s)\n",
		launchTime, time.Unix(int64(launchTime), 0).UTC().Format(time.RFC3339),
		timestamp, time.Unix(int64(timestamp), 0).UTC().Format(time.RFC3339))

	tupleData := CreateTokenParamsTuple{
		Name:                 params.Name,
		Symbol:               params.Symbol,
		TotalSupply:          params.TotalSupply,
		SaleAmount:           params.SaleAmount,
		VirtualBNBReserve:    params.VirtualBNBReserve,
		VirtualTokenReserve:  params.VirtualTokenReserve,
		LaunchTime:           new(big.Int).SetUint64(launchTime),
		Creator:              params.Creator,
		Timestamp:            new(big.Int).SetUint64(timestamp),
		RequestId:            params.RequestID,
		Nonce:                new(big.Int).SetUint64(params.Nonce),
		InitialBuyPercentage: new(big.Int).SetUint64(params.InitialBuyPercentage),
		MarginBnb:            marginBnb,
		MarginTime:           new(big.Int).SetUint64(params.MarginTime),
		VestingAllocations:   vestingData,
	}

	// ABI 编码为 tuple (与 Solidity abi.encode(CreateTokenParams) 一致)
	// 关键发现：go-ethereum 的 abi.Arguments{{Type: tupleType}}.Pack(tupleData) 对包含动态类型的 tuple
	// 会添加外层偏移量（32字节），这与 Solidity 的 abi.encode(struct) 格式一致
	//
	// 但是，根据测试用例（TestOnchain.s.sol:118），Solidity 使用：
	//   bytes memory data = abi.encode(params);
	// 这会产生：外层偏移量(32字节) + tuple数据
	//
	// 而合约解码（MEMECore.sol:386）使用：
	//   abi.decode(data, (IMetaNodeCore.CreateTokenParams))
	// 这期望的格式也是：外层偏移量(32字节) + struct数据
	//
	// 所以格式应该是一致的。但如果仍然失败，可能需要尝试不同的编码方式
	var encodedData []byte
	var encodeErr error

	if useJSEncoding {
		// 使用 JS 脚本生成编码数据，确保与 Solidity 的 abi.encode 完全一致
		encodedData, encodeErr = s.encodeWithJS(tupleData, chainID, contractAddress)
		if encodeErr != nil {
			return nil, nil, fmt.Errorf("failed to encode with JS: %w", encodeErr)
		}
		fmt.Printf("[SignCreateTokenParams] Using JS encoding (length: %d bytes)\n", len(encodedData))
	} else {
		// #region agent log
		logPath := "/Users/zhujie/workspace/metaNode/meme-launchpad/.cursor/debug.log"
		logEntry := fmt.Sprintf(`{"sessionId":"debug-session","runId":"run1","hypothesisId":"A","location":"signer.go:Pack","message":"Go encoding start","data":{"tupleDataName":%s,"tupleDataSymbol":%s,"totalSupply":%s},"timestamp":%d}`+"\n",
			jsonString(tupleData.Name), jsonString(tupleData.Symbol), tupleData.TotalSupply.String(), os.Getpid())
		if f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
			f.WriteString(logEntry)
			f.Close()
		}
		// #endregion

		// 使用 Go 的 abi.Arguments.Pack 方法
		// 注意：go-ethereum 的 Pack 方法对包含动态类型的 tuple 会添加外层偏移量（32字节）
		// 这与 Solidity 的 abi.encode(struct) 格式完全一致
		args := abi.Arguments{{Type: tupleType}}
		encodedData, encodeErr = args.Pack(tupleData)

		// #region agent log
		if encodeErr != nil {
			logEntry2 := fmt.Sprintf(`{"sessionId":"debug-session","runId":"run1","hypothesisId":"B","location":"signer.go:Pack","message":"Go encoding failed","data":{"error":%s},"timestamp":%d}`+"\n",
				jsonString(encodeErr.Error()), os.Getpid())
			if f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
				f.WriteString(logEntry2)
				f.Close()
			}
		} else {
			// 对比测试用例的 data
			testDataHex := "000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000033b2e3c9fd0803ce800000000000000000000000000000000000000000000000295be96e6406697200000000000000000000000000000000000000000000000000000008ac7230489e8000000000000000000000000000000000000000000000295be96e64066972000000000000000000000000000000000000000000000000000000000000000695caf260000000000000000000000005a7157d6fd2ad4a9edc4686758be77ae480bfe6a00000000000000000000000000000000000000000000000000000000695caf265fca43a01703870508a63d9122a30e8b1020cb3907f789bfca2b04cb7fd90bf100000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000260000000000000000000000000000000000000000000000000000000000000000c5465737420546f6b656e20310000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000554455354310000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
			encodedHex := hex.EncodeToString(encodedData)
			matches := encodedHex == testDataHex
			logEntry3 := fmt.Sprintf(`{"sessionId":"debug-session","runId":"run1","hypothesisId":"C","location":"signer.go:Pack","message":"Go encoding result","data":{"encodedLength":%d,"first32Bytes":%s,"matchesTestData":%t,"encodedHex":%s},"timestamp":%d}`+"\n",
				len(encodedData), hex.EncodeToString(encodedData[:min(32, len(encodedData))]), matches, jsonString(encodedHex), os.Getpid())
			if f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
				f.WriteString(logEntry3)
				f.Close()
			}
		}
		// #endregion

		if encodeErr != nil {
			return nil, nil, fmt.Errorf("failed to encode params: %w", encodeErr)
		}
	}

	// 验证编码：检查编码后的数据长度
	if len(encodedData) < 32 {
		return nil, nil, fmt.Errorf("encoded data too short: %d bytes", len(encodedData))
	}

	// 验证外层偏移量（应该指向 32 字节之后，即 tuple 数据的开始）
	// 这是 ABI 编码规范：对于包含动态类型的 tuple，前 32 字节是偏移量
	outerOffset := new(big.Int).SetBytes(encodedData[:32])
	fmt.Printf("[SignCreateTokenParams] Encoded data validation: length=%d bytes, outer offset: %d (0x%x)\n",
		len(encodedData), outerOffset.Uint64(), outerOffset.Uint64())

	if outerOffset.Uint64() != 32 {
		fmt.Printf("[SignCreateTokenParams] WARNING: Outer offset is %d, expected 32. This might indicate encoding issue.\n", outerOffset.Uint64())
		return nil, nil, fmt.Errorf("invalid outer offset: expected 32, got %d", outerOffset.Uint64())
	}

	fmt.Printf("[SignCreateTokenParams] Outer offset validation: OK (offset = 32)\n")

	// 验证 tuple 数据开始位置的字段（应该是 name 和 symbol 的偏移量）
	tupleDataStart := int(outerOffset.Uint64())
	if len(encodedData) < tupleDataStart+64 {
		return nil, nil, fmt.Errorf("encoded data too short for tuple fields")
	}

	nameOffsetInTuple := new(big.Int).SetBytes(encodedData[tupleDataStart : tupleDataStart+32])
	symbolOffsetInTuple := new(big.Int).SetBytes(encodedData[tupleDataStart+32 : tupleDataStart+64])
	fmt.Printf("[SignCreateTokenParams] name offset in tuple: %d (0x%x)\n", nameOffsetInTuple.Uint64(), nameOffsetInTuple.Uint64())
	fmt.Printf("[SignCreateTokenParams] symbol offset in tuple: %d (0x%x)\n", symbolOffsetInTuple.Uint64(), symbolOffsetInTuple.Uint64())

	// 验证编码格式是否与 Solidity 的 abi.encode 一致
	// name 和 symbol 的偏移量应该在合理范围内（通常 > 480，因为前面有静态字段）
	if nameOffsetInTuple.Uint64() < 480 || nameOffsetInTuple.Uint64() > 1000 {
		fmt.Printf("[SignCreateTokenParams] WARNING: name offset in tuple (%d) seems unusual\n", nameOffsetInTuple.Uint64())
	}
	if symbolOffsetInTuple.Uint64() < 544 || symbolOffsetInTuple.Uint64() > 1000 {
		fmt.Printf("[SignCreateTokenParams] WARNING: symbol offset in tuple (%d) seems unusual\n", symbolOffsetInTuple.Uint64())
	}

	fmt.Printf("[SignCreateTokenParams] Encoded data length: %d bytes\n", len(encodedData))
	encodedHex := hex.EncodeToString(encodedData)
	if len(encodedHex) > 200 {
		fmt.Printf("[SignCreateTokenParams] Encoded data (hex, first 200 chars): %s...\n", encodedHex[:200])
	} else {
		fmt.Printf("[SignCreateTokenParams] Encoded data (hex): %s\n", encodedHex)
	}

	// 验证 InitialBuyPercentage 是否超过限制
	if tupleData.InitialBuyPercentage.Cmp(big.NewInt(9990)) > 0 {
		fmt.Printf("[SignCreateTokenParams] WARNING: InitialBuyPercentage (%s) exceeds MAX_INITIAL_BUY_PERCENTAGE (9990)!\n", tupleData.InitialBuyPercentage.String())
	}

	// 计算消息哈希: keccak256(abi.encodePacked(data, CHAIN_ID, address(core)))
	// 完全按照 Solidity 合约的方式（MEMECore.sol:389）：
	//   bytes32 messageHash = keccak256(abi.encodePacked(data, CHAIN_ID, address(this)));
	//
	// abi.encodePacked 的行为：
	// - data (bytes): 直接拼接，不填充
	// - CHAIN_ID (uint256): 在 encodePacked 中，uint256 按 32 字节编码（左填充零）
	//   例如：uint256(97) 编码为 32 字节 (0x00...0x61)，而不是 1 字节
	// - address(core) (address): 20 字节，直接拼接
	//
	// 重要：abi.encodePacked 对 uint256 类型使用 32 字节编码，不是最小字节数！
	packedData := make([]byte, 0, len(encodedData)+32+20)
	packedData = append(packedData, encodedData...) // bytes 类型直接拼接

	// chainID 作为 uint256，在 encodePacked 中按 32 字节编码（左填充零）
	chainIDBytes := make([]byte, 32)
	chainIDBig := new(big.Int).SetInt64(chainID)
	chainIDBig.FillBytes(chainIDBytes) // 填充为 32 字节，左填充零
	packedData = append(packedData, chainIDBytes...)

	// contractAddress 作为 address (20 字节)
	packedData = append(packedData, contractAddress.Bytes()...)

	fmt.Printf("[SignCreateTokenParams] Packed data length: %d bytes (encodedData: %d + chainID: %d + address: 20)\n", len(packedData), len(encodedData), len(chainIDBytes))
	fmt.Printf("[SignCreateTokenParams] ChainID: %d (hex: %s, %d bytes)\n", chainID, hex.EncodeToString(chainIDBytes), len(chainIDBytes))
	fmt.Printf("[SignCreateTokenParams] Contract address: %s\n", contractAddress.Hex())

	// #region agent log
	logPath := "/Users/zhujie/workspace/metaNode/meme-launchpad/.cursor/debug.log"
	logEntry4 := fmt.Sprintf(`{"sessionId":"debug-session","runId":"run1","hypothesisId":"D","location":"signer.go:messageHash","message":"Packed data for hash","data":{"packedLength":%d,"encodedDataLength":%d,"chainID":%d,"chainIDBytes":%s,"contractAddress":%s},"timestamp":%d}`+"\n",
		len(packedData), len(encodedData), chainID, hex.EncodeToString(chainIDBytes), contractAddress.Hex(), os.Getpid())
	if f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
		f.WriteString(logEntry4)
		f.Close()
	}
	// #endregion

	// 计算消息哈希
	messageHash := crypto.Keccak256(packedData)

	// #region agent log
	logEntry5 := fmt.Sprintf(`{"sessionId":"debug-session","runId":"run1","hypothesisId":"E","location":"signer.go:messageHash","message":"Message hash calculated","data":{"messageHash":%s},"timestamp":%d}`+"\n",
		hex.EncodeToString(messageHash), os.Getpid())
	if f, err := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
		f.WriteString(logEntry5)
		f.Close()
	}
	// #endregion

	// 签名 (使用 secp256k1)
	// crypto.Sign 返回的签名格式: [r (32 bytes) | s (32 bytes) | v (1 byte)]
	// 其中 v 是 recovery ID (0 或 1)
	//
	// 注意：OpenZeppelin 的 ECDSA.recover 要求 v 值为 27 或 28（见文档第80行）
	// 虽然 ecrecover EVM 操作码支持 v=0/1，但 OpenZeppelin 的标准要求是 v=27/28
	// 因此我们需要将 v 值从 0/1 转换为 27/28
	signature, err := crypto.Sign(messageHash, s.privateKey)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to sign: %w", err)
	}

	// 创建调整后的签名（v=27/28），符合 OpenZeppelin 的要求
	ethereumSignature := make([]byte, 65)
	copy(ethereumSignature, signature)
	// 将 v 值从 0/1 转换为 27/28（OpenZeppelin 要求）
	if ethereumSignature[64] < 27 {
		ethereumSignature[64] += 27
	}

	// 验证签名可以恢复（使用调整后的 v 值）
	// 注意：验证时需要使用原始签名（v=0/1），因为 crypto.SigToPub 期望原始格式
	recoveredPubKey, err := crypto.SigToPub(messageHash, signature)
	if err != nil {
		// #region agent log
		logPath := "/Users/zhujie/workspace/metaNode/meme-launchpad/.cursor/debug.log"
		logEntry6 := fmt.Sprintf(`{"sessionId":"debug-session","runId":"run1","hypothesisId":"F","location":"signer.go:recover","message":"Signature recovery failed","data":{"error":%s},"timestamp":%d}`+"\n",
			jsonString(err.Error()), os.Getpid())
		if f, err2 := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err2 == nil {
			f.WriteString(logEntry6)
			f.Close()
		}
		// #endregion
		return nil, nil, fmt.Errorf("failed to recover public key from signature: %w", err)
	}
	recoveredAddress := crypto.PubkeyToAddress(*recoveredPubKey)
	if recoveredAddress != s.address {
		// #region agent log
		logPath := "/Users/zhujie/workspace/metaNode/meme-launchpad/.cursor/debug.log"
		logEntry7 := fmt.Sprintf(`{"sessionId":"debug-session","runId":"run1","hypothesisId":"G","location":"signer.go:recover","message":"Signature address mismatch","data":{"expected":%s,"got":%s},"timestamp":%d}`+"\n",
			s.address.Hex(), recoveredAddress.Hex(), os.Getpid())
		if f, err2 := os.OpenFile(logPath, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err2 == nil {
			f.WriteString(logEntry7)
			f.Close()
		}
		// #endregion
		return nil, nil, fmt.Errorf("signature recovery failed: expected %s, got %s", s.address.Hex(), recoveredAddress.Hex())
	}

	// #region agent log
	logPath8 := "/Users/zhujie/workspace/metaNode/meme-launchpad/.cursor/debug.log"
	logEntry8 := fmt.Sprintf(`{"sessionId":"debug-session","runId":"run1","hypothesisId":"H","location":"signer.go:recover","message":"Signature recovery success","data":{"signerAddress":%s,"recoveredAddress":%s,"vOriginal":%d,"vAdjusted":%d},"timestamp":%d}`+"\n",
		s.address.Hex(), recoveredAddress.Hex(), signature[64], ethereumSignature[64], os.Getpid())
	if f, err2 := os.OpenFile(logPath8, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err2 == nil {
		f.WriteString(logEntry8)
		f.Close()
	}
	// #endregion

	fmt.Printf("[SignCreateTokenParams] Message hash: %s\n", common.BytesToHash(messageHash).Hex())
	fmt.Printf("[SignCreateTokenParams] Signer address: %s\n", s.address.Hex())
	fmt.Printf("[SignCreateTokenParams] Recovered address: %s\n", recoveredAddress.Hex())
	fmt.Printf("[SignCreateTokenParams] Original v value: %d, Adjusted v value: %d (27/28 format for OpenZeppelin)\n", signature[64], ethereumSignature[64])
	fmt.Printf("[SignCreateTokenParams] Signature (hex): %s\n", hex.EncodeToString(ethereumSignature))
	fmt.Printf("[SignCreateTokenParams] Encoded data (hex, for contract): %s\n", hex.EncodeToString(encodedData))

	// 重要提示：验证签名者地址是否在合约中拥有 SIGNER_ROLE
	fmt.Printf("[SignCreateTokenParams] IMPORTANT: Ensure signer address %s has SIGNER_ROLE in contract %s\n", s.address.Hex(), contractAddress.Hex())
	fmt.Printf("[SignCreateTokenParams] IMPORTANT: Contract CHAIN_ID must match the chainID used for signing: %d\n", chainID)

	// 返回调整后的签名（v=27/28），符合 OpenZeppelin ECDSA.recover 的要求
	return encodedData, ethereumSignature, nil
}

// encodeWithJS 使用 JS 脚本生成编码数据，确保与 Solidity 的 abi.encode 完全一致
// 参数：
//   - tupleData: ABI tuple 数据
//   - chainID: 链 ID
//   - contractAddress: 合约地址
// 返回：编码后的字节数组、错误
// 实现原理：
//   1. 构建 Node.js 脚本，使用 ethers.js 的 defaultAbiCoder.encode 进行编码
//   2. 通过 exec.Command 调用 node 执行脚本
//   3. 解析标准输出中的 hex 字符串并解码为字节数组
// 用途：调试阶段用于对比 Go 编码与 JS 编码结果，确保一致性
func (s *Signer) encodeWithJS(tupleData CreateTokenParamsTuple, chainID int64, contractAddress common.Address) ([]byte, error) {
	// 构建 JS 脚本
	jsScript := fmt.Sprintf(`
const { ethers } = require("ethers");

const params = {
    name: %s,
    symbol: %s,
    totalSupply: "%s",
    saleAmount: "%s",
    virtualBNBReserve: "%s",
    virtualTokenReserve: "%s",
    launchTime: "%s",
    creator: "%s",
    timestamp: "%s",
    requestId: "%s",
    nonce: "%s",
    initialBuyPercentage: "%s",
    marginBnb: "%s",
    marginTime: "%s",
    vestingAllocations: %s
};

const types = [
    "string", "string", "uint256", "uint256", "uint256", "uint256",
    "uint256", "address", "uint256", "bytes32", "uint256",
    "uint256", "uint256", "uint256",
    "tuple(uint256,uint256,uint256,uint8)[]"
];

const values = [
    params.name,
    params.symbol,
    params.totalSupply,
    params.saleAmount,
    params.virtualBNBReserve,
    params.virtualTokenReserve,
    params.launchTime,
    params.creator,
    params.timestamp,
    params.requestId,
    params.nonce,
    params.initialBuyPercentage,
    params.marginBnb,
    params.marginTime,
    params.vestingAllocations
];

const data = ethers.utils.defaultAbiCoder.encode(
    ["tuple(" + types.join(",") + ")"],
    [values]
);

console.log(data);
`,
		jsonString(tupleData.Name), jsonString(tupleData.Symbol),
		tupleData.TotalSupply.String(), tupleData.SaleAmount.String(),
		tupleData.VirtualBNBReserve.String(), tupleData.VirtualTokenReserve.String(),
		tupleData.LaunchTime.String(), tupleData.Creator.Hex(),
		tupleData.Timestamp.String(), "0x"+hex.EncodeToString(tupleData.RequestId[:]),
		tupleData.Nonce.String(), tupleData.InitialBuyPercentage.String(),
		tupleData.MarginBnb.String(), tupleData.MarginTime.String(),
		encodeVestingAllocations(tupleData.VestingAllocations)) // vestingAllocations

	// 执行 JS 脚本
	cmd := exec.Command("node", "-e", jsScript)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to execute JS script: %w", err)
	}

	// 解析输出
	dataHex := strings.TrimSpace(string(output))
	if !strings.HasPrefix(dataHex, "0x") {
		dataHex = "0x" + dataHex
	}

	// 转换为字节数组
	data, err := hex.DecodeString(strings.TrimPrefix(dataHex, "0x"))
	if err != nil {
		return nil, fmt.Errorf("failed to decode hex: %w", err)
	}

	return data, nil
}

// jsonString 将字符串转换为 JSON 字符串（转义特殊字符）
// 用途：在构建 JS 脚本时安全地插入字符串变量，防止引号冲突
func jsonString(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

// encodeVestingAllocations 将 vesting allocations 编码为 JS 数组字符串
// 输出格式：[[amount,launchTime,duration,mode],[...],...]
// 用途：嵌入到 JS 脚本中作为 ethers.js 的编码输入
func encodeVestingAllocations(allocations []VestingTuple) string {
	if len(allocations) == 0 {
		return "[]"
	}
	var parts []string
	for _, alloc := range allocations {
		parts = append(parts, fmt.Sprintf("[%s,%s,%s,%d]",
			alloc.Amount.String(),
			alloc.LaunchTime.String(),
			alloc.Duration.String(),
			alloc.Mode))
	}
	return "[" + strings.Join(parts, ",") + "]"
}

// GenerateRequestID 生成请求 ID
// 与 ethers.js solidityKeccak256(["string", "address", "uint256", "uint256"], ["mainnet_", creator, timestamp, nonce]) 保持一致
// 参数：
//   - prefix: 前缀字符串（如 "mainnet_"、"testnet_"）
//   - creator: 代币创建者地址
//   - timestamp: 时间戳（Unix 秒级）
//   - nonce: 随机数
// 返回：32 字节的请求 ID（[32]byte）
// 编码规则（与 Solidity keccak256(abi.encodePacked(...)) 一致）：
//   - string: 按 UTF-8 编码，不填充
//   - address: 20 字节，不填充
//   - uint256: 32 字节，左填充零
func GenerateRequestID(prefix string, creator common.Address, timestamp, nonce uint64) [32]byte {
	// solidityKeccak256 对于不同类型有不同的编码方式：
	// - string: 按 UTF-8 编码（不填充）
	// - address: 20 字节（不填充）
	// - uint256: 32 字节（左填充零）

	data := []byte(prefix)                  // string 类型直接作为字节
	data = append(data, creator.Bytes()...) // address 是 20 字节

	// uint256 类型需要 32 字节（左填充零）
	timestampBytes := make([]byte, 32)
	new(big.Int).SetUint64(timestamp).FillBytes(timestampBytes)
	data = append(data, timestampBytes...)

	nonceBytes := make([]byte, 32)
	new(big.Int).SetUint64(nonce).FillBytes(nonceBytes)
	data = append(data, nonceBytes...)

	hash := crypto.Keccak256(data)
	var result [32]byte
	copy(result[:], hash)
	return result
}

// VerifySignature 验证签名
// 参数：
//   - data: 原始消息数据
//   - signature: 签名结果（65 字节，v 可为 27/28 或 0/1）
//   - expectedSigner: 期望的签名者地址
// 返回：签名是否有效（bool）
// 验证流程：
//   1. 检查签名长度必须为 65 字节
//   2. 将 v 值统一调整为 0/1（如原为 27/28 则减 27）
//   3. 计算消息哈希 keccak256(data)
//   4. 使用 crypto.SigToPub 恢复公钥
//   5. 比较恢复出的地址与 expectedSigner 是否一致（忽略大小写）
func VerifySignature(data []byte, signature []byte, expectedSigner common.Address) bool {
	if len(signature) != 65 {
		return false
	}

	// 调整 v 值
	sigCopy := make([]byte, 65)
	copy(sigCopy, signature)
	if sigCopy[64] >= 27 {
		sigCopy[64] -= 27
	}

	// 计算消息哈希
	messageHash := crypto.Keccak256(data)

	// 恢复公钥
	pubKey, err := crypto.SigToPub(messageHash, sigCopy)
	if err != nil {
		return false
	}

	// 获取地址
	recoveredAddress := crypto.PubkeyToAddress(*pubKey)

	return strings.EqualFold(recoveredAddress.Hex(), expectedSigner.Hex())
}

// HexToBytes32 将 hex 字符串转换为 [32]byte
// 参数：hexStr - 十六进制字符串，支持带 0x 前缀
// 返回：32 字节数组、错误
// 用途：将前端传入的 hex 格式 requestId 转换为合约所需的 bytes32 类型
func HexToBytes32(hexStr string) ([32]byte, error) {
	hexStr = strings.TrimPrefix(hexStr, "0x")
	bytes, err := hex.DecodeString(hexStr)
	if err != nil {
		return [32]byte{}, err
	}
	var result [32]byte
	copy(result[:], bytes)
	return result, nil
}

// Bytes32ToHex 将 [32]byte 转换为 hex 字符串
// 返回：带 0x 前缀的 64 字符十六进制字符串
func Bytes32ToHex(b [32]byte) string {
	return "0x" + hex.EncodeToString(b[:])
}

// mustNewType 创建 ABI 类型（panic on error）
// 用途：在包初始化时预定义 ABI 类型，简化编码调用
// 注意：仅在确保类型字符串合法时使用，否则会导致程序 panic
func mustNewType(t string) abi.Type {
	typ, err := abi.NewType(t, "", nil)
	if err != nil {
		panic(err)
	}
	return typ
}
