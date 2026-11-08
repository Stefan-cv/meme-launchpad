// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeployNewCoreImpl
 * @notice 部署新的 MEMECore 逻辑合约（用于 UUPS 升级）
 * @dev 此脚本只部署新的实现合约，不执行升级操作
 *
 * 使用场景：
 * - 修复 Bug 后需要升级核心合约
 * - 添加新功能需要升级
 * - 安全漏洞修复
 *
 * 升级流程：
 * 1. 运行此脚本部署新实现
 * 2. 在区块浏览器验证新实现合约
 * 3. 通过管理员多签调用 proxy.upgradeToAndCall()
 * 4. 测试升级后的功能
 *
 * 部署命令：
 * forge script script/DeployNewCoreImpl.s.sol:DeployNewCoreImpl \
 *   --rpc-url $BSC_TEST_RPC \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $ETH_API_KEY \
 *   --legacy
 */

import "forge-std/Script.sol";
import "../src/MEMECore.sol";

contract DeployNewCoreImpl is Script {
    /**
     * @notice 部署新的 Core 实现合约
     * @return newImplementation 新实现合约地址
     */
    function run() external returns (address newImplementation) {
        // 从环境变量读取部署者私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);

        // 打印部署信息
        console.log("=== Deploying New MEMECore Implementation ===");
        console.log("Deployer:", deployer);
        console.log("Network ChainId:", block.chainid);
        console.log("");

        // 部署新的 MEMECore 实现合约
        console.log("Deploying MEMECore implementation...");
        MetaNodeCore newCoreImpl = new MetaNodeCore();
        newImplementation = address(newCoreImpl);
        
        console.log("New MEMECore implementation deployed at:", newImplementation);
        console.log("");

        vm.stopBroadcast();

        // 输出升级指引
        console.log("=== Deployment Complete ===");
        console.log("New Implementation Address:", newImplementation);
        console.log("");
        console.log("Next Steps:");
        console.log("1. Verify the new implementation on block explorer");
        console.log("   forge verify-contract <address> MetaNodeCore --chain-id <chainId>");
        console.log("2. Use the admin/multisig to upgrade the proxy to this new implementation");
        console.log("   proxy.upgradeToAndCall(newImplementation, '')");
        console.log("3. Test the upgraded functionality on testnet first");
        
        return newImplementation;
    }
}
