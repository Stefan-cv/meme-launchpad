// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FutureLaunchTest
 * @notice 未来启动功能测试合约
 * @dev 测试代币的延迟启动功能，确保在指定的启动时间之前无法进行交易（买入/卖出），
 *      而在启动时间之后可以正常交易。同时验证 launchTime = 0 时立即启动的兼容性。
 */
import "forge-std/Test.sol";
import "../src/MEMECore.sol";
import "../src/MEMEFactory.sol";
import "../src/MEMEHelper.sol";
import "../src/interfaces/IMEMECore.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockPancakeRouter} from "./mocks/MockPancakeRouter.sol";
import {MockWBNB} from "./mocks/MockWBNB.sol";

contract FutureLaunchTest is Test {
    // 核心合约实例
    MetaNodeCore public core;
    MEMEFactory public factory;
    MEMEHelper public helper;
    
    // 测试角色地址
    address public deployer = makeAddr("deployer");           // 部署者地址
    address public signer = makeAddr("signer");               // 签名者地址（用于签名创建代币的参数）
    address public creator = makeAddr("creator");             // 代币创建者地址
    address public buyer = makeAddr("buyer");                 // 买家地址
    address public platformFeeReceiver = makeAddr("platformFeeReceiver"); // 平台手续费接收地址
    
    // 签名者私钥（用于生成签名）
    uint256 public signerPrivateKey = 0x1234;
    
    /**
     * @notice 测试环境初始化函数
     * @dev 在每个测试用例运行前执行，部署所需的合约并设置权限
     */
    function setUp() public {
        vm.startPrank(deployer);
        
        // 部署模拟的 WBNB 和 PancakeRouter 合约
        MockWBNB wbnb = new MockWBNB();
        MockPancakeRouter router = new MockPancakeRouter(address(wbnb));
        
        // 部署工厂合约
        factory = new MEMEFactory(deployer);
        
        // 部署辅助合约
        helper = new MEMEHelper(deployer, address(router), address(wbnb));
        
        // 部署 Core 实现合约
        MetaNodeCore coreImpl = new MetaNodeCore();
        
        // 准备初始化数据
        bytes memory coreInitData = abi.encodeWithSelector(
            MetaNodeCore.initialize.selector,
            address(factory),           // 工厂地址
            address(helper),            // 辅助合约地址
            signer,                     // 签名者地址（稍后会更新）
            platformFeeReceiver,        // 平台手续费接收地址
            platformFeeReceiver,        // 其他费用接收地址
            platformFeeReceiver,        // 备用费用接收地址
            deployer                    // 管理员地址
        );
        
        // 使用 ERC1967 代理模式部署 Core 合约
        ERC1967Proxy coreProxy = new ERC1967Proxy(address(coreImpl), coreInitData);
        core = MetaNodeCore(payable(address(coreProxy)));

        // 在工厂中设置 Core 合约地址
        factory.setMetaNode(address(core));
        
        // 授予 Core 合约在 Helper 中的 CORE_ROLE 权限
        helper.grantRole(helper.CORE_ROLE(), address(core));
        
        vm.stopPrank();
        
        // 根据私钥计算签名者地址（确保地址与私钥匹配）
        signer = vm.addr(signerPrivateKey);
        
        // 授予签名者 SIGNER_ROLE 权限
        vm.startPrank(deployer);
        core.grantRole(core.SIGNER_ROLE(), signer);
        vm.stopPrank();
        
        // 为测试账户充值 ETH
        vm.deal(creator, 10 ether);
        vm.deal(buyer, 10 ether);
    }
    
    /**
     * @notice 测试未来启动功能防止早期交易
     * @dev 验证在启动时间之前无法进行买入操作，即使只差1秒也不行
     */
    function testFutureLaunchPreventsEarlyTrading() public {
        // 设置启动时间为当前时间后1小时
        uint256 futureTime = block.timestamp + 3600;
        
        // 准备创建代币的参数
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Future Token",
            symbol: "FUT",
            totalSupply: 1_000_000 * 10**18,      // 总供应量：100万代币
            saleAmount: 800_000 * 10**18,         // 销售数量：80万代币
            virtualBNBReserve: 1 ether,           // 虚拟 BNB 储备：1 ETH
            virtualTokenReserve: 800_000 * 10**18, // 虚拟代币储备：80万代币
            launchTime: futureTime,                // 启动时间：未来1小时
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("future-launch", block.timestamp)),
            nonce: block.timestamp,
            initialBuyPercentage: 0,              // 无初始买入
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IMetaNodeCore.VestingAllocation[](0) // 无锁仓分配
        });
        
        // 对参数进行签名
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // 创建代币
        vm.recordLogs();
        vm.prank(creator);
        core.createToken{value: core.creationFee()}(data, signature);
        
        // 从事件日志中提取代币地址
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address tokenAddress = address(0);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("TokenCreated(address,address,string,string,uint256,bytes32)")) {
                tokenAddress = address(uint160(uint256(logs[i].topics[1])));
                break;
            }
        }
        require(tokenAddress != address(0), "Token not created");
        
        // 验证代币信息
        IMetaNodeCore.TokenInfo memory info = core.getTokenInfo(tokenAddress);
        assertEq(uint8(info.status), uint8(IMetaNodeCore.TokenStatus.TRADING), "Status should be TRADING");
        assertEq(info.launchTime, futureTime, "Launch time should be set correctly");
        
        // 尝试在启动时间之前买入 - 应该失败
        vm.prank(buyer);
        vm.expectRevert(IMetaNodeCore.TokenNotLaunchedYet.selector);
        core.buy{value: 0.1 ether}(tokenAddress, 0, block.timestamp + 100);
        
        // 快进到启动时间前1秒
        vm.warp(futureTime - 1);
        
        // 应该仍然失败（即使只差1秒）
        vm.prank(buyer);
        vm.expectRevert(IMetaNodeCore.TokenNotLaunchedYet.selector);
        core.buy{value: 0.1 ether}(tokenAddress, 0, block.timestamp + 100);
    }
    
    /**
     * @notice 测试启动时间后交易功能启用
     * @dev 验证在达到启动时间后可以正常进行买入操作，并且可以多次买入
     */
    function testTradingEnabledAfterLaunchTime() public {
        // 设置启动时间为当前时间后1小时
        uint256 futureTime = block.timestamp + 3600;
        
        // 准备创建代币的参数
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Future Token",
            symbol: "FUT",
            totalSupply: 1_000_000 * 10**18,
            saleAmount: 800_000 * 10**18,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800_000 * 10**18,
            launchTime: futureTime,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("future-launch-2", block.timestamp)),
            nonce: block.timestamp + 1,
            initialBuyPercentage: 0,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IMetaNodeCore.VestingAllocation[](0)
        });
        
        // 对参数进行签名
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // 创建代币
        vm.recordLogs();
        vm.prank(creator);
        core.createToken{value: core.creationFee()}(data, signature);
        
        // 从事件日志中提取代币地址
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address tokenAddress = address(0);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("TokenCreated(address,address,string,string,uint256,bytes32)")) {
                tokenAddress = address(uint160(uint256(logs[i].topics[1])));
                break;
            }
        }
        require(tokenAddress != address(0), "Token not created");
        
        // 快进到启动时间（精确时间）
        vm.warp(futureTime);
        
        // 现在应该可以成功买入
        vm.prank(buyer);
        core.buy{value: 0.1 ether}(tokenAddress, 0, block.timestamp + 100);
        
        // 验证买家收到了代币
        uint256 buyerBalance = IERC20(tokenAddress).balanceOf(buyer);
        assertGt(buyerBalance, 0, "Buyer should have received tokens");
        
        // 快进更多时间并再次买入
        vm.warp(futureTime + 3600);
        vm.prank(buyer);
        core.buy{value: 0.2 ether}(tokenAddress, 0, block.timestamp + 3700);
        
        // 验证第二次买入后余额增加
        uint256 newBalance = IERC20(tokenAddress).balanceOf(buyer);
        assertGt(newBalance, buyerBalance, "Buyer should have more tokens after second buy");
    }
    
    /**
     * @notice 测试立即启动功能仍然有效
     * @dev 验证当 launchTime = 0 时，代币可以立即进行交易（向后兼容性测试）
     */
    function testImmediateLaunchStillWorks() public {
        // 创建立即启动的代币（launchTime = 0）
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Immediate Token",
            symbol: "IMM",
            totalSupply: 1_000_000 * 10**18,
            saleAmount: 800_000 * 10**18,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800_000 * 10**18,
            launchTime: 0, // 立即启动（0 表示立即启动）
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("immediate-launch", block.timestamp)),
            nonce: block.timestamp + 2,
            initialBuyPercentage: 0,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IMetaNodeCore.VestingAllocation[](0)
        });
        
        // 对参数进行签名
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // 创建代币
        vm.recordLogs();
        vm.prank(creator);
        core.createToken{value: core.creationFee()}(data, signature);
        
        // 从事件日志中提取代币地址
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address tokenAddress = address(0);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("TokenCreated(address,address,string,string,uint256,bytes32)")) {
                tokenAddress = address(uint160(uint256(logs[i].topics[1])));
                break;
            }
        }
        require(tokenAddress != address(0), "Token not created");
        
        // 应该能够立即买入（launchTime = 0 表示立即启动）
        vm.prank(buyer);
        core.buy{value: 0.1 ether}(tokenAddress, 0, block.timestamp + 100);
        
        // 验证买家立即收到了代币
        uint256 buyerBalance = IERC20(tokenAddress).balanceOf(buyer);
        assertGt(buyerBalance, 0, "Buyer should have received tokens immediately");
    }
    
    /**
     * @notice 测试卖出操作也遵守启动时间限制
     * @dev 验证即使通过初始买入获得了代币，在启动时间之前也无法卖出
     */
    function testSellAlsoRespectsLaunchTime() public {
        // 创建带有未来启动时间和初始买入的代币
        uint256 futureTime = block.timestamp + 3600;
        
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Future Token",
            symbol: "FUT",
            totalSupply: 1_000_000 * 10**18,
            saleAmount: 800_000 * 10**18,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800_000 * 10**18,
            launchTime: futureTime,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("future-sell", block.timestamp)),
            nonce: block.timestamp + 3,
            initialBuyPercentage: 1000, // 10% 初始买入（1000 = 10%，因为精度是 10000）
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IMetaNodeCore.VestingAllocation[](0)
        });
        
        // 对参数进行签名
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // 创建TOKEN并进行初始买入
        vm.recordLogs();
        vm.prank(creator);
        // 0.01 手续fee + ~0.11 ETH 用于 10% 初始买入
        core.createToken{value: 0.2 ether}(data, signature);
        
        // 从事件日志中提取Token地址（可能有两个不同的事件）
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address tokenAddress = address(0);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("TokenCreated(address,address,string,string,uint256,bytes32)") ||
                logs[i].topics[0] == keccak256("TokenCreatedWithInitialBuy(address,address,uint256,uint256,uint256)")) {
                tokenAddress = address(uint160(uint256(logs[i].topics[1])));
                break;
            }
        }
        require(tokenAddress != address(0), "Token not created");
        
        // 验证创建者通过初始买入获得了代币
        uint256 creatorBalance = IERC20(tokenAddress).balanceOf(creator);
        assertGt(creatorBalance, 0, "Creator should have tokens from initial buy");
        
        // 尝试在启动时间之前卖出 - 应该失败
        vm.prank(creator);
        IERC20(tokenAddress).approve(address(core), creatorBalance);
        
        vm.prank(creator);
        vm.expectRevert(IMetaNodeCore.TokenNotLaunchedYet.selector);
        core.sell(tokenAddress, creatorBalance / 2, 0, block.timestamp + 100);
        
        // 快进到启动时间之后
        vm.warp(futureTime);
        
        // 现在应该可以卖出
        vm.prank(creator);
        core.sell(tokenAddress, creatorBalance / 2, 0, block.timestamp + 360);
        
        // 验证卖出后余额减少
        uint256 newCreatorBalance = IERC20(tokenAddress).balanceOf(creator);
        assertLt(newCreatorBalance, creatorBalance, "Creator balance should decrease after sell");
    }
    
    /**
     * @notice 测试零启动时间的正常交易
     * @dev 验证 launchTime = 0 的代币可以正常交易（向后兼容性测试）
     */
    function testNormalTradingWithZeroLaunchTime() public {
        // 测试 launchTime = 0 的代币是否正常工作
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Test Token",
            symbol: "TEST",
            totalSupply: 1_000_000 * 10**18,
            saleAmount: 800_000 * 10**18,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800_000 * 10**18,
            launchTime: 0, // 零启动时间（立即启动）
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("compat-test", block.timestamp)),
            nonce: block.timestamp + 4,
            initialBuyPercentage: 0,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IMetaNodeCore.VestingAllocation[](0)
        });
        
        // 对参数进行签名
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // 创建代币
        vm.recordLogs();
        vm.prank(creator);
        core.createToken{value: core.creationFee()}(data, signature);
        
        // 从事件日志中提取代币地址
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address tokenAddress = address(0);
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("TokenCreated(address,address,string,string,uint256,bytes32)")) {
                tokenAddress = address(uint160(uint256(logs[i].topics[1])));
                break;
            }
        }
        require(tokenAddress != address(0), "Token not created");
        
        // 当 launchTime = 0 时，交易应该立即生效
        vm.prank(buyer);
        core.buy{value: 0.1 ether}(tokenAddress, 0, block.timestamp + 100);
        
        // 验证交易正常工作
        assertGt(IERC20(tokenAddress).balanceOf(buyer), 0, "Trading should work normally");
    }
}