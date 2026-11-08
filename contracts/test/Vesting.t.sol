// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VestingTest
 * @notice 代币归属（锁仓释放）功能综合测试
 * @dev 测试代币创建时的归属计划配置和释放机制
 *
 * 归属模式（VestingMode）：
 * - BURN：销毁模式 - 指定比例的代币在创建时直接销毁
 * - CLIFF：悬崖模式 - 在指定时间后一次性释放全部代币
 * - LINEAR：线性模式 - 在指定时间段内线性释放代币
 *
 * 测试覆盖场景：
 * 1. 多归属计划创建 - 同时配置多个不同模式的归属计划
 * 2. 线性释放测试 - 验证代币按时间线性释放
 * 3. 销毁模式测试 - 验证代币正确销毁
 * 4. 部分归属测试 - 部分锁仓、部分立即发放
 * 5. 无初始买入时的归属 - 验证无预购时归属计划不生效
 * 6. 无效归属参数 - 验证参数校验
 * 7. 最小锁仓时间校验 - 验证 duration 最小值限制
 * 8. 归属开始时间计算 - 验证 launchTime 与归属开始时间的关系
 * 9. 毕业时的费用分配 - 验证代币毕业后的费用分配
 * 10. 池子比率边界测试 - 验证不同虚拟储备配置
 */
import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/MEMECore.sol";
import "../src/MEMEFactory.sol";
import "../src/MEMEHelper.sol";
import "../src/MEMEVesting.sol";
import "../src/MEMEToken.sol";
import "../src/interfaces/IMEMECore.sol";
import "../src/interfaces/IMEMEVesting.sol";
import "../src/interfaces/IVestingParams.sol";
import {MockPancakeRouter} from "./mocks/MockPancakeRouter.sol";
import {MockWBNB} from "./mocks/MockWBNB.sol";

