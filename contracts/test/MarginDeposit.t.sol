// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MarginDepositTest
 * @notice 保证金存款功能测试
 * @dev 测试代币创建时的保证金机制
 *
 * 保证金业务说明：
 * - 创建者可以在创建代币时缴纳保证金（marginBnb）
 * - 保证金用于约束创建者行为，防止 rug pull
 * - 保证金会立即转给 marginReceiver 地址
 * - marginTime 记录保证金锁定时间（业务逻辑由后端控制）
 *
 * 测试覆盖场景：
 * 1. 带保证金创建代币 - 验证保证金正确转账
 * 2. 无保证金创建代币 - 验证无保证金时的行为
 * 3. 保证金 + 初始买入 - 同时使用两个功能
 * 4. 设置保证金接收者 - 验证管理员可以修改接收地址
 * 5. 权限控制 - 非管理员无法修改接收者
 * 6. 零地址校验 - 不允许设置零地址为接收者
 */
import "forge-std/Test.sol";
import "../src/MEMECore.sol";
import "../src/MEMEFactory.sol";
import "../src/MEMEHelper.sol";
import "../src/MEMEToken.sol";
import "../src/interfaces/IMEMECore.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockPancakeRouter} from "./mocks/MockPancakeRouter.sol";
import {MockWBNB} from "./mocks/MockWBNB.sol";

