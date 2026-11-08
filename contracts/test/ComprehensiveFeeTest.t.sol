// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ComprehensiveFeeTest
 * @notice 费用机制综合测试
 * @dev 测试 MEME 发射器的各种费用收取和分配机制
 *
 * 费用类型：
 * - creationFee：代币创建费（固定金额，如 0.01 BNB）
 * - preBuyFee：预购手续费（初始买入金额的百分比）
 * - tradingFee：交易手续费（买入/卖出金额的百分比）
 *
 * 测试覆盖场景：
 * 1. 总费用计算 - 验证创建费 + 初始买入 + 预购手续费的计算
 * 2. 费用分配 - 验证平台正确收到各项费用
 * 3. 交易手续费 - 验证买入/卖出时的手续费收取
 * 4. 归属配置校验 - 验证超过100%的归属配置被拒绝
 * 5. 零费用场景 - 测试创建费为0时的行为
 * 6. 预购费率为0 - 测试无预购手续费时的行为
 * 7. 边界初始买入比例 - 测试0%、1%、最大比例等边界条件
 */
import "forge-std/Test.sol";
import "../src/MEMECore.sol";
import "../src/MEMEFactory.sol";
import "../src/MEMEHelper.sol";
import "../src/MEMEVesting.sol";
import "../src/MEMEToken.sol";
import "../src/interfaces/IVestingParams.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockPancakeRouter} from "./mocks/MockPancakeRouter.sol";
import {MockWBNB} from "./mocks/MockWBNB.sol";

