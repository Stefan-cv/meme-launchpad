// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title TestCall
 * @notice MEME Launchpad 功能测试脚本
 * @dev 用于在测试网/主网上测试各种合约交互功能
 *
 * 功能列表：
 * - 创建代币（含归属计划）
 * - 买入/卖出代币
 * - PancakeSwap 流动性操作
 * - 查询代币和归属信息
 * - 配置更新和权限管理
 *
 * 使用方法：
 * 1. 设置 setUp() 中的 projectName 和 environment
 * 2. 在 run() 中取消注释要执行的操作
 * 3. 运行部署命令
 *
 * 部署命令示例：
 * BSC 测试网：
 * forge script script/TestCall.s.sol:TestCall --rpc-url $BSC_TEST_RPC --broadcast --verify --etherscan-api-key $ETH_API_KEY --verifier etherscan --legacy
 *
 * XLayer 测试网：
 * forge script script/TestCall.s.sol:TestCall --rpc-url $XLAYER_TEST_RPC --broadcast --legacy
 *
 * BSC 主网：
 * forge script script/TestCall.s.sol:TestCall --rpc-url $BSC_MAIN_RPC --broadcast --verify --etherscan-api-key $ETH_API_KEY --verifier etherscan --legacy
 */

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MetaNodeCore} from "../src/MEMECore.sol";
import {MEMEFactory} from "../src/MEMEFactory.sol";
import {MEMEHelper} from "../src/MEMEHelper.sol";
import {MetaNodeToken} from "../src/MEMEToken.sol";
import {MEMEVesting} from "../src/MEMEVesting.sol";
import {DeployConfig} from "./DeployConfig.s.sol";
import {Deployer} from "./Deployer.sol";
import {IMEMECore} from "../src/interfaces/IMEMECore.sol";
import {IPancakeFactory} from "../src/interfaces/IPancakeFactory.sol";
import {IPancakeRouter02} from "../src/interfaces/IPancakeRouter02.sol";
import {IVestingParams} from "../src/interfaces/IVestingParams.sol";
import {IMEMEVesting} from "../src/interfaces/IMEMEVesting.sol";
import {IPancakePair} from"../test/mocks/IPancakePair.sol";