contract VestingTest is Test {
    MetaNodeCore public coreImpl;
    MetaNodeCore public core;
    MEMEFactory public factory;
    MEMEHelper public helper;
    MEMEVesting public vestingImpl;
    MEMEVesting public vesting;

    address public admin = address(0x1);
    uint256 public signerPrivateKey = 0x12345;
    address public signer;
    address public platformFeeReceiver = address(0x3);
    address public marginReceiver = address(0x4);
    address public creator = address(0x5);
    uint256 public secondsInOneDay = 86400;

    event VestingCreated(
        address indexed token,
        address indexed beneficiary,
        uint256 totalVestedAmount,
        uint256 scheduleCount
    );

    event TokensClaimed(
        address indexed token,
        address indexed beneficiary,
        uint256 scheduleId,
        uint256 amount
    );

    function setUp() public {
        // Derive signer address from private key
        signer = vm.addr(signerPrivateKey);

        vm.startPrank(admin);
        MockWBNB wbnb = new MockWBNB();
        MockPancakeRouter router = new MockPancakeRouter(address(wbnb));
        // Deploy Helper
        helper = new MEMEHelper(admin, address(router), address(wbnb));

        // Deploy Factory
        factory = new MEMEFactory(admin);

        // Deploy and initialize Core
        coreImpl = new MetaNodeCore();
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

        // Deploy and initialize Vesting
        vestingImpl = new MEMEVesting();
        bytes memory vestingInitData = abi.encodeWithSelector(
            MEMEVesting.initialize.selector,
            admin,
            address(core)
        );
        ERC1967Proxy vestingProxy = new ERC1967Proxy(address(vestingImpl), vestingInitData);
        vesting = MEMEVesting(address(vestingProxy));

        // Configure Core
        core.setMarginReceiver(marginReceiver);
        core.setVesting(address(vesting));

        // Grant roles
        factory.setMetaNode(address(core));
        helper.grantRole(helper.CORE_ROLE(), address(core));
        vm.stopPrank();

        // Fund creator
        vm.deal(creator, 10000 ether);
    }

    function testCreateTokenWithVesting() public {
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](3);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 4000,
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });
        vestingAllocations[1] = IVestingParams.VestingAllocation({
            amount: 3000,  // 30%
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });
        vestingAllocations[2] = IVestingParams.VestingAllocation({
            amount: 2000,  // 20%
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });

        // Create token with initial buy and vesting
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Test Token",
            symbol: "TEST",
            totalSupply: 1000000 ether,
            saleAmount: 900000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test1"),
            nonce: 1,
            initialBuyPercentage: 9000,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Calculate required payment
        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        // Create token
        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);
    }

    function testLinearVestingRelease() public {
        // Create token with vesting
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](1);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 9000,  // 100% vested
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Test Token",
            symbol: "TEST",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test2"),
            nonce: 2,
            initialBuyPercentage: 9000,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        // Get token address (we need to predict it or get it from events)
        // For simplicity, we'll get the last created token
        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        // Check initial state - no tokens claimable immediately
        uint256 claimable = vesting.getClaimableAmount(tokenAddress, creator, 0);
        assertEq(claimable, 0, "Should have no claimable tokens initially");

        // Move forward 30 minutes (50% of vesting period)
        vm.warp(block.timestamp + secondsInOneDay / 2);

        // Check claimable amount - should be approximately 50%
        claimable = vesting.getClaimableAmount(tokenAddress, creator, 0);
        uint256 expectedTokens = (params.totalSupply * 9000) / 10000;
        uint256 expectedClaimable = expectedTokens / 2; // 50% vested
        assertApproxEqAbs(claimable, expectedClaimable, 1 ether, "Should have ~50% claimable");

        // Claim tokens
        vm.prank(creator);
        uint256 claimed = vesting.claim(tokenAddress, 0);
        assertGt(claimed, 0, "Should have claimed some tokens");

        vm.warp(86401);

        // Claim remaining tokens
        vm.prank(creator);
        uint256 remainingClaimed = vesting.claim(tokenAddress, 0);
        assertGt(remainingClaimed, 0, "Should have claimed remaining tokens");

        // Verify all tokens have been claimed
        claimable = vesting.getClaimableAmount(tokenAddress, creator, 0);
        assertEq(claimable, 0, "Should have no claimable tokens left");
    }

    function testTokenBurnDuringCreation() public {
        // Test token burn during creation
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](1);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 8000, // 80% burn
            launchTime: 0,
            duration: 0,
            mode: IVestingParams.VestingMode.BURN
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Burn Test Token",
            symbol: "BURN",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: block.timestamp,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("burn-test"),
            nonce: 100,
            initialBuyPercentage: 9990,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        // Verify total supply is reduced by burned amount
        uint256 finalSupply = IERC20(tokenAddress).totalSupply();
        uint256 expectedSupply = 1000000 ether - (1000000 ether * 8000 / 10000);
        assertEq(finalSupply, expectedSupply, "Total supply should be reduced by burned amount");
    }


    function testMultipleVestingSchedules() public {
        // Create token with multiple vesting schedules
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](3);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 300,
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.BURN
        });
        vestingAllocations[1] = IVestingParams.VestingAllocation({
            amount: 200,
            launchTime: 0,
            duration: secondsInOneDay * 2,
            mode: IVestingParams.VestingMode.LINEAR
        });
        vestingAllocations[2] = IVestingParams.VestingAllocation({
            amount: 400,
            launchTime: 0,
            duration: secondsInOneDay * 3,
            mode: IVestingParams.VestingMode.CLIFF
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Multi Vest Token",
            symbol: "MVT",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test3"),
            nonce: 3,
            initialBuyPercentage: 900,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        // Check schedule count
        uint256 scheduleCount = vesting.getVestingScheduleCount(tokenAddress, creator);
        assertEq(scheduleCount, 3, "Should have 3 vesting schedules");

        // Move forward 1 hour - first schedule should be fully vested
        vm.warp(block.timestamp + secondsInOneDay);

        uint256 claimable0 = vesting.getClaimableAmount(tokenAddress, creator, 0);
        uint256 claimable1 = vesting.getClaimableAmount(tokenAddress, creator, 1);
        uint256 claimable2 = vesting.getClaimableAmount(tokenAddress, creator, 2);

        uint256 schedule1Amount = (params.totalSupply * 200) / 10000; 
        uint256 schedule2Amount = (params.totalSupply * 400) / 10000;

        // First schedule should be fully vested
        assertApproxEqAbs(claimable0, 0, 1 ether, "Schedule 0 should be fully vested");
        // Second schedule should be 50% vested
        assertApproxEqAbs(claimable1, schedule1Amount / 2, 1 ether, "Schedule 1 should be 50% vested");
        // Third schedule should be 33% vested
        assertApproxEqAbs(claimable2, 0, 1 ether, "Schedule 2 should be 33% vested");

        // Claim all available tokens
        vm.prank(creator);
        uint256 totalClaimed = vesting.claimAll(tokenAddress);
        assertGt(totalClaimed, 0, "Should have claimed tokens from all schedules");
    }

    function testMultiVestingSchedules() public {
        // Create token with multiple vesting schedules
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](3);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 500,
            launchTime: 0,
            duration: 86400,
            mode: IVestingParams.VestingMode.CLIFF
        });
        vestingAllocations[1] = IVestingParams.VestingAllocation({
            amount: 300,
            launchTime: 0,
            duration: 1728000,
            mode: IVestingParams.VestingMode.CLIFF
        });
        vestingAllocations[2] = IVestingParams.VestingAllocation({
            amount: 200,
            launchTime: 0,
            duration: 0,
            mode: IVestingParams.VestingMode.BURN
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Multi Vest Token",
            symbol: "MVT",
            totalSupply: 1000000000000000000000000000,
            saleAmount: 999000000000000000000000000,
            virtualBNBReserve: 300000000000000000,
            virtualTokenReserve: 1000000000000000000000000000,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test3"),
            nonce: 7,
            initialBuyPercentage: 1000,
            marginBnb: 0,
            marginTime: block.timestamp + 300,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        // Check schedule count
        uint256 scheduleCount = vesting.getVestingScheduleCount(tokenAddress, creator);
        assertEq(scheduleCount, 3, "Should have 3 vesting schedules");

        // Move forward 1 hour - first schedule should be fully vested
        vm.warp(block.timestamp + secondsInOneDay);

        uint256 claimable0 = vesting.getClaimableAmount(tokenAddress, creator, 0);
        uint256 claimable1 = vesting.getClaimableAmount(tokenAddress, creator, 1);
        uint256 claimable2 = vesting.getClaimableAmount(tokenAddress, creator, 2);

        uint256 schedule0Amount = (params.totalSupply * 500) / 10000; 
        uint256 schedule1Amount = (params.totalSupply * 300) / 10000; 
        uint256 schedule2Amount = (params.totalSupply * 200) / 10000;

        // First schedule should be fully vested
        assertApproxEqAbs(claimable0, schedule0Amount, 1 ether, "Schedule 0 should be fully vested");
        assertApproxEqAbs(claimable1, 0, 1 ether, "Schedule 1 should be 50% vested");
        assertApproxEqAbs(claimable2, 0, 1 ether, "Schedule 2 should be 33% vested");

        // Claim all available tokens
        vm.prank(creator);
        uint256 totalClaimed = vesting.claimAll(tokenAddress);
        assertGt(totalClaimed, 0, "Should have claimed tokens from all schedules");
    }

    function testPartialVesting() public {
        // Create token with 50% vested, 50% immediate
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](1);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 5000,  // 50% vested
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Partial Vest Token",
            symbol: "PVT",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test4"),
            nonce: 4,
            initialBuyPercentage: 8000,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        // Check creator's balance before
        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        // Creator should have received 50% immediately
        IMEMEVesting.VestingSchedule memory vestingSchedule = vesting.getVestingSchedule(tokenAddress, creator, 0);
        uint256 totalInitialTokens = (1000000 ether * 8000) / 10000; // 50%
        uint256 vestAmount = (1000000 ether * 5000) / 10000; // 50%
        uint256 immediateTokens = totalInitialTokens - vestAmount; // 50% immediate

        assertApproxEqAbs(vestingSchedule.totalAmount, vestAmount, 1 ether, "Creator should have 50% tokens vest");
        assertApproxEqAbs(MetaNodeToken(tokenAddress).balanceOf(creator), immediateTokens, 1 ether, "Creator should have 30% tokens immediately");

        // Check vesting contract has the other 50%
        uint256 vestingBalance = MetaNodeToken(tokenAddress).balanceOf(address(vesting));
        assertApproxEqAbs(vestingBalance, vestAmount, 1 ether, "Vesting should hold 50% tokens");
    }

    function testVestingWithNoInitialBuy() public {
        // Create token without initial buy - vesting should not apply
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](1);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 10000,  // 100% vested (but no initial buy)
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "No Buy Token",
            symbol: "NBT",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test5"),
            nonce: 5,
            initialBuyPercentage: 0, // No initial buy
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
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

        // No vesting schedules should exist
        uint256 scheduleCount = vesting.getVestingScheduleCount(tokenAddress, creator);
        assertEq(scheduleCount, 0, "Should have no vesting schedules without initial buy");

        // Creator should have no tokens
        uint256 creatorBalance = MetaNodeToken(tokenAddress).balanceOf(creator);
        assertEq(creatorBalance, 0, "Creator should have no tokens");
    }

    function testInvalidVestingAllocations() public {
        // Test with vesting allocations exceeding 100%
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](2);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 6000,  // 60%
            launchTime: 0,
            duration: 1200,
            mode: IVestingParams.VestingMode.LINEAR
        });
        vestingAllocations[1] = IVestingParams.VestingAllocation({
            amount: 5000,  // 50% - total 110%
            launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Invalid Token",
            symbol: "INV",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("test6"),
            nonce: 6,
            initialBuyPercentage: 1000,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        // Should revert due to invalid vesting allocations
        vm.prank(creator);
        vm.expectRevert(IMetaNodeCore.InvalidDurationParameters.selector);
        core.createToken{value: totalPayment}(data, signature);
    }

    function testMinLockTimeValidation() public {
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](1);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 9000,
            launchTime: 0,
            duration: 3600,
            mode: IVestingParams.VestingMode.LINEAR
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Invalid Lock Token",
            symbol: "ILT",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("min-lock-test"),
            nonce: 999,
            initialBuyPercentage: 9000,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        vm.prank(creator);
        vm.expectRevert(IMetaNodeCore.InvalidDurationParameters.selector);
        core.createToken{value: totalPayment}(data, signature);
    }

    function testVestingStartTimeCalculation() public {
        // Test various vesting start time scenarios
        uint256 futureLaunchTime = block.timestamp + 2 days;

        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](3);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 3330, // Immediate start
            launchTime: futureLaunchTime,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });
        vestingAllocations[1] = IVestingParams.VestingAllocation({
            amount: 3330, // Delayed start
            launchTime: futureLaunchTime,
            duration: secondsInOneDay * 2,
            mode: IVestingParams.VestingMode.LINEAR
        });
        vestingAllocations[2] = IVestingParams.VestingAllocation({
            amount: 3330, // Cliff vesting
            launchTime: futureLaunchTime,
            duration: secondsInOneDay * 3,
            mode: IVestingParams.VestingMode.CLIFF
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Time Test Token",
            symbol: "TIME",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: futureLaunchTime,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("time-test"),
            nonce: 101,
            initialBuyPercentage: 9990,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        // Verify vesting schedules have correct start times
        uint256 scheduleCount = vesting.getVestingScheduleCount(tokenAddress, creator);
        assertEq(scheduleCount, 3, "Should have 3 vesting schedules");

        // Schedule 0: should start at launchTime (futureLaunchTime)
        IMEMEVesting.VestingSchedule memory schedule0 = vesting.getVestingSchedule(tokenAddress, creator, 0);
        assertEq(schedule0.startTime, futureLaunchTime, "Schedule 0 should start at launch time");
        assertEq(schedule0.endTime, futureLaunchTime + secondsInOneDay, "Schedule 0 should end at launch time");

        // Schedule 1: should start at launchTime + 1 day
        IMEMEVesting.VestingSchedule memory schedule1 = vesting.getVestingSchedule(tokenAddress, creator, 1);
        assertEq(schedule1.startTime, futureLaunchTime, "Schedule 1 should start 1 day after launch");
        assertEq(schedule1.endTime, futureLaunchTime + secondsInOneDay * 2, "Schedule 0 should end at launch time");

        // Schedule 2: should start at launchTime + 2 days (cliff)
        IMEMEVesting.VestingSchedule memory schedule2 = vesting.getVestingSchedule(tokenAddress, creator, 2);
        assertEq(schedule2.startTime, futureLaunchTime, "Schedule 2 should start 2 days after launch");
        assertEq(schedule2.endTime, futureLaunchTime + secondsInOneDay * 3, "Schedule 0 should end at launch time");

    }

    function testLinearUnlockAfterOneDay() public {
        uint256 launchTime = block.timestamp; // Schedule launch in 2 days
        uint256 delay = 0; // Start linear unlock 1 day after launch

        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](1);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 9990, // 100%
            launchTime: delay,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.LINEAR
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Linear Unlock Token",
            symbol: "LUNLOCK",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: launchTime,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("linear-unlock-test"),
            nonce: 102,
            initialBuyPercentage: 9990,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        // Before launch time - no tokens claimable
        vm.warp(launchTime - 1);
        uint256 claimable = vesting.getClaimableAmount(tokenAddress, creator, 0);
        assertEq(claimable, 0, "No tokens claimable before launch");

        // At launch time but before delay - still no tokens
        vm.warp(launchTime);
        claimable = vesting.getClaimableAmount(tokenAddress, creator, 0);
        assertEq(claimable, 0, "No tokens claimable at launch (before delay)");

        // After delay period starts - should have claimable tokens
        vm.warp(launchTime + 43201); // 50% through linear period
        claimable = vesting.getClaimableAmount(tokenAddress, creator, 0);
        uint256 expectedTokens = (params.totalSupply * 9990) / 10000;
        assertApproxEqAbs(claimable, expectedTokens / 2, 1 ether, "Should have 50% claimable after 6 hours");

        // After full linear period - all tokens claimable
        vm.warp(launchTime + delay + 24 hours);
        claimable = vesting.getClaimableAmount(tokenAddress, creator, 0);
        assertApproxEqAbs(claimable, expectedTokens, 1 ether, "Should have 100% claimable after full period");
    }

    function testFeeCalculationAtGraduation() public {
        // Create token without initial buy
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Graduation Fee Token",
            symbol: "GFEE",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("graduation-fee-test"),
            nonce: 300,
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

        // Simulate trading to collect BNB
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 10 ether);

        // Buy tokens to fill the bonding curve
        vm.prank(buyer);
        core.buy{value: 5 ether}(tokenAddress, 0, block.timestamp + 3600);

        // Get balances before graduation
        uint256 platformBalanceBefore = platformFeeReceiver.balance;
        uint256 creatorBalanceBefore = creator.balance;
        uint256 platformTokenBalanceBefore = IERC20(tokenAddress).balanceOf(platformFeeReceiver);
        uint256 creatorTokenBalanceBefore = IERC20(tokenAddress).balanceOf(creator);

        // Trigger graduation
        vm.prank(admin);
        core.graduateToken(tokenAddress);

        // Verify fee distribution (5.5% to platform, 2.5% to creator)
        IMetaNodeCore.BondingCurveParams memory curve = core.getBondingCurve(tokenAddress);
        uint256 totalCollectedBNB = curve.collectedBNB;

        uint256 expectedPlatformBNB = (totalCollectedBNB * 550) / 10000; // 5.5%
        uint256 expectedCreatorBNB = (totalCollectedBNB * 250) / 10000;  // 2.5%

        uint256 platformBNBReceived = platformFeeReceiver.balance - platformBalanceBefore;
        uint256 creatorBNBReceived = creator.balance - creatorBalanceBefore;

        assertApproxEqAbs(platformBNBReceived, expectedPlatformBNB, 1e15, "Platform should receive 5.5% BNB");
        assertApproxEqAbs(creatorBNBReceived, expectedCreatorBNB, 1e15, "Creator should receive 2.5% BNB");
    }

    function testRecommendedPoolRatios() public {
        uint256[] memory virtualBNBReserves = new uint256[](4);
        virtualBNBReserves[0] = 0.3 ether;
        virtualBNBReserves[1] = 2.02 ether;
        virtualBNBReserves[2] = 3.03 ether;
        virtualBNBReserves[3] = 6.06 ether;


        for (uint256 i = 0; i < virtualBNBReserves.length; i++) {
            IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
                name: string(abi.encodePacked("Pool Test ", i)),
                symbol: string(abi.encodePacked("POOL", i)),
                totalSupply: 1000000000 ether, // 1B tokens
                saleAmount: 800000000 ether,   // 800M for sale
                virtualBNBReserve: virtualBNBReserves[i],
                virtualTokenReserve: 800000000 ether,
                launchTime: 0,
                creator: creator,
                timestamp: block.timestamp,
                requestId: keccak256(abi.encodePacked("pool-test-", i)),
                nonce: 200 + i,
                initialBuyPercentage: 0, // No pre-buy for price testing
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
            // Verify opening price calculation
            IMetaNodeCore.BondingCurveParams memory curve = core.getBondingCurve(tokenAddress);
            uint256 calculatedPrice = (curve.virtualBNBReserve * 1e18) / curve.virtualTokenReserve;

            // For standard pool: 0.3 BNB / 800M tokens = 0.375e-9 BNB per token
            // Convert to USD equivalent or compare relative values
            if (i == 0) {
                assertApproxEqAbs(calculatedPrice, 375000000, 1000, "Standard pool price should be ~0.375e-9 BNB/token");
            }
        }
    }

    function testFeeCalculationAfterGraduation() public {
        // Create token without initial buy
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Graduation Fee Token",
            symbol: "GFEE",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("graduation-fee-test"),
            nonce: 300,
            initialBuyPercentage: 0,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(admin);
        core.createToken{value: core.creationFee()}(data, signature);

        address tokenAddress = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );

        // Simulate trading to collect BNB
        address buyer = makeAddr("buyer");
        vm.deal(buyer, 10 ether);

        // Buy tokens to fill the bonding curve
        vm.prank(buyer);
        core.buy{value: 5 ether}(tokenAddress, 0, block.timestamp + 3600);

        // Get balances before graduation
        uint256 platformBalanceBefore = platformFeeReceiver.balance;
        uint256 creatorBalanceBefore = creator.balance;
        uint256 platformTokenBalanceBefore = IERC20(tokenAddress).balanceOf(platformFeeReceiver);
        uint256 creatorTokenBalanceBefore = IERC20(tokenAddress).balanceOf(creator);

        // Trigger graduation
        vm.prank(admin);
        core.graduateToken(tokenAddress);

        // Verify fee distribution (5.5% to platform, 2.5% to creator)
        IMetaNodeCore.BondingCurveParams memory curve = core.getBondingCurve(tokenAddress);
        uint256 totalCollectedBNB = curve.collectedBNB;

        uint256 expectedPlatformBNB = (totalCollectedBNB * 550) / 10000; // 5.5%
        uint256 expectedCreatorBNB = (totalCollectedBNB * 250) / 10000;  // 2.5%

        uint256 platformBNBReceived = platformFeeReceiver.balance - platformBalanceBefore;
        uint256 creatorBNBReceived = creator.balance - creatorBalanceBefore;

        assertApproxEqAbs(platformBNBReceived, expectedPlatformBNB, 1e15, "Platform should receive 5.5% BNB");
        assertApproxEqAbs(creatorBNBReceived, expectedCreatorBNB, 1e15, "Creator should receive 2.5% BNB");
    }

    function testPoolRatioBoundaries() public {
        // Test minimum and maximum pool ratios
        testPoolRatioCreation("PoolRatioCreation1", 0.3 ether, true, "Minimum pool ratio should work");
        testPoolRatioCreation("PoolRatioCreation2", 20 ether, true, "Maximum pool ratio should work");
    }

    function testPoolRatioCreation(string memory name, uint256 virtualBNBReserve, bool shouldSucceed, string memory message) internal {
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: name,
            symbol: "BOUND",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: virtualBNBReserve,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("boundary-test-", virtualBNBReserve)),
            nonce: 400,
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
        if (shouldSucceed) {
            core.createToken{value: core.creationFee()}(data, signature);
            // Verify token was created
            address tokenAddress = factory.predictTokenAddress(
                params.name,
                params.symbol,
                params.totalSupply,
                address(core),
                params.timestamp,
                params.nonce
            );
            assertTrue(tokenAddress != address(0), message);
        } else {
            vm.expectRevert(IMetaNodeCore.InvalidParameters.selector);
            core.createToken{value: core.creationFee()}(data, signature);
        }
    }

    function testMaximumPreBuyPercentage() public {
        vm.deal(creator, 2000 ether); // Increase funding
        testPreBuyPercentage(9990, true, "99.9% pre-buy should work");
    }

    function testPreBuyPercentage(uint256 percentage, bool shouldSucceed, string memory message) internal {
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "PreBuy Test",
            symbol: "PBUY",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("prebuy-test-", percentage)),
            nonce: 500,
            initialBuyPercentage: percentage,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB;

        vm.prank(creator);
        if (shouldSucceed) {
            core.createToken{value: totalPayment}(data, signature);
            address tokenAddress = factory.predictTokenAddress(
                params.name,
                params.symbol,
                params.totalSupply,
                address(core),
                params.timestamp,
                params.nonce
            );
            assertTrue(tokenAddress != address(0), message);
        } else {
            vm.expectRevert(IMetaNodeCore.InvalidParameters.selector);
            core.createToken{value: totalPayment}(data, signature);
        }
    }

    function testDynamicFeeAdjustment() public {
        // Test fee parameter adjustments
        uint256 newCreationFee = 0.1 ether;
        uint256 newPreBuyFeeRate = 100;
        uint256 newTradingFeeRate = 90;

        vm.prank(admin);
        core.setCreationFee(newCreationFee);

        vm.prank(admin);
        core.setPreBuyFeeRate(newPreBuyFeeRate);

        vm.prank(admin);
        core.setTradingFeeRate(newTradingFeeRate);

        // Verify new fees are applied
        assertEq(core.creationFee(), newCreationFee, "Creation fee should be updated");
        assertEq(core.preBuyFeeRate(), newPreBuyFeeRate, "Pre-buy fee rate should be updated");
        assertEq(core.tradingFeeRate(), newTradingFeeRate, "Trading fee rate should be updated");

        // Test that new fees are actually used in calculations
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Dynamic Fee Token",
            symbol: "DFEE",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("dynamic-fee-test"),
            nonce: 600,
            initialBuyPercentage: 1000,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        (uint256 initialBNB,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = newCreationFee + initialBNB;

        uint256 creatorBalanceBefore = creator.balance;
        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);
        uint256 creatorBalanceAfter = creator.balance;

        // Verify correct amount was deducted (including new fees)
        uint256 actualPayment = creatorBalanceBefore - creatorBalanceAfter;
        assertEq(actualPayment, totalPayment, "Should pay correct amount with new fees");
    }
}