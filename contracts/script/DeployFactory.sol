// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeployFactory
 * @notice 单独部署 MEMEFactory 合约
 * @dev 用于需要单独部署或更新 Factory 合约的场景
 *
 * 使用场景：
 * - Factory 合约需要重新部署（如更新 initHash）
 * - 需要部署新的 Factory 并迁移到新版本
 *
 * 注意事项：
 * - 部署后需要在 Core 中更新 Factory 地址
 * - 需要授予 Core 合约 DEPLOYER_ROLE 权限
 * - 需要调用 factory.setMetaNode(core) 设置 Core 地址
 *
 * 部署命令：
 * export MEME_CORE_ADDRESS=0x...  # Core 代理合约地址
 * forge script script/DeployFactory.sol:DeployFactory \
 *   --rpc-url $BSC_TEST_RPC \
 *   --broadcast \
 *   --verify \
 *   --etherscan-api-key $ETH_API_KEY \
 *   --legacy
 */

import "forge-std/Script.sol";
import "../src/MEMEFactory.sol";

contract DeployFactory is Script {
    /**
     * @notice 部署 Factory 合约并配置权限
     * @return newImplementation Factory 合约地址
     */
    function run() external returns (address newImplementation) {
        // 从环境变量读取配置
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        address core = vm.envAddress("MEME_CORE_ADDRESS");  // Core 代理合约地址

        console.log("=== Deploying MEMEFactory ===");
        console.log("Deployer:", deployer);
        console.log("Core Address:", core);
        console.log("Network ChainId:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 部署 Factory 合约
        MEMEFactory newFactory = new MEMEFactory(deployer);
        newImplementation = address(newFactory);

        // 授予 Core 合约 DEPLOYER_ROLE
        newFactory.grantRole(newFactory.DEPLOYER_ROLE(), core);
        
        // 设置 Core 地址
        newFactory.setMetaNode(core);

        console.log("MEMEFactory deployed at:", newImplementation);
        console.log("DEPLOYER_ROLE granted to Core");
        console.log("MetaNode set to Core");
        console.log("");

        vm.stopBroadcast();

        // 输出后续步骤
        console.log("=== Deployment Complete ===");
        console.log("Next Steps:");
        console.log("1. Update Core contract to use new Factory:");
        console.log("   core.setFactory(newFactoryAddress)");
        console.log("2. Update deploy config with new Factory address");
        
        return newImplementation;
    }
}
