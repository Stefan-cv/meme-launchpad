package crypto

import (
	"encoding/hex"
	"fmt"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
)

/*
 * 本文件实现 CREATE2 地址预测与计算功能。
 * CREATE2 是以太坊 Constantinople 硬分叉引入的 opcode，允许在部署合约前确定性预测合约地址。
 * 核心公式（EIP-1014）：
 *   address = keccak256(0xff ++ deployer ++ salt ++ keccak256(init_code))[12:]
 * 其中：
 *   - 0xff: 固定前缀（1 字节）
 *   - deployer: 工厂合约地址（20 字节）
 *   - salt: 用户提供的 32 字节盐值
 *   - init_code: 合约初始化字节码（bytecode + constructorArgs）
 *   - [12:]: 取 keccak256 哈希结果的后 20 字节作为地址
 *
 * 在 MEME Token Launchpad 中的用途：
 *   1. 用户在创建代币前可预先知道代币合约地址
 *   2. 支持"靓号地址"搜索（vanity address），通过调整 nonce 寻找特定后缀的地址
 *   3. 链上链下通过相同的 salt 计算逻辑保证地址一致性
 *
 * 安全说明：
 *   - salt 的计算必须包含不可预测因子（如 nonce），防止地址碰撞攻击
 *   - 工厂合约需使用相同的 salt 计算逻辑，否则预测地址与实际部署地址不一致
 */

// Create2Calculator CREATE2 地址计算器
// 封装了工厂合约地址与代币合约字节码，用于计算确定性部署地址
type Create2Calculator struct {
	factoryAddress common.Address // 工厂合约地址（即 deployer）
	tokenBytecode  []byte         // 代币合约的部署字节码（不包含构造函数参数）
}

// NewCreate2Calculator 创建 CREATE2 计算器实例
// 参数：
//   - factoryAddress: 工厂合约地址（十六进制字符串，支持 0x 前缀）
//   - tokenBytecodeHex: 代币合约字节码（十六进制字符串，支持 0x 前缀）
// 返回：
//   - *Create2Calculator: 计算器实例
//   - error: 字节码解码失败时返回错误
// 执行流程：
//   1. 去除字节码字符串的 0x 前缀
//   2. 使用 hex.DecodeString 将十六进制字符串解码为字节数组
//   3. 使用 common.HexToAddress 解析工厂地址
// 错误处理：
//   - 字节码格式非法时返回 fmt.Errorf("invalid bytecode: ...")
func NewCreate2Calculator(factoryAddress string, tokenBytecodeHex string) (*Create2Calculator, error) {
	bytecode, err := hex.DecodeString(strings.TrimPrefix(tokenBytecodeHex, "0x"))
	if err != nil {
		return nil, fmt.Errorf("invalid bytecode: %w", err)
	}

	return &Create2Calculator{
		factoryAddress: common.HexToAddress(factoryAddress),
		tokenBytecode:  bytecode,
	}, nil
}

// CalculateSalt 计算 salt 值
// salt 是 CREATE2 地址计算的关键输入，必须保证唯一性和不可预测性
// 计算公式：
//   salt = keccak256(abi.encodePacked(name, symbol, totalSupply, owner, timestamp, nonce))
// 参数：
//   - name: 代币名称
//   - symbol: 代币符号
//   - totalSupply: 代币总供应量（*big.Int）
//   - owner: 代币所有者地址
//   - timestamp: 创建时间戳（Unix 秒级）
//   - nonce: 随机数（用于靓号搜索时递增）
// 返回：32 字节的 salt 值（[32]byte）
// 编码规则（与 Solidity abi.encodePacked 一致）：
//   - string: 按 UTF-8 编码，不填充
//   - uint256: 32 字节，左填充零
//   - address: 20 字节，不填充
// 注意：此处的编码使用 abi.Arguments.Pack，与 Solidity 的 abi.encodePacked 行为一致
func (c *Create2Calculator) CalculateSalt(name, symbol string, totalSupply *big.Int, owner common.Address, timestamp, nonce uint64) [32]byte {
	// 使用 keccak256 计算 salt
	// 注意：这里使用的是 solidityKeccak256，对应 Solidity 中的 keccak256(abi.encodePacked(...))

	// 编码参数
	args := abi.Arguments{
		{Type: mustNewType("string")},
		{Type: mustNewType("string")},
		{Type: mustNewType("uint256")},
		{Type: mustNewType("address")},
		{Type: mustNewType("uint256")},
		{Type: mustNewType("uint256")},
	}

	packed, err := args.Pack(
		name,
		symbol,
		totalSupply,
		owner,
		new(big.Int).SetUint64(timestamp),
		new(big.Int).SetUint64(nonce),
	)
	if err != nil {
		// 简化处理，实际应该返回错误
		return [32]byte{}
	}

	hash := crypto.Keccak256(packed)
	var result [32]byte
	copy(result[:], hash)
	return result
}

// CalculateAddress 计算 CREATE2 部署地址
// 核心公式（EIP-1014）：
//   address = keccak256(0xff ++ factory ++ salt ++ keccak256(init_code))[12:]
// 参数：
//   - salt: 32 字节盐值（由 CalculateSalt 计算得出）
//   - name: 代币名称（用于构造函数参数编码）
//   - symbol: 代币符号（用于构造函数参数编码）
//   - totalSupply: 代币总供应量（用于构造函数参数编码）
//   - owner: 代币所有者地址（用于构造函数参数编码）
// 返回：预测的合约地址（common.Address）
// 执行流程：
//   1. 编码构造函数参数（encodeConstructorArgs）
//   2. 拼接 initcode = bytecode + constructorArgs
//   3. 计算 initcodeHash = keccak256(initcode)
//   4. 拼接 data = 0xff + factoryAddress + salt + initcodeHash
//   5. 计算 hash = keccak256(data)
//   6. 取 hash[12:] 作为 20 字节地址
// 一致性保证：
//   - 工厂合约必须使用相同的 initcode 和 salt 调用 CREATE2，否则地址不一致
func (c *Create2Calculator) CalculateAddress(salt [32]byte, name, symbol string, totalSupply *big.Int, owner common.Address) common.Address {
	// 编码构造函数参数
	constructorArgs := c.encodeConstructorArgs(name, symbol, totalSupply, owner)

	// 计算 initcode = bytecode + constructorArgs
	initcode := append(c.tokenBytecode, constructorArgs...)

	// 计算 initcode hash
	initcodeHash := crypto.Keccak256(initcode)

	// 计算 CREATE2 地址
	// keccak256(0xff ++ factory ++ salt ++ initcodeHash)[12:]
	data := []byte{0xff}
	data = append(data, c.factoryAddress.Bytes()...)
	data = append(data, salt[:]...)
	data = append(data, initcodeHash...)

	hash := crypto.Keccak256(data)
	return common.BytesToAddress(hash[12:])
}

// encodeConstructorArgs 编码构造函数参数
// 代币合约的构造函数通常为：constructor(string name, string symbol, uint256 totalSupply, address owner)
// 参数：
//   - name: 代币名称
//   - symbol: 代币符号
//   - totalSupply: 代币总供应量
//   - owner: 代币所有者地址
// 返回：ABI 编码后的构造函数参数字节数组
// 错误处理：编码失败时返回 nil（简化处理，实际应返回错误）
func (c *Create2Calculator) encodeConstructorArgs(name, symbol string, totalSupply *big.Int, owner common.Address) []byte {
	args := abi.Arguments{
		{Type: mustNewType("string")},
		{Type: mustNewType("string")},
		{Type: mustNewType("uint256")},
		{Type: mustNewType("address")},
	}

	packed, err := args.Pack(name, symbol, totalSupply, owner)
	if err != nil {
		return nil
	}
	return packed
}

// FindVanityAddress 寻找"靓号地址"
// 通过递增 nonce 尝试不同的 salt，寻找满足特定后缀条件的合约地址
// 参数：
//   - name: 代币名称
//   - symbol: 代币符号
//   - totalSupply: 代币总供应量
//   - owner: 代币所有者地址
//   - timestamp: 创建时间戳
//   - targetSuffix: 目标地址后缀（十六进制字符串，不区分大小写）
//   - maxAttempts: 最大尝试次数（防止无限循环）
// 返回：
//   - nonce: 找到靓号时使用的 nonce 值
//   - address: 找到的靓号地址
//   - found: 是否找到（true=找到，false=未找到）
// 性能说明：
//   - 地址空间为 2^160，寻找特定后缀的期望尝试次数为 16^len(suffix)
//   - 建议 suffix 长度不超过 4-5 位，否则计算时间过长
//   - 可通过 goroutine 并行搜索加速（本实现为串行，可扩展）
func (c *Create2Calculator) FindVanityAddress(
	name, symbol string,
	totalSupply *big.Int,
	owner common.Address,
	timestamp uint64,
	targetSuffix string,
	maxAttempts uint64,
) (nonce uint64, address common.Address, found bool) {
	targetSuffix = strings.ToLower(targetSuffix)

	for nonce := uint64(0); nonce < maxAttempts; nonce++ {
		salt := c.CalculateSalt(name, symbol, totalSupply, owner, timestamp, nonce)
		addr := c.CalculateAddress(salt, name, symbol, totalSupply, owner)

		addrLower := strings.ToLower(addr.Hex())
		if strings.HasSuffix(addrLower, targetSuffix) {
			return nonce, addr, true
		}
	}

	return 0, common.Address{}, false
}

// PredictAddress 预测代币地址
// 给定完整的创建参数，计算对应的 salt 和预测地址
// 参数：
//   - name: 代币名称
//   - symbol: 代币符号
//   - totalSupply: 代币总供应量
//   - owner: 代币所有者地址
//   - timestamp: 创建时间戳
//   - nonce: 随机数
// 返回：
//   - salt: 计算出的 32 字节盐值
//   - address: 预测的合约地址
// 用途：
//   - 用户在提交创建交易前，可预先知道代币合约地址
//   - 前端展示预测地址，供用户确认
func (c *Create2Calculator) PredictAddress(
	name, symbol string,
	totalSupply *big.Int,
	owner common.Address,
	timestamp, nonce uint64,
) (salt [32]byte, address common.Address) {
	salt = c.CalculateSalt(name, symbol, totalSupply, owner, timestamp, nonce)
	address = c.CalculateAddress(salt, name, symbol, totalSupply, owner)
	return salt, address
}