contract TestCall is Deployer {
    // ============ 配置和合约实例 ============
    DeployConfig public cfg;              // 部署配置
    MetaNodeCore public core;             // 核心合约
    MEMEFactory public factory;           // 工厂合约
    MEMEHelper public helper;             // 辅助合约
    MEMEVesting public vesting;           // 归属合约
    
    // ============ 常量 ============
    uint256 public secondsInOneDay = 86400;  // 一天的秒数

    /**
     * @notice 初始化测试环境
     * @dev 设置网络和环境，加载配置
     */
    function setUp() public override {
        // ===== 选择测试网络（取消注释对应行）=====
//        projectName = "bnb/";           // BSC 主网
//        projectName = "bnb_test/";      // BSC 测试网
        projectName = "xlayer_test/";   // XLayer 测试网
//        projectName = "xlayer/";        // XLayer 主网
//        projectName = "base/";          // Base 主网
//        projectName = "base_sepolia/";  // Base Sepolia

        // ===== 选择环境 =====
        environment = "dev";            // 开发环境
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

    /**
     * @notice 主测试入口
     * @dev 取消注释要执行的测试操作
     */
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        console.log("TestCalling ", projectName, environment);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 初始化合约实例
        core = MetaNodeCore(payable(cfg.MEMECore()));
        factory = MEMEFactory(address(cfg.MEMEFactory()));
        helper = MEMEHelper(payable(address(cfg.MEMEHelper())));
        vesting = MEMEVesting(cfg.MEMEVesting());
        
        // ===== 配置操作 =====
//        pause();                        // 暂停合约
        setConfig();                    // 更新配置
        
        // ===== Core 合约操作 =====
//        core.setCreationFee(0);        // 设置创建费用
//        grantRole();                    // 授予角色权限
//        address tokenAddress = createToken();  // 创建代币
        
        // ===== 交易操作 =====
//        address tokenAddress = 0xa229d6d023eec571b6dde707df64f609af524a4d;
//        uint256 bnbAmount = 0.001 ether;
//        uint256 tokenAmount = 100000 ether;
//        buyTokens(tokenAddress, bnbAmount);                              // 联合曲线买入
//        addLiquidityToPancakeSwapV2(tokenAddress, tokenAmount, bnbAmount); // 添加流动性
//        buyTokenOnPancake(tokenAddress, bnbAmount);                       // DEX 买入
//        sellTokenOnPancake(tokenAddress, tokenAmount);                    // DEX 卖出
//        removeLiquidityFromPancake(0x7f0f99734568fe91BB1B53459caD73239B5Fd4f4); // 移除流动性

        // ===== 查询操作 =====
//        address tokenAddress = 0xa229d6D023EeC571B6DDe707DF64F609af524a4D;
//        getTokenPriceInfo(tokenAddress);   // 查询代币价格
//        getTradingPairInfo(tokenAddress);  // 查询交易对信息
//        getVestingInfo(tokenAddress);      // 查询归属信息
//        getTokenInfo(tokenAddress);        // 查询代币信息
//        getPairInfo(tokenAddress);         // 查询流动性池信息
//        getLPTokenBalance(tokenAddress);   // 查询 LP 代币余额
        
        vm.stopBroadcast();
    }

    // ==================== 配置函数 ====================

    /**
     * @notice 更新核心合约配置
     * @dev 检查并更新各项配置参数
     */
    function setConfig() public {
        // 设置平台费用接收地址
        if (address(core.platformFeeReceiver()) != address(cfg.PlatformFeeReceiver())) {
            core.setPlatformFeeReceiver(cfg.PlatformFeeReceiver());
            console.log("Core setPlatformFeeReceiver done");
        } else {
            console.log("Core setPlatformFeeReceiver AlreadySet");
        }

        // 设置保证金接收地址
        if (address(core.marginReceiver()) != address(cfg.MarginReceiver())) {
            core.setMarginReceiver(cfg.MarginReceiver());
            console.log("Core setMarginReceiver done");
        } else {
            console.log("Core setMarginReceiver AlreadySet");
        }

        // 设置毕业费用接收地址
        if (address(core.graduateFeeReceiver()) != address(cfg.GraduateFeeReceiver())) {
            core.setGraduateFeeReceiver(cfg.GraduateFeeReceiver());
            console.log("Core setGraduateFeeReceiver done");
        } else {
            console.log("Core setGraduateFeeReceiver AlreadySet");
        }

        // 设置最小锁仓时间
        if (core.minLockTime() != cfg.MinLockTime()) {
            core.setMinLockTime(cfg.MinLockTime());
            console.log("Core setMinLockTime done");
        } else {
            console.log("Core setMinLockTime AlreadySet");
        }
    }

    /**
     * @notice 授予必要的角色权限
     * @dev 为签名者和管理员授予各种角色
     */
    function grantRole() public {
        // 授予签名者 SIGNER_ROLE
        if (!core.hasRole(core.SIGNER_ROLE(), cfg.Signer())) {
            core.grantRole(core.SIGNER_ROLE(), cfg.Signer());
            console.log("Core grant SIGNER_ROLE to Signer done");
        }

        // 授予管理员 SIGNER_ROLE
        if (!core.hasRole(core.SIGNER_ROLE(), cfg.Admin())) {
            core.grantRole(core.SIGNER_ROLE(), cfg.Admin());
            console.log("Core grant SIGNER_ROLE to Admin done");
        }

        // 授予签名者 DEPLOYER_ROLE
        if (!core.hasRole(core.DEPLOYER_ROLE(), cfg.Signer())) {
            core.grantRole(core.DEPLOYER_ROLE(), cfg.Signer());
            console.log("Core grant DEPLOYER_ROLE to Signer done");
        }

        // 授予 Core DEPLOYER_ROLE（在 Factory 中）
        if (!factory.hasRole(factory.DEPLOYER_ROLE(), cfg.MEMECore())) {
            factory.grantRole(factory.DEPLOYER_ROLE(), cfg.MEMECore());
            console.log("Factory grant DEPLOYER_ROLE to Core done");
        }

        // 授予 Core CORE_ROLE（在 Helper 中）
        if (!helper.hasRole(helper.CORE_ROLE(), cfg.MEMECore())) {
            helper.grantRole(helper.CORE_ROLE(), cfg.MEMECore());
            console.log("Helper grant CORE_ROLE to Core done");
        }
    }

    // ==================== 查询函数 ====================

    /**
     * @notice 查询归属信息
     * @param tokenAddress 代币地址
     * @dev 显示指定受益人的所有归属计划详情
     */
    function getVestingInfo(address tokenAddress) public view {
        address beneficiary = 0xDB83330C3235489439d7EC4F238eAc31E7f614ED;  // 示例受益人地址
        
        // 获取总归属金额
        (uint256 vested, uint256 claimed, uint256 locked) = vesting.getTotalVestedAmount(tokenAddress, beneficiary);
        console.log("Total vested:", vested);
        console.log("Total claimed: ", claimed);
        console.log("Total locked: ", locked);
        console.log("");

        // 获取每个归属计划的详情
        uint256 count = vesting.getVestingScheduleCount(tokenAddress, beneficiary);
        if (count > 0) {
            IMEMEVesting.VestingSchedule memory vestingSchedule;
            for (uint256 i = 0; i < count; i++) {
                vestingSchedule = vesting.getVestingSchedule(tokenAddress, beneficiary, i);
                console.log("");
                console.log("Schedule Index:", i);
                console.log("  startTime:", vestingSchedule.startTime);
                console.log("  endTime:", vestingSchedule.endTime);
                console.log("  totalAmount:", vestingSchedule.totalAmount);
                console.log("  claimedAmount:", vestingSchedule.claimedAmount);
                console.log("  mode:", uint256(vestingSchedule.mode));
                
                uint256 claimableAmount = vesting.getClaimableAmount(tokenAddress, beneficiary, i);
                console.log("  claimableAmount:", claimableAmount);
            }
        }

        // 获取代币总锁仓量
        uint256 totalTokenLocked = vesting.totalTokenLocked(tokenAddress);
        console.log("");
        console.log("Total token locked:", totalTokenLocked);
    }

    /**
     * @notice 查询代币信息
     * @param tokenAddress 代币地址
     * @dev 显示代币基本信息和联合曲线状态
     */
    function getTokenInfo(address tokenAddress) public view {
        MetaNodeToken token = MetaNodeToken(tokenAddress);
        
        console.log("Token Info:");
        console.log("  name:", token.name());
        console.log("  symbol:", token.symbol());
        console.log("  totalSupply:", token.totalSupply());
        console.log("  metaNodeCore:", token.metaNodeCore());
        
        // 获取联合曲线参数
        IMEMECore.BondingCurveParams memory bondingCurve = core.getBondingCurve(tokenAddress);
        console.log("");
        console.log("Bonding Curve:");
        console.log("  availableTokens:", bondingCurve.availableTokens);
        console.log("  collectedBNB:", bondingCurve.collectedBNB);
        console.log("  k:", bondingCurve.k);
        console.log("  virtualTokenReserve:", bondingCurve.virtualTokenReserve);
        console.log("  virtualBNBReserve:", bondingCurve.virtualBNBReserve);
    }

    /**
     * @notice 暂停合约
     * @dev 预留的暂停功能
     */
    function pause() public {}

    // ==================== 操作函数 ====================

    /**
     * @notice 创建代币（含归属计划）
     * @return tokenAddress 创建的代币地址
     * @dev 演示创建带有多个归属计划的代币
     */
    function createToken() public returns (address tokenAddress){
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // 配置归属计划
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](3);
        
        // 归属计划1：销毁模式（3% 代币立即销毁）
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 300,                          // 3% (基点)
            launchTime: block.timestamp,          // 立即开始
            duration: secondsInOneDay,            // 持续1天（销毁模式会忽略）
            mode: IVestingParams.VestingMode.BURN
        });
        
        // 归属计划2：线性释放（2% 代币2天线性释放）
        vestingAllocations[1] = IVestingParams.VestingAllocation({
            amount: 200,                          // 2% (基点)
            launchTime: block.timestamp,          // 立即开始
            duration: secondsInOneDay * 2,        // 持续2天
            mode: IVestingParams.VestingMode.LINEAR
        });
        
        // 归属计划3：悬崖释放（4% 代币3天后一次性释放）
        vestingAllocations[2] = IVestingParams.VestingAllocation({
            amount: 400,                          // 4% (基点)
            launchTime: block.timestamp,          // 立即开始
            duration: secondsInOneDay * 3,        // 悬崖期3天
            mode: IVestingParams.VestingMode.CLIFF
        });

        // 构建创建参数
        IMEMECore.CreateTokenParams memory params;
        params.name = "SteveToken";               // 代币名称
        params.symbol = "Steve";                  // 代币符号
        params.totalSupply = 1000000000 ether;    // 总供应量 10亿
        params.saleAmount = 999000000 ether;      // 可售数量
        params.virtualBNBReserve = 8219178082191780000;  // 虚拟 BNB 储备
        params.virtualTokenReserve = 1073972602 ether;   // 虚拟代币储备
        params.launchTime = block.timestamp;      // 启动时间
        params.creator = deployer;                // 创建者地址
        params.timestamp = block.timestamp;       // 请求时间戳
        params.requestId = keccak256(abi.encodePacked("Test", block.timestamp, deployer));  // 请求ID
        params.nonce = 1;                         // nonce
        params.initialBuyPercentage = 900;        // 初始买入 9%
        params.marginBnb = 1 ether;               // 保证金 1 BNB
        params.marginTime = 0;                    // 保证金锁定时间
        params.vestingAllocations = vestingAllocations;  // 归属计划

        // 签名参数
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(data);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // 计算所需支付金额
        uint256 creationFee = core.creationFee();
        (uint256 initialBNB, uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = creationFee + initialBNB + params.marginBnb;
        
        console.log("Creation fee:", creationFee);
        console.log("Initial BNB:", initialBNB);
        console.log("Pre-buy fee:", preBuyFee);
        console.log("Margin:", params.marginBnb);
        console.log("Total payment:", totalPayment);
        
        // 创建代币
        tokenAddress = core.createToken{value: totalPayment}(data, signature);
        require(tokenAddress != address(0), "Create token failed");

        console.log("Token created at:", tokenAddress);
    }

    /**
     * @notice 在联合曲线上买入代币
     * @param tokenAddress 代币地址
     * @param bnbAmount 支付的 BNB 数量
     */
    function buyTokens(address tokenAddress, uint256 bnbAmount) public {
        // 预估可获得的代币数量
        uint256 estimatedTokens = core.calculateBuyAmount(tokenAddress, bnbAmount);
        console.log("Estimated tokens to receive:", estimatedTokens / 1e18, "tokens");

        // 设置滑点保护（5%）
        uint256 minTokenAmount = estimatedTokens * 95 / 100;
        uint256 deadline = block.timestamp + 300;

        // 执行买入
        core.buy{value: bnbAmount}(
            tokenAddress,
            minTokenAmount,
            deadline
        );
    }

    // ==================== PancakeSwap 操作函数 ====================

    /**
     * @notice 添加流动性到 PancakeSwap V2
     * @param tokenAddress 代币地址
     * @param tokenAmount 代币数量
     * @param bnbAmount BNB 数量
     */
    function addLiquidityToPancakeSwapV2(address tokenAddress, uint256 tokenAmount, uint256 bnbAmount) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address liquidityProvider = vm.addr(deployerPrivateKey);

        IPancakeRouter02 router = IPancakeRouter02(cfg.Router());
        IERC20 token = IERC20(tokenAddress);

        // 检查代币余额
        uint256 tokenBalance = token.balanceOf(liquidityProvider);
        require(tokenBalance >= tokenAmount, "Insufficient token balance");

        // 授权 Router 使用代币
        token.approve(address(router), tokenAmount);

        // 设置滑点保护（5%）
        uint256 minTokenAmount = tokenAmount * 95 / 100;
        uint256 minBNBAmount = bnbAmount * 95 / 100;
        uint256 deadline = block.timestamp + 300;

        // 添加流动性
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{value: bnbAmount}(
            tokenAddress,
            tokenAmount,
            minTokenAmount,
            minBNBAmount,
            deadline,
            false
        );

        console.log("Tokens added:", amountToken / 1e18);
        console.log("BNB added:", amountETH / 1e18);
        console.log("LP tokens received:", liquidity / 1e18);
    }

    /**
     * @notice 从 PancakeSwap 移除流动性
     * @param tokenAddress 代币地址
     */
    function removeLiquidityFromPancake(address tokenAddress) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address liquidityProvider = vm.addr(deployerPrivateKey);

        IPancakeRouter02 router = IPancakeRouter02(cfg.Router());
        address wbnb = router.WETH();
        
        // 获取交易对地址
        address pairAddress = IPancakeFactory(router.factory()).getPair(tokenAddress, wbnb);
        require(pairAddress != address(0), "Pair does not exist");
        
        // 检查 LP 代币余额
        IPancakePair pair = IPancakePair(pairAddress);
        uint256 lpBalance = pair.balanceOf(liquidityProvider);
        require(lpBalance > 0, "No LP tokens to remove");
        
        console.log("LP token balance:", lpBalance / 1e18);
        
        // 授权并移除流动性
        pair.approve(address(router), lpBalance);
        uint256 deadline = block.timestamp + 300;
        
        (uint256 amountToken, uint256 amountETH) = router.removeLiquidityETH(
            tokenAddress,
            lpBalance,
            0,  // minTokenAmount
            0,  // minBNBAmount
            liquidityProvider,
            deadline
        );
        
        console.log("Tokens received:", amountToken);
        console.log("BNB received:", amountETH);
    }

    /**
     * @notice 在 PancakeSwap 买入代币
     * @param tokenAddress 代币地址
     * @param bnbAmount 支付的 BNB 数量
     */
    function buyTokenOnPancake(address tokenAddress, uint256 bnbAmount) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address buyer = vm.addr(deployerPrivateKey);

        IPancakeRouter02 router = IPancakeRouter02(cfg.Router());
        address wbnb = router.WETH();

        // 构建交易路径
        address[] memory path = new address[](2);
        path[0] = wbnb;
        path[1] = tokenAddress;

        // 预估可获得的代币数量
        uint256[] memory amountsOut = router.getAmountsOut(bnbAmount, path);
        uint256 expectedTokenAmount = amountsOut[1];

        console.log("Expected tokens to receive:", expectedTokenAmount / 1e18, "tokens");

        // 设置滑点保护（1%）
        uint256 minTokenAmount = expectedTokenAmount * 99 / 100;
        uint256 deadline = block.timestamp + 300;

        // 执行买入
        router.swapExactETHForTokens{value: bnbAmount}(
            minTokenAmount,
            path,
            buyer,
            deadline
        );

        // 检查最终余额
        IERC20 token = IERC20(tokenAddress);
        uint256 finalBalance = token.balanceOf(buyer);
        console.log("Final token balance:", finalBalance / 1e18, "tokens");
    }

    /**
     * @notice 在 PancakeSwap 卖出代币
     * @param tokenAddress 代币地址
     * @param tokenAmount 卖出的代币数量
     */
    function sellTokenOnPancake(address tokenAddress, uint256 tokenAmount) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address seller = vm.addr(deployerPrivateKey);

        IPancakeRouter02 router = IPancakeRouter02(cfg.Router());
        address wbnb = router.WETH();

        IERC20 token = IERC20(tokenAddress);

        // 检查代币余额
        uint256 tokenBalance = token.balanceOf(seller);
        require(tokenBalance >= tokenAmount, "Insufficient token balance");

        // 授权 Router 使用代币
        token.approve(address(router), tokenAmount);

        // 构建交易路径
        address[] memory path = new address[](2);
        path[0] = tokenAddress;
        path[1] = wbnb;

        // 预估可获得的 BNB 数量
        uint256[] memory amountsOut = router.getAmountsOut(tokenAmount, path);
        uint256 expectedBNBAmount = amountsOut[1];

        console.log("Expected BNB to receive:", expectedBNBAmount / 1e18, "BNB");

        // 设置滑点保护（1%）
        uint256 minBNBAmount = expectedBNBAmount * 99 / 100;
        uint256 deadline = block.timestamp + 300;

        uint256 initialBNBBalance = seller.balance;

        // 执行卖出
        router.swapExactTokensForETH(
            tokenAmount,
            minBNBAmount,
            path,
            seller,
            deadline
        );

        // 计算实际收到的 BNB
        uint256 finalBNBBalance = seller.balance;
        uint256 bnbReceived = finalBNBBalance - initialBNBBalance;

        console.log("BNB received:", bnbReceived / 1e18, "BNB");
    }

    // ==================== 价格查询函数 ====================

    /**
     * @notice 查询代币价格信息
     * @param tokenAddress 代币地址
     */
    function getTokenPriceInfo(address tokenAddress) public view {
        IPancakeRouter02 router = IPancakeRouter02(cfg.Router());
        address wbnb = router.WETH();
        address factoryAddr = router.factory();
        address pairAddress = IPancakeFactory(factoryAddr).getPair(tokenAddress, wbnb);

        if (pairAddress == address(0)) {
            console.log("Trading pair does not exist");
            return;
        }

        IPancakePair pair = IPancakePair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        address token0 = pair.token0();

        uint256 tokenReserve;
        uint256 wbnbReserve;

        if (token0 == tokenAddress) {
            tokenReserve = reserve0;
            wbnbReserve = reserve1;
        } else {
            tokenReserve = reserve1;
            wbnbReserve = reserve0;
        }

        // 计算价格：1 代币 = ? BNB
        uint256 priceInBNB = (wbnbReserve * 1e18) / tokenReserve;

        console.log("Token address:", tokenAddress);
        console.log("Token reserve:", tokenReserve / 1e18);
        console.log("WBNB reserve:", wbnbReserve / 1e18);
        console.log("Price (1 Token):", priceInBNB, "wei BNB");
        console.log("Price (1 Token):", priceInBNB / 1e14, "e-4 BNB");
    }

    /**
     * @notice 查询交易对信息
     * @param tokenAddress 代币地址
     */
    function getTradingPairInfo(address tokenAddress) public view {
        IPancakeRouter02 router = IPancakeRouter02(cfg.Router());
        address wbnb = router.WETH();
        address factoryAddr = router.factory();
        address pairAddress = IPancakeFactory(factoryAddr).getPair(tokenAddress, wbnb);

        if (pairAddress == address(0)) {
            console.log("Trading pair does not exist");
            return;
        }

        IPancakePair pair = IPancakePair(pairAddress);

        console.log("Pair address:", pairAddress);
        console.log("Token0:", pair.token0());
        console.log("Token1:", pair.token1());
        console.log("Total supply:", pair.totalSupply() / 1e18);
    }

    /**
     * @notice 查询流动性池信息
     * @param tokenAddress 代币地址
     */
    function getPairInfo(address tokenAddress) public view {
        IPancakeRouter02 router = IPancakeRouter02(cfg.Router());
        address wbnb = router.WETH();
        address factoryAddr = router.factory();
        address pairAddress = IPancakeFactory(factoryAddr).getPair(tokenAddress, wbnb);

        if (pairAddress == address(0)) {
            console.log("Pair does not exist yet");
            return;
        }
        
        IPancakePair pair = IPancakePair(pairAddress);
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        
        console.log("Pair address:", pairAddress);
        console.log("Reserve0:", reserve0 / 1e18);
        console.log("Reserve1:", reserve1 / 1e18);
        console.log("Token0:", pair.token0());
        console.log("Token1:", pair.token1());
    }

    /**
     * @notice 查询 LP 代币余额
     * @param tokenAddress 代币地址
     */
    function getLPTokenBalance(address tokenAddress) public view {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(deployerPrivateKey);
        
        IPancakeRouter02 router = IPancakeRouter02(cfg.Router());
        address wbnb = router.WETH();
        address pairAddress = IPancakeFactory(router.factory()).getPair(tokenAddress, wbnb);
        
        if (pairAddress == address(0)) {
            console.log("No LP tokens - pair does not exist");
            return;
        }
        
        IPancakePair pair = IPancakePair(pairAddress);
        uint256 balance = pair.balanceOf(user);
        console.log("LP token balance:", balance / 1e18);
    }

    // ==================== 工具函数 ====================

    /**
     * @notice 计算平方根
     * @param x 输入值
     * @return y 平方根
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