contract MarginDepositTest is Test {
    MetaNodeCore public coreImpl;
    MetaNodeCore public core;
    MEMEFactory public factory;
    MEMEHelper public helper;

    address public admin = address(0x1);
    address public signer;
    address public platformFeeReceiver = address(0x3);
    address public marginReceiver = address(0x4);
    address public creator = address(0x5);
    address public buyer = address(0x6);

    uint256 public signerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;

    function setUp() public {
        // Setup signer from private key
        signer = vm.addr(signerPrivateKey);
        MockWBNB wbnb = new MockWBNB();
        MockPancakeRouter router = new MockPancakeRouter(address(wbnb));
        // Deploy implementations
        factory = new MEMEFactory(admin);
        helper = new MEMEHelper(admin, address(router), address(wbnb));
        coreImpl = new MetaNodeCore();

        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            MetaNodeCore.initialize.selector,
            address(factory),
            address(helper),
            signer,
            platformFeeReceiver,
            platformFeeReceiver,
            platformFeeReceiver,
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(coreImpl), initData);
        core = MetaNodeCore(payable(address(proxy)));

        // Grant DEPLOYER_ROLE to core
        vm.startPrank(admin);
        factory.setMetaNode(address(core));

        // Grant CORE_ROLE to core  
        helper.grantRole(helper.CORE_ROLE(), address(core));
        vm.stopPrank();

        // Set margin receiver
        vm.prank(admin);
        core.setMarginReceiver(marginReceiver);

        // Fund accounts
        vm.deal(creator, 100 ether);
        vm.deal(buyer, 100 ether);
    }

    function testCreateTokenWithMargin() public {
        uint256 marginAmount = 1 ether;
        uint256 lockTime = 30 days;

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Margin Token",
            symbol: "MTKN",
            totalSupply: 1_000_000_000 * 10 ** 18,
            saleAmount: 800_000_000 * 10 ** 18,
            virtualBNBReserve: 8.22 ether,
            virtualTokenReserve: 1_000_000_000 * 10 ** 18,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test-request-with-margin"),
            nonce: 1,
            initialBuyPercentage: 0,
            marginBnb: marginAmount,
            marginTime: lockTime,
            vestingAllocations: new IMetaNodeCore.VestingAllocation[](0)
        });

        // Create signature
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Record margin receiver balance before
        uint256 marginReceiverBalanceBefore = marginReceiver.balance;

        // Create token with margin
        vm.prank(creator);
        core.createToken{value: core.creationFee() + marginAmount}(data, signature);

        // Verify margin was transferred
        assertEq(marginReceiver.balance - marginReceiverBalanceBefore, marginAmount, "Margin not transferred");
    }

    function testCreateTokenWithoutMargin() public {
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "No Margin Token",
            symbol: "NMTKN",
            totalSupply: 1_000_000_000 * 10 ** 18,
            saleAmount: 800_000_000 * 10 ** 18,
            virtualBNBReserve: 8.22 ether,
            virtualTokenReserve: 1_000_000_000 * 10 ** 18,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test-request-no-margin"),
            nonce: 2,
            initialBuyPercentage: 0,
            marginBnb: 0,  // No margin
            marginTime: 0,   // No lock time
            vestingAllocations: new IMetaNodeCore.VestingAllocation[](0)
        });

        // Create signature
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Record margin receiver balance before
        uint256 marginReceiverBalanceBefore = marginReceiver.balance;

        // Create token without margin
        vm.prank(creator);
        core.createToken{value: core.creationFee()}(data, signature);

        // Verify no margin was transferred
        assertEq(marginReceiver.balance, marginReceiverBalanceBefore, "Margin should not be transferred");
    }

    function testCreateTokenWithMarginAndInitialBuy() public {
        uint256 marginAmount = 0.5 ether;
        uint256 lockTime = 7 days;
        uint256 initialBuyPercent = 5000; // 50%

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Margin Initial Buy Token",
            symbol: "MIBT",
            totalSupply: 1_000_000_000 * 10 ** 18,
            saleAmount: 800_000_000 * 10 ** 18,
            virtualBNBReserve: 8.22 ether,
            virtualTokenReserve: 1_000_000_000 * 10 ** 18,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test-margin-initial-buy"),
            nonce: 3,
            initialBuyPercentage: initialBuyPercent,
            marginBnb: marginAmount,
            marginTime: lockTime,
            vestingAllocations: new IMetaNodeCore.VestingAllocation[](0)
        });

        // Create signature
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Calculate initial buy cost using bonding curve formula
        uint256 initialBuyTokens = (params.totalSupply * initialBuyPercent) / 10000;
        // Using x * y = k formula: cost = (tokenAmount * virtualBNBReserve) / (virtualTokenReserve - tokenAmount)
        uint256 initialBuyCost = (initialBuyTokens * params.virtualBNBReserve) / (params.virtualTokenReserve - initialBuyTokens);

        // Record balances before
        uint256 marginReceiverBalanceBefore = marginReceiver.balance;

        // Create token with margin and initial buy
        vm.prank(creator);
        uint256 preBuyFee = (initialBuyCost * core.preBuyFeeRate()) / 10000;
        uint256 totalPayment = core.creationFee() + initialBuyCost + preBuyFee + marginAmount;
        // Need to send enough for creation fee + initial buy + margin
        core.createToken{value: totalPayment}(data, signature);

        // Verify margin was transferred
        assertEq(marginReceiver.balance - marginReceiverBalanceBefore, marginAmount, "Margin not transferred correctly");
    }

    function testSetMarginReceiver() public {
        address newMarginReceiver = address(0x7);

        // Only admin can set margin receiver
        vm.prank(admin);
        core.setMarginReceiver(newMarginReceiver);

        assertEq(core.marginReceiver(), newMarginReceiver, "Margin receiver not updated");
    }

    function test_RevertWhen_SetMarginReceiverNonAdmin() public {
        address newMarginReceiver = address(0x7);

        // Non-admin should fail
        vm.prank(creator);
        vm.expectRevert();
        core.setMarginReceiver(newMarginReceiver);
    }

    function test_RevertWhen_SetMarginReceiverZeroAddress() public {
        // Admin trying to set zero address should fail
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        core.setMarginReceiver(address(0));
    }

    // Event definitions for testing
    event MarginDeposited(
        address indexed token,
        address indexed creator,
        uint256 marginAmount,
        uint256 lockTime
    );
}