// test_encoding.go - 编码对比测试工具
// 本文件提供了使用 Node.js/ethers.js 生成 ABI 编码数据的功能
// 主要用于调试：对比 Go (go-ethereum/abi) 和 JS (ethers.js) 的编码结果
// 确保与 Solidity 的 abi.encode 完全一致
package crypto

import (
	"encoding/hex" // 十六进制编解码
	"fmt"         // 格式化输出
	"os/exec"     // 执行外部命令
	"strings"     // 字符串处理

	"github.com/ethereum/go-ethereum/common" // 以太坊通用工具
)

// TestEncodingWithJS 使用 JS 脚本生成编码数据，用于对比
// 构建一个 Node.js 脚本，使用 ethers.js 的 defaultAbiCoder.encode 进行编码
// 然后通过 exec.Command 执行脚本并获取输出
// 参数：
//   - params: 创建代币参数
//   - chainID: 链 ID
//   - contractAddress: 合约地址
// 返回：编码后的字节数组、错误
func TestEncodingWithJS(params *CreateTokenParams, chainID int64, contractAddress common.Address) ([]byte, error) {
	// 构建 JS 脚本
	// 使用 ethers.js 的 defaultAbiCoder.encode 编码 CreateTokenParams tuple
	jsScript := fmt.Sprintf(`
const { ethers } = require("ethers");

const params = {
    name: "%s",
    symbol: "%s",
    totalSupply: "%s",
    saleAmount: "%s",
    virtualBNBReserve: "%s",
    virtualTokenReserve: "%s",
    launchTime: %d,
    creator: "%s",
    timestamp: %d,
    requestId: "%s",
    nonce: %d,
    initialBuyPercentage: %d,
    marginBnb: "%s",
    marginTime: %d,
    vestingAllocations: []
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
`, params.Name, params.Symbol,                                     // 代币名称和符号
		params.TotalSupply.String(), params.SaleAmount.String(),         // 总供应量和销售数量
		params.VirtualBNBReserve.String(), params.VirtualTokenReserve.String(), // 虚拟储备量
		params.LaunchTime, params.Creator.Hex(), params.Timestamp,       // 上线时间、创建者、时间戳
		hex.EncodeToString(params.RequestID[:]), params.Nonce,           // 请求 ID、nonce
		params.InitialBuyPercentage,                                      // 初始购买比例
		params.MarginBnb.String(), params.MarginTime)                    // 保证金

	// 执行 Node.js 脚本
	cmd := exec.Command("node", "-e", jsScript)
	output, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("failed to execute JS script: %w", err)
	}

	// 解析输出（去掉换行符）
	dataHex := strings.TrimSpace(string(output))
	// 确保有 0x 前缀
	if !strings.HasPrefix(dataHex, "0x") {
		dataHex = "0x" + dataHex
	}

	// 将十六进制字符串解码为字节数组
	data, err := hex.DecodeString(strings.TrimPrefix(dataHex, "0x"))
	if err != nil {
		return nil, fmt.Errorf("failed to decode hex: %w", err)
	}

	return data, nil
}

// CompareEncodings 对比 Go 和 JS 生成的编码数据
// 逐字节比较两种编码方式的结果，输出差异信息
// 参数：
//   - goEncoded: Go 生成的编码数据
//   - jsEncoded: JS 生成的编码数据
func CompareEncodings(goEncoded []byte, jsEncoded []byte) {
	fmt.Printf("=== 对比编码数据 ===\n")
	fmt.Printf("Go 编码长度: %d bytes\n", len(goEncoded)) // Go 编码数据长度
	fmt.Printf("JS 编码长度: %d bytes\n", len(jsEncoded)) // JS 编码数据长度

	// 长度不匹配
	if len(goEncoded) != len(jsEncoded) {
		fmt.Printf("长度不匹配！\n")
		return
	}

	// 逐字节比较（只检查前 200 字节）
	differences := 0
	for i := 0; i < len(goEncoded) && i < 200; i++ {
		if goEncoded[i] != jsEncoded[i] {
			fmt.Printf("差异位置 %d: Go=0x%02x, JS=0x%02x\n", i, goEncoded[i], jsEncoded[i])
			differences++
			if differences > 10 {
				fmt.Printf("... (还有更多差异)\n")
				break
			}
		}
	}

	// 无差异
	if differences == 0 {
		fmt.Printf("前 200 字节完全一致\n")
	}
}
