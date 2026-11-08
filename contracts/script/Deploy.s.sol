// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DeployScript
 * @notice MEME Launchpad 主部署脚本
 * @dev 部署和配置整个 MEME 发射平台的所有合约
 *
 * 部署顺序：
 * 1. MEMEVesting - 归属合约（依赖 Core 地址）
 * 2. MEMECore - 核心合约（依赖 Factory、Helper）
 * 3. MEMEHelper - 辅助合约（联合曲线计算、DEX 交互）
 * 4. MEMEFactory - 工厂合约（CREATE2 部署代币）
 *
 * 配置步骤：
 * - Factory.setMetaNode(core) - 授权 Core 调用工厂
 * - Helper.grantRole(CORE_ROLE, core) - 授权 Core 调用辅助合约
 * - Core.setVesting(vesting) - 设置归属合约地址
 *
 * 使用方法：
 * 1. 配置 deploy-config/{chain}/{env}.json 文件
 * 2. 设置环境变量 PRIVATE_KEY
 * 3. 运行部署命令（见下方注释）
 */

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MetaNodeCore} from "../src/MEMECore.sol";
import {MEMEFactory} from "../src/MEMEFactory.sol";
import {MEMEHelper} from "../src/MEMEHelper.sol";
import {MEMEVesting} from "../src/MEMEVesting.sol";
import {MetaNodeToken} from "../src/MEMEToken.sol";

import {Deployer} from "./Deployer.sol";
import {DeployConfig} from "./DeployConfig.s.sol";