contract ComprehensiveFeeTest is Test {
    MetaNodeCore public core;
    MEMEFactory public factory;
    MEMEHelper public helper;
    MEMEVesting public vestingImpl;
    MEMEVesting public vesting;

    address public admin = makeAddr("admin");
    uint256 public signerPrivateKey = 0x123456;
    address public signer;
    address public platformFeeReceiver = makeAddr("platform");
    address public creator = makeAddr("creator");
    uint256 public secondsInOneDay = 86400;

    function setUp() public {
        vm.startPrank(admin);
        MockWBNB wbnb = new MockWBNB();
        MockPancakeRouter router = new MockPancakeRouter(address(wbnb));

        factory = new MEMEFactory(admin);
        helper = new MEMEHelper(admin, address(router), address(wbnb));

        MetaNodeCore coreImpl = new MetaNodeCore();
        bytes memory coreInitData = abi.encodeWithSelector(
            MetaNodeCore.initialize.selector,
            address(factory),
            address(helper),
            signer,
            platformFeeReceiver,
            platformFeeReceiver,
            platformFeeReceiver,
            admin
        );
        ERC1967Proxy coreProxy = new ERC1967Proxy(address(coreImpl), coreInitData);
        core = MetaNodeCore(payable(address(coreProxy)));

        factory.setMetaNode(address(core));
        helper.grantRole(helper.CORE_ROLE(), address(core));


        signer = vm.addr(signerPrivateKey);
        core.grantRole(core.SIGNER_ROLE(), signer);

        vestingImpl = new MEMEVesting();
        bytes memory vestingInitData = abi.encodeWithSelector(
            MEMEVesting.initialize.selector,
            admin,
            address(core)  // Core proxy as operator
        );
        ERC1967Proxy vestProxy = new ERC1967Proxy(address(vestingImpl), vestingInitData);
        vesting = MEMEVesting(address(vestProxy));

        core.setVesting(address(vesting));

        vm.stopPrank();

        vm.deal(creator, 10000 ether);
    }

    function testTotalFeeCalculationWithInitialBuy() public {
        uint256 initialBuyPercentage = 5000; // 50%

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Fee Test Token",
            symbol: "FEE",
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("fee-test"),
            nonce: 1,
            initialBuyPercentage: initialBuyPercentage,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        // Calculate expected amounts
        (uint256 expectedTokens, uint256 expectedBNB) = calculateExpectedInitialBuy(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            initialBuyPercentage
        );

        uint256 preBuyFee = (expectedBNB * core.preBuyFeeRate()) / 10000;
        uint256 creationFee = core.creationFee();
        uint256 totalExpectedPayment = creationFee + expectedBNB + preBuyFee;

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 creatorBalanceBefore = creator.balance;

        vm.prank(creator);
        core.createToken{value: totalExpectedPayment + 1 ether}(data, signature); // Extra for refund test

        uint256 creatorBalanceAfter = creator.balance;
        uint256 actualPayment = creatorBalanceBefore - creatorBalanceAfter;

        // Should pay exactly the expected amount (refund excess)
        assertEq(actualPayment, totalExpectedPayment, "Incorrect total payment");
    }

    function testFeeDistribution() public {
        uint256 initialBuyPercentage = 1000; // 10%

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Fee Dist Token",
            symbol: "FDIST",
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("fee-dist-test"),
            nonce: 2,
            initialBuyPercentage: initialBuyPercentage,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        (uint256 expectedTokens, uint256 expectedBNB) = calculateExpectedInitialBuy(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            initialBuyPercentage
        );

        uint256 preBuyFee = (expectedBNB * core.preBuyFeeRate()) / 10000;
        uint256 creationFee = core.creationFee();

        uint256 platformBalanceBefore = platformFeeReceiver.balance;

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(creator);
        core.createToken{value: creationFee + expectedBNB + preBuyFee}(data, signature);

        uint256 platformBalanceAfter = platformFeeReceiver.balance;
        uint256 platformReceived = platformBalanceAfter - platformBalanceBefore;

        // Platform should receive creationFee + preBuyFee
        assertEq(platformReceived, creationFee + preBuyFee, "Incorrect fee distribution to platform");
    }

    function testBuySellWithTradingFees() public {
        // Create token without initial buy
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Trading Fee Token",
            symbol: "TFEE",
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("trading-fee-test"),
            nonce: 3,
            initialBuyPercentage: 0,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(creator);
        core.createToken{value: core.creationFee()}(data, signature);

        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        address buyer = makeAddr("buyer");
        vm.deal(buyer, 10 ether);

        uint256 buyAmount = 1 ether;
        uint256 platformBalanceBefore = platformFeeReceiver.balance;

        vm.prank(buyer);
        core.buy{value: buyAmount}(tokenAddress, 0, block.timestamp + 3600);

        uint256 platformBalanceAfter = platformFeeReceiver.balance;
        uint256 tradingFeeReceived = platformBalanceAfter - platformBalanceBefore;
        uint256 expectedTradingFee = (buyAmount * core.tradingFeeRate()) / 10000;

        assertEq(tradingFeeReceived, expectedTradingFee, "Incorrect trading fee on buy");

        // Test sell fee
        uint256 tokenBalance = IERC20(tokenAddress).balanceOf(buyer);
        vm.prank(buyer);
        IERC20(tokenAddress).approve(address(core), tokenBalance);

        platformBalanceBefore = platformFeeReceiver.balance;

        vm.prank(buyer);
        core.sell(tokenAddress, tokenBalance / 2, 0, block.timestamp + 3600);

        platformBalanceAfter = platformFeeReceiver.balance;
        uint256 sellTradingFee = platformBalanceAfter - platformBalanceBefore;
        assertGt(sellTradingFee, 0, "Should receive trading fee on sell");
    }

    function testVestingAllocationValidation() public {
        // Test vesting allocations exceeding 100%
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](2);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 6000,
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });
        vestingAllocations[1] =  IVestingParams.VestingAllocation({
            amount: 5000,
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Invalid Vesting Token",
            symbol: "INV",
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("invalid-vesting-test"),
            nonce: 4,
            initialBuyPercentage: 1000,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee)= core.calculateInitialBuyBNB(
            params.saleAmount,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 preBuyFeeVal = (initialBNB * core.preBuyFeeRate()) / 10000;
        uint256 totalPayment = core.creationFee() + initialBNB + preBuyFeeVal;

        vm.prank(creator);
        vm.expectRevert();
        core.createToken{value: totalPayment}(data, signature);
    }

    function testZeroFeeScenarios() public {
        // Test with zero creation fee
        vm.prank(admin);
        core.setCreationFee(0);

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Zero Fee Token",
            symbol: "ZERO",
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("zero-fee-test"),
            nonce: 5,
            initialBuyPercentage: 0,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Should succeed with zero payment (except gas)
        vm.prank(creator);
        core.createToken{value: 0}(data, signature);
    }

    function testPreBuyFeeRateZero() public {
        // Test with zero pre-buy fee rate
        vm.prank(admin);
        core.setPreBuyFeeRate(0);

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Zero PreBuy Fee Token",
            symbol: "ZPBF",
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("zero-prebuy-test"),
            nonce: 6,
            initialBuyPercentage: 1000,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        (uint256 expectedTokens, uint256 expectedBNB) = calculateExpectedInitialBuy(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );

        uint256 totalPayment = core.creationFee() + expectedBNB; // No preBuyFee

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 creatorBalanceBefore = creator.balance;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        uint256 creatorBalanceAfter = creator.balance;
        uint256 actualPayment = creatorBalanceBefore - creatorBalanceAfter;

        assertEq(actualPayment, totalPayment, "Should pay only creation fee + initial buy without preBuyFee");
    }

    // Helper function to calculate expected initial buy
    function calculateExpectedInitialBuy(
        uint256 saleAmount,
        uint256 virtualBNBReserve,
        uint256 virtualTokenReserve,
        uint256 percentageBP
    ) internal pure returns (uint256 tokensOut, uint256 bnbRequired) {
        tokensOut = (saleAmount * percentageBP) / 10000;
        uint256 k = virtualBNBReserve * virtualTokenReserve;
        uint256 newTokenReserve = virtualTokenReserve - tokensOut;
        uint256 newBNBReserve = k / newTokenReserve;
        bnbRequired = newBNBReserve - virtualBNBReserve;
    }

    function testEdgeCaseInitialBuyPercentages() public {
        // Test 0% initial buy
        testInitialBuyPercentage(0, "ZeroPercent");

        // Test 1% initial buy
        testInitialBuyPercentage(100, "OnePercent");
        // Test 99.9% initial buy (max allowed)
        testInitialBuyPercentage(8000, "MaxPercent");
    }

    function testInitialBuyPercentage(uint256 percentage, string memory suffix) internal {
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: string(abi.encodePacked("Test ", suffix)),
            symbol: string(abi.encodePacked("T", suffix)),
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("edge-test-", suffix)),
            nonce: uint256(keccak256(abi.encodePacked(suffix))),
            initialBuyPercentage: percentage,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        (uint256 expectedTokens, uint256 expectedBNB) = calculateExpectedInitialBuy(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            percentage
        );

        uint256 preBuyFee = (expectedBNB * core.preBuyFeeRate()) / 10000;
        uint256 totalPayment = core.creationFee() + expectedBNB + preBuyFee;

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        // Verify token was created successfully
        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        assertTrue(tokenAddress != address(0), "Token should be created");
    }
}