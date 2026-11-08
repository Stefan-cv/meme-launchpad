// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TestPrediction
 * @notice 测试 Factory 合约的 CREATE2 地址预测功能
 * @dev 用于验证 predictTokenAddress 函数的正确性
 *
 * 使用场景：
 * - 验证地址预测算法是否正确
 * - 调试 CREATE2 部署问题
 * - 生成靓号地址时验证预测结果
 *
 * 运行命令：
 * forge script script/TestPrediction.s.sol:TestPrediction --rpc-url $BSC_TEST_RPC
 */

import "forge-std/Script.sol";
import "../src/MEMEFactory.sol";

contract TestPrediction is Script {
    /**
     * @notice 测试地址预测
     * @dev 对比预测地址与实际部署地址
     */
    function run() external {
        // 使用已部署的 Factory 合约地址（示例地址）
        MEMEFactory factory = MEMEFactory(0xe8DdCc54a64fAa53380F3e92BFB5cA98aED96b15);
        
        // 使用相同参数预测地址
        address predicted = factory.predictTokenAddress(
            "MyToken",                              // 代币名称
            "MTK",                                  // 代币符号
            1000000000000000000000000000,           // 总供应量
            0xb58A9e7720A3Be24082C91178193fbd76020c079, // Core 合约地址
            1750330890,                             // 时间戳
            7                                       // nonce
        );
        
        // 输出对比结果
        console.log("Factory predicted address:", predicted);
        console.log("Actual deployed address:  0x041F61CCD6a4D46a850424396Ba7a5C9B00d49E7");
        console.log("Match:", predicted == 0x041F61CCD6a4D46a850424396Ba7a5C9B00d49E7);
    }
}
