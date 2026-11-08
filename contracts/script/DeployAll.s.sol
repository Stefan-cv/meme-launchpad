// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeployAll
 * @notice 一键部署完整的 MEME Launchpad 系统
 * @dev 部署所有合约并配置权限
 */

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MetaNodeCore} from "../src/MEMECore.sol";
import {MEMEFactory} from "../src/MEMEFactory.sol";
import {MEMEHelper} from "../src/MEMEHelper.sol";
import {MEMEVesting} from "../src/MEMEVesting.sol";

contract DeployAll is Script {
    // BSC 测试网配置
    address constant PANCAKE_ROUTER = 0xD99D1c33F9fC3444f8101754aBC46c52416550D1;
    address constant WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==============================================");
        console.log("   MEME Launchpad BSC Testnet Deployment");
        console.log("==============================================");
        console.log("Deployer:", deployer);
        console.log("ChainId:", block.chainid);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署 Factory
        console.log("1. Deploying MEMEFactory...");
        MEMEFactory factory = new MEMEFactory(deployer);
        console.log("   MEMEFactory deployed at:", address(factory));

        // 2. 部署 Helper
        console.log("2. Deploying MEMEHelper...");
        MEMEHelper helper = new MEMEHelper(deployer, PANCAKE_ROUTER, WBNB);
        console.log("   MEMEHelper deployed at:", address(helper));

        // 3. 部署 Core 实现
        console.log("3. Deploying MetaNodeCore...");
        MetaNodeCore coreImpl = new MetaNodeCore();
        console.log("   MetaNodeCore impl deployed at:", address(coreImpl));

        // 4. 部署 Core 代理
        bytes memory initData = abi.encodeWithSelector(
            MetaNodeCore.initialize.selector,
            address(factory),    // factory
            address(helper),     // helper
            deployer,            // signer
            deployer,            // platformFeeReceiver
            deployer,            // marginReceiver
            deployer,            // graduateFeeReceiver
            deployer             // admin
        );
        ERC1967Proxy coreProxy = new ERC1967Proxy(address(coreImpl), initData);
        MetaNodeCore core = MetaNodeCore(payable(address(coreProxy)));
        console.log("   MetaNodeCore proxy deployed at:", address(core));

        // 5. 部署 Vesting 实现
        console.log("4. Deploying MEMEVesting...");
        MEMEVesting vestingImpl = new MEMEVesting();
        console.log("   MEMEVesting impl deployed at:", address(vestingImpl));

        // 6. 部署 Vesting 代理
        bytes memory vestingInitData = abi.encodeWithSelector(
            MEMEVesting.initialize.selector,
            deployer,           // admin
            address(core)       // operator (core)
        );
        ERC1967Proxy vestingProxy = new ERC1967Proxy(address(vestingImpl), vestingInitData);
        MEMEVesting vesting = MEMEVesting(address(vestingProxy));
        console.log("   MEMEVesting proxy deployed at:", address(vesting));

        // 7. 配置权限
        console.log("5. Configuring permissions...");
        
        // Factory 设置 MetaNode
        factory.setMetaNode(address(core));
        console.log("   Factory.setMetaNode done");

        // Factory 授予 Core DEPLOYER_ROLE
        factory.grantRole(factory.DEPLOYER_ROLE(), address(core));
        console.log("   Factory granted DEPLOYER_ROLE to Core");

        // Helper 授予 Core CORE_ROLE
        helper.grantRole(helper.CORE_ROLE(), address(core));
        console.log("   Helper granted CORE_ROLE to Core");

        // Core 设置 Vesting
        core.setVesting(address(vesting));
        console.log("   Core.setVesting done");

        // Core 授予 deployer SIGNER_ROLE
        core.grantRole(core.SIGNER_ROLE(), deployer);
        console.log("   Core granted SIGNER_ROLE to deployer");

        // Core 授予 deployer DEPLOYER_ROLE
        core.grantRole(core.DEPLOYER_ROLE(), deployer);
        console.log("   Core granted DEPLOYER_ROLE to deployer");

        vm.stopBroadcast();

        // 输出部署结果
        console.log("");
        console.log("==============================================");
        console.log("   Deployment Complete!");
        console.log("==============================================");
        console.log("MEMEFactory:    ", address(factory));
        console.log("MEMEHelper:     ", address(helper));
        console.log("MetaNodeCore:   ", address(core));
        console.log("MEMEVesting:    ", address(vesting));
        console.log("");
        console.log("Admin:          ", deployer);
        console.log("Signer:         ", deployer);
        console.log("");
    }
}