contract DeployScript is Deployer {
    // ============ 配置和地址存储 ============
    DeployConfig public cfg;           // 部署配置
    address public MEMEHelperAddr;     // Helper 合约地址
    address public MEMEFactoryAddr;    // Factory 合约地址
    address public MEMECoreAddr;       // Core 代理合约地址

    /**
     * @notice 初始化部署环境
     * @dev 设置项目名称和环境，加载配置文件
     */
    function setUp() public override {
        // ===== 选择部署网络（取消注释对应行）=====
//        projectName = "bnb/";           // BSC 主网
        projectName = "bnb_test/";      // BSC 测试网
//        projectName = "xlayer/";        // XLayer 主网
//        projectName = "xlayer_test/";   // XLayer 测试网

        // ===== 选择部署环境 =====
        environment = "dev";            // 开发环境
//        environment = "test";           // 测试环境
//        environment = "pre";            // 预发布环境
//        environment = "prod";           // 生产环境
        
        super.setUp();

        // 加载配置文件
        string memory path = string.concat(
            vm.projectRoot(),
            "/deploy-config/",
            projectName,
            environment,
            ".json"
        );
        cfg = new DeployConfig(path);
    }

    // ==================== 部署命令示例 ====================
    // BSC 测试网部署：
    // forge script script/Deploy.s.sol:DeployScript --rpc-url $BSC_TEST_RPC --broadcast --verify --etherscan-api-key $ETH_API_KEY --verifier etherscan --legacy --slow
    
    // XLayer 测试网部署（无验证）：
    // forge script script/Deploy.s.sol:DeployScript --rpc-url $XLAYER_TEST_RPC --broadcast --legacy --slow
    
    // BSC 主网部署：
    // forge script script/Deploy.s.sol:DeployScript --rpc-url $BSC_MAIN_RPC --broadcast --verify --etherscan-api-key $ETH_API_KEY --verifier etherscan --legacy --slow
    
    // XLayer 主网部署：
    // forge script script/Deploy.s.sol:DeployScript --rpc-url $XLAYER_MAIN_RPC --broadcast --legacy --slow

    /**
     * @notice 主部署入口函数
     * @dev 执行完整的部署流程
     */
    function run() external {
        // 从环境变量读取部署者私钥
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // 读取配置
        address admin = cfg.Admin();
        address signer = cfg.Signer();
        address platformFeeReceiver = cfg.PlatformFeeReceiver();
        
        // 打印部署信息
        console.log("Deploying MEME Launchpad system...");
        console.log("Deployer:", deployer);
        console.log("Admin:", admin);
        console.log("Signer:", signer);
        console.log("Platform Fee Receiver:", platformFeeReceiver);
        console.log("-----------------------------------");
        
        vm.startBroadcast(deployerPrivateKey);

        // ===== 部署操作（取消注释需要执行的操作）=====
        // 注意：部署 Helper 前需要先更新 initHash！
        
//        deployMEMEVesting();      // 部署归属合约
//        deployMEMECore();         // 部署核心合约
//        deployMEMEHelper();       // 部署辅助合约
//        deployMEMEFactory();      // 部署工厂合约

        setAll();                   // 配置所有合约
        
//        upgradeMEMECore();        // 升级核心合约
//        upgradeMEMEVesting();     // 升级归属合约
        
        vm.stopBroadcast();
    }

    // ==================== 配置函数 ====================
    // 单独执行配置：
    // forge script script/Deploy.s.sol:DeployScript --sig "setAll()" --broadcast --rpc-url $BSC_TEST_RPC --verify --etherscan-api-key $ETH_API_KEY --verifier etherscan --legacy

    /**
     * @notice 配置所有合约
     * @dev 设置各合约间的权限和地址引用
     */
    function setAll() public {
        setMEMECore();
    }

    // ==================== 部署函数 ====================

    /**
     * @notice 部署 MEMEHelper 辅助合约
     * @dev 提供联合曲线计算和 DEX 交互功能
     * @return addr_ 部署的合约地址
     */
    function deployMEMEHelper() public returns (address addr_) {
        MEMEHelper helper;
        if (cfg.MEMEHelper() == address(0)) {
            // 新部署
            helper = new MEMEHelper(cfg.Admin(), cfg.Router(), cfg.WBNB());

            // 验证配置
            require(helper.PANCAKE_V2_ROUTER() == cfg.Router(), "Router set failed");
            require(helper.WBNB() == cfg.WBNB(), "WBNB set failed");
            console.log("MEMEHelper deployed at: %s", address(helper));
        } else {
            // 已部署，使用现有地址
            helper = MEMEHelper(payable(address(cfg.MEMEHelper())));
            console.log("MEMEHelper already deployed at %s", address(helper));
        }
        save("MEMEHelper", address(helper));
        addr_ = address(helper);
    }

    /**
     * @notice 部署 MEMEFactory 工厂合约
     * @dev 使用 CREATE2 部署代币，支持地址预测
     * @return addr_ 部署的合约地址
     */
    function deployMEMEFactory() public returns (address addr_) {
        MEMEFactory factory;
        if (cfg.MEMEFactory() == address(0)) {
            // 新部署
            factory = new MEMEFactory(cfg.Admin());
            console.log("MEMEFactory deployed at: %s", address(factory));
        } else {
            // 已部署，使用现有地址
            factory = MEMEFactory(cfg.MEMEFactory());
            console.log("MEMEFactory already deployed at %s", address(factory));
        }
        save("MEMEFactory", address(factory));
        addr_ = address(factory);
    }

    /**
     * @notice 部署 MEMECore 核心合约（使用 UUPS 代理）
     * @dev 核心业务逻辑：创建代币、买卖、毕业等
     * @return addr_ 代理合约地址
     */
    function deployMEMECore() public returns (address addr_) {
        MetaNodeCore coreImpl;
        if (cfg.MEMECore() == address(0)) {
            // 1. 部署实现合约
            coreImpl = new MetaNodeCore();
            save("MEMECoreImpl", address(coreImpl));
            console.log("MEMECoreImpl deployed at %s", address(coreImpl));
            
            // 2. 部署依赖合约
            address payable factory = payable(deployMEMEFactory());
            address payable helper = payable(deployMEMEHelper());
            
            // 3. 编码初始化数据
            bytes memory initData = abi.encodeWithSelector(
                MetaNodeCore.initialize.selector,
                factory,                        // 工厂合约地址
                helper,                         // 辅助合约地址
                cfg.Signer(),                   // 签名者地址
                cfg.PlatformFeeReceiver(),      // 平台费用接收地址
                cfg.MarginReceiver(),           // 保证金接收地址
                cfg.GraduateFeeReceiver(),      // 毕业费用接收地址
                cfg.Admin()                     // 管理员地址
            );
            
            // 4. 部署代理合约
            ERC1967Proxy proxy = new ERC1967Proxy(address(coreImpl), initData);
            console.log("MEMECoreProxy deployed at:", address(proxy));

            // 5. 验证初始化配置
            MetaNodeCore core = MetaNodeCore(payable(address(proxy)));
            require(address(core.factory()) == factory, "factory set failed");
            require(address(core.helper()) == helper, "helper set failed");
            require(address(core.platformFeeReceiver()) == cfg.PlatformFeeReceiver(), "platformFeeReceiver set failed");
            require(address(core.marginReceiver()) == cfg.MarginReceiver(), "marginReceiver set failed");
            require(address(core.graduateFeeReceiver()) == cfg.GraduateFeeReceiver(), "GraduateFeeReceiver set failed");

            // 6. 验证常量配置
            require(core.REQUEST_EXPIRY() == 3600, "REQUEST_EXPIRY set failed");
            require(core.graduationPlatformFeeRate() == 550, "PLATFORM_FEE_RATE set failed");
            require(core.graduationCreatorFeeRate() == 250, "CREATOR_FEE_RATE set failed");
            require(core.MIN_LIQUIDITY() == 10 ether, "MIN_LIQUIDITY set failed");
            require(core.MAX_INITIAL_BUY_PERCENTAGE() == 9990, "MAX_INITIAL_BUY_PERCENTAGE set failed");

            addr_ = address(proxy);
            console.log("MEMECoreProxy deployed at %s", addr_);
            save("MEMECore", addr_);
            
            // 7. 配置权限
            MEMEFactory(factory).setMetaNode(address(proxy));
            MEMEHelper(helper).grantRole(MEMEHelper(helper).CORE_ROLE(), address(proxy));
        } else {
            addr_ = cfg.MEMECore();
            console.log("MEMECoreProxy already deployed at %s", addr_);
        }
    }

    /**
     * @notice 部署 MEMEVesting 归属合约（使用 UUPS 代理）
     * @dev 管理代币锁仓释放：线性、悬崖、销毁模式
     * @return addr_ 代理合约地址
     */
    function deployMEMEVesting() public returns (address addr_) {
        MEMEVesting vestingImpl;
        if (cfg.MEMEVesting() == address(0)) {
            // 1. 部署实现合约
            vestingImpl = new MEMEVesting();
            save("MEMEVestingImpl", address(vestingImpl));
            console.log("MEMEVestingImpl deployed at %s", address(vestingImpl));

            // 2. 部署 Core（如果尚未部署）
            address coreProxyAddr = deployMEMECore();
            
            // 3. 编码初始化数据
            bytes memory vestingInitData = abi.encodeWithSelector(
                MEMEVesting.initialize.selector,
                cfg.Admin(),        // 管理员地址
                coreProxyAddr       // Core 代理地址（作为 operator）
            );
            
            // 4. 部署代理合约
            ERC1967Proxy vestingProxy = new ERC1967Proxy(address(vestingImpl), vestingInitData);

            addr_ = address(vestingProxy);
            console.log("MEMEVestingProxy deployed at %s", addr_);
            save("MEMEVesting", addr_);

            // 5. 配置 Core 引用 Vesting
            MetaNodeCore(payable(address(coreProxyAddr))).setVesting(addr_);
        } else {
            addr_ = cfg.MEMEVesting();
            console.log("MEMEVestingProxy already deployed at %s", addr_);
        }
    }

    // ==================== 升级函数 ====================

    /**
     * @notice 升级 MEMECore 核心合约
     * @dev 使用 UUPS 升级模式，部署新实现并升级代理
     */
    function upgradeMEMECore() public {
        address currentCoreProxy = cfg.MEMECore();
        require(currentCoreProxy != address(0), "Core proxy not deployed");

        // 部署新实现合约
        MetaNodeCore newImplementation = new MetaNodeCore();
        console.log("New MEMECoreImpl deployed at:", address(newImplementation));

        save("MEMECoreImpl", address(newImplementation));
        
        // 执行升级（无额外初始化数据）
        bytes memory initData = "";
        UUPSUpgradeable core = UUPSUpgradeable(payable(currentCoreProxy));
        core.upgradeToAndCall(address(newImplementation), initData);
        
        console.log("Proxy address:", currentCoreProxy);
    }

    /**
     * @notice 升级 MEMEVesting 归属合约
     * @dev 使用 UUPS 升级模式
     */
    function upgradeMEMEVesting() public {
        address currentVestingProxy = cfg.MEMEVesting();
        require(currentVestingProxy != address(0), "Vesting proxy not deployed");

        // 部署新实现合约
        MEMEVesting newImplementation = new MEMEVesting();
        console.log("New MEMEVestingImpl deployed at:", address(newImplementation));

        save("MEMEVestingImpl", address(newImplementation));
        
        // 执行升级
        bytes memory initData = "";
        UUPSUpgradeable vesting = UUPSUpgradeable(payable(currentVestingProxy));
        vesting.upgradeToAndCall(address(newImplementation), initData);

        console.log("Proxy address:", currentVestingProxy);
    }

    // ==================== 配置函数 ====================

    /**
     * @notice 配置 MEMECore 合约的所有参数和权限
     * @dev 检查并设置各项配置，授予必要的角色权限
     */
    function setMEMECore() public {
        MetaNodeCore core = MetaNodeCore(payable(address(cfg.MEMECore())));

        // ===== 配置地址 =====
        
        // 设置平台费用接收地址
        if (core.platformFeeReceiver() != cfg.PlatformFeeReceiver()) {
            core.setPlatformFeeReceiver(cfg.PlatformFeeReceiver());
            console.log("setPlatformFeeReceiver done");
        } else {
            console.log("platformFeeReceiver already set");
        }

        // 设置工厂合约地址
        if (address(core.factory()) != cfg.MEMEFactory()) {
            core.setFactory(cfg.MEMEFactory());
            console.log("setFactory done");
        } else {
            console.log("MEMEFactory already set");
        }

        // 设置辅助合约地址
        if (address(core.helper()) != cfg.MEMEHelper()) {
            core.setHelper(cfg.MEMEHelper());
            console.log("setHelper done");
        } else {
            console.log("MEMEHelper already set");
        }

        // 设置归属合约地址
        if (address(core.vesting()) != cfg.MEMEVesting()) {
            core.setVesting(cfg.MEMEVesting());
            console.log("setVesting done");
        } else {
            console.log("MEMEVesting already set");
        }

        // 设置保证金接收地址
        if (address(core.marginReceiver()) != cfg.MarginReceiver()) {
            core.setMarginReceiver(cfg.MarginReceiver());
            console.log("setMarginReceiver done");
        } else {
            console.log("MarginReceiver already set");
        }

        // ===== 配置权限 =====
        
        MEMEFactory factory = MEMEFactory(address(cfg.MEMEFactory()));
        MEMEHelper helper = MEMEHelper(payable(address(cfg.MEMEHelper())));

        // 授予签名者 SIGNER_ROLE
        if (!core.hasRole(core.SIGNER_ROLE(), cfg.Signer())) {
            core.grantRole(core.SIGNER_ROLE(), cfg.Signer());
            console.log("MEMECore grant SIGNER_ROLE to Signer done");
        }

        // 授予签名者 DEPLOYER_ROLE
        if (!core.hasRole(core.DEPLOYER_ROLE(), cfg.Signer())) {
            core.grantRole(core.DEPLOYER_ROLE(), cfg.Signer());
            console.log("MEMECore grant DEPLOYER_ROLE to Signer done");
        }

        // 授予 Core DEPLOYER_ROLE（在 Factory 中）
        if (!factory.hasRole(factory.DEPLOYER_ROLE(), cfg.MEMECore())) {
            factory.grantRole(factory.DEPLOYER_ROLE(), cfg.MEMECore());
            console.log("MEMEFactory grant DEPLOYER_ROLE to MEMECore done");
        }

        // 设置 Factory 的 MetaNode 地址
        if (address(factory.metaNode()) != address(cfg.MEMECore())) {
            factory.setMetaNode(cfg.MEMECore());
            console.log("MEMEFactory setMetaNode done");
        } else {
            console.log("MEMEFactory metaNode already set");
        }

        // 授予 Core CORE_ROLE（在 Helper 中）
        if (!helper.hasRole(helper.CORE_ROLE(), cfg.MEMECore())) {
            helper.grantRole(helper.CORE_ROLE(), cfg.MEMECore());
            console.log("MEMEHelper grant CORE_ROLE to MEMECore done");
        }

        // 设置最小锁仓时间
        if (core.minLockTime() != cfg.MinLockTime()) {
            core.setMinLockTime(cfg.MinLockTime());
            console.log("MEMECore setMinLockTime done");
        } else {
            console.log("MEMECore setMinLockTime already set");
        }
    }
}
