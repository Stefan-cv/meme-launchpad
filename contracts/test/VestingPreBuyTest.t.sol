// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VestingPreBuyTest
 * @notice 预购 + 归属组合功能测试
 * @dev 测试初始买入（Pre-buy）与归属计划（Vesting）的组合使用场景
 *
 * 业务场景说明：
 * - 创建者可以同时配置初始买入和归属计划
 * - 预购的代币可以按归属计划锁仓释放
 * - 支持 CLIFF（悬崖）、LINEAR（线性）、BURN（销毁）三种模式组合
 *
 * 测试覆盖场景：
 * 1. 纯预购（无归属）- 代币直接发放给创建者
 * 2. 预购 + 保证金 - 同时使用两个功能
 * 3. 预购 + 悬崖归属 - 预购代币在到期后一次性释放
 * 4. 预购 + 混合归属 - 多种归属模式组合
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
import {MockPancakeRouter} from "./mocks/MockPancakeRouter.sol";
import {MockWBNB} from "./mocks/MockWBNB.sol";

contract VestingPreBuyTest is Test {
    MetaNodeCore public core;
    MEMEFactory public factory;
    MEMEHelper public helper;
    MEMEVesting public vesting;

    address public admin = address(0x1);
    uint256 public signerPrivateKey = 0x1234567890;
    address public signer;
    address public platformFeeReceiver = address(0x3);
    address public marginReceiver = address(0x4);
    address public creator = address(0x5);
    address public buyer = address(0x6);

    uint256 public secondsInOneDay = 86400;

    function setUp() public {
        // Setup signer
        signer = vm.addr(signerPrivateKey);

        vm.startPrank(admin);
        MockWBNB wbnb = new MockWBNB();
        MockPancakeRouter router = new MockPancakeRouter(address(wbnb));

        // Deploy contracts
        helper = new MEMEHelper(admin, address(router), address(wbnb));
        factory = new MEMEFactory(admin);

        // Deploy Core
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

        // Deploy Vesting
        MEMEVesting vestingImpl = new MEMEVesting();
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

        // Fund accounts
        vm.deal(creator, 10000 ether);
        vm.deal(buyer, 10000 ether);
    }

    function _createTokenWithParams(IMetaNodeCore.CreateTokenParams memory params) internal returns (address) {
        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Calculate payment
        (uint256 initialBNB,uint256 preBuyFee)  = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = core.creationFee() + initialBNB + params.marginBnb;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        return factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );
    }

    function testCreateTokenWithPrebuy() public {
        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Prebuy Token",
            symbol: "PRE",
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("prebuy-test"),
            nonce: 1,
            initialBuyPercentage: 3000, // 30% prebuy
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        address tokenAddress = _createTokenWithParams(params);

        assertTrue(tokenAddress != address(0), "Token should be created");

        uint256 creatorBalance = IERC20(tokenAddress).balanceOf(creator);
        uint256 expectedTokens = (params.totalSupply * params.initialBuyPercentage) / 10000;
        assertApproxEqAbs(creatorBalance, expectedTokens, 1 ether, "Creator should receive prebuy tokens");
    }

    function testCreateTokenWithPrebuyAndMargin() public {
        uint256 marginAmount = 2 ether;
        uint256 lockTime = 30 days;

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Prebuy Margin Token",
            symbol: "PMT",
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 800000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("prebuy-margin-test"),
            nonce: 2,
            initialBuyPercentage: 2000, // 20% prebuy
            marginBnb: marginAmount,
            marginTime: lockTime,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        uint256 marginReceiverBalanceBefore = marginReceiver.balance;
        address tokenAddress = _createTokenWithParams(params);

        assertEq(marginReceiver.balance - marginReceiverBalanceBefore, marginAmount, "Margin should be transferred");

        uint256 creatorBalance = IERC20(tokenAddress).balanceOf(creator);
        uint256 expectedTokens = (params.totalSupply * params.initialBuyPercentage) / 10000;
        assertApproxEqAbs(creatorBalance, expectedTokens, 1 ether, "Creator should receive prebuy tokens");
    }

    function testCreateTokenWithCliffVesting() public {
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](1);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 5000,
             launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.CLIFF
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Cliff Vest Token",
            symbol: "CVT",
            totalSupply: 1000000 ether,
            saleAmount: 800000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("cliff-vest-test"),
            nonce: 3,
            initialBuyPercentage: 5000, // 50% prebuy
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        address tokenAddress = _createTokenWithParams(params);

        uint256 scheduleCount = vesting.getVestingScheduleCount(tokenAddress, creator);
        assertEq(scheduleCount, 1, "Should have 1 vesting schedule");

        uint256 claimable = vesting.getClaimableAmount(tokenAddress, creator, 0);
        assertEq(claimable, 0, "No tokens should be claimable before cliff");

        vm.warp(block.timestamp + secondsInOneDay);

        uint256 totalInitialTokens = (params.totalSupply * params.initialBuyPercentage) / 10000;
        claimable = vesting.getClaimableAmount(tokenAddress, creator, 0);
        assertApproxEqAbs(claimable, totalInitialTokens, 1 ether, "All tokens should be claimable after cliff");

        vm.prank(creator);
        uint256 claimed = vesting.claim(tokenAddress, 0);
        assertApproxEqAbs(claimed, totalInitialTokens, 1 ether, "Should claim all tokens");
    }

    function testCreateTokenWithMixedVesting() public {
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](2);
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 3000,  // 30% cliff after 30 minutes
             launchTime: 0,
            duration: secondsInOneDay,
            mode: IVestingParams.VestingMode.CLIFF
        });
        vestingAllocations[1] = IVestingParams.VestingAllocation({
            amount: 6990,  // 60% linear over 1 hour
             launchTime: 0,
            duration: 172800,
            mode: IVestingParams.VestingMode.LINEAR
        });

        IMetaNodeCore.CreateTokenParams memory params = IMetaNodeCore.CreateTokenParams({
            name: "Mixed Vest Token",
            symbol: "MVT",
            totalSupply: 1000000 ether,
            saleAmount: 999000 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000000 ether,
            launchTime: 0,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("mixed-vest-test"),
            nonce: 5,
            initialBuyPercentage: 9990,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        address tokenAddress = _createTokenWithParams(params);

        uint256 totalInitialTokens = (params.totalSupply * params.initialBuyPercentage) / 10000;
        uint256 cliffAmount = (params.totalSupply * 3000) / 10000;
        uint256 linearAmount = totalInitialTokens - cliffAmount;

        uint256 scheduleCount = vesting.getVestingScheduleCount(tokenAddress, creator);
        assertEq(scheduleCount, 2, "Should have 2 vesting schedules");

        vm.warp(block.timestamp + secondsInOneDay);

        uint256 claimable0 = vesting.getClaimableAmount(tokenAddress, creator, 0);
        assertApproxEqAbs(claimable0, cliffAmount, 1 ether, "Cliff should be fully vested");

        uint256 claimable1 = vesting.getClaimableAmount(tokenAddress, creator, 1);
        assertApproxEqAbs(claimable1, linearAmount / 2, 1 ether, "Linear should be 50% vested");

        vm.prank(creator);
        uint256 totalClaimed = vesting.claimAll(tokenAddress);
        uint256 expectedTotal = cliffAmount + (linearAmount / 2);
        assertApproxEqAbs(totalClaimed, expectedTotal, 1 ether, "Should claim all available tokens");
    }
}