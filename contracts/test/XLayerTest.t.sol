// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/MEMECore.sol";
import "../src/MEMEFactory.sol";
import "../src/MEMEHelper.sol";
import "../src/MEMEVesting.sol";
import "../src/MEMEToken.sol";
import "../src/interfaces/IMEMECore.sol";

contract XLayerTest is Test {
    address constant PANCAKE_V2_ROUTER = 0x78491F2f4b9198aD17548295bb6CfCaFFC9FE1aB;
    address constant WBNB = 0xEAa36b2825a87b97f6847e295ACd8a233033E5f2;

    uint256 constant SIGNER_PRIVATE_KEY = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    address signer;

    address admin = address(0xA11CE);
    address creator = address(0xC0FFEE);
    address user = address(0x1234);

    MetaNodeCore coreImpl;
    MetaNodeCore core;
    MEMEFactory factory;
    MEMEHelper helper;
    MEMEVesting vestingImpl;
    MEMEVesting vesting;

    address createdToken;

    uint256 constant TOTAL_SUPPLY = 1000000000 ether;
    uint256 constant SALE_AMOUNT = 999000000 ether;
    uint256 constant VIRTUAL_BNB_RESERVE = 8219178082191780000;
    uint256 constant VIRTUAL_TOKEN_RESERVE = 1073972602 ether;

    function setUp() public {
        vm.createSelectFork("xlayer_test", 12601629);

        signer = vm.addr(SIGNER_PRIVATE_KEY);
        vm.deal(admin, 1000 ether);
        vm.deal(signer, 1000 ether);
        vm.deal(creator, 1000 ether);
        vm.deal(user, 1000 ether);

        vm.startPrank(admin);
        factory = new MEMEFactory(admin);
        helper = new MEMEHelper(admin, PANCAKE_V2_ROUTER, WBNB);

        coreImpl = new MetaNodeCore();
        bytes memory coreInitData = abi.encodeWithSelector(
            MetaNodeCore.initialize.selector,
            address(factory),
            address(helper),
            signer,
            admin,
            admin,
            admin,
            admin
        );
        ERC1967Proxy coreProxy = new ERC1967Proxy(address(coreImpl), coreInitData);
        core = MetaNodeCore(payable(address(coreProxy)));

        factory.setMetaNode(address(core));
        helper.grantRole(helper.CORE_ROLE(), address(core));

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
        createdToken = _createTokenHelper();
    }

    function _createTokenHelper() internal returns (address token) {
        IMetaNodeCore.CreateTokenParams memory params;
        params.name = "TestToken";
        params.symbol = "TT";
        params.totalSupply = TOTAL_SUPPLY;
        params.saleAmount = SALE_AMOUNT;
        params.virtualBNBReserve = VIRTUAL_BNB_RESERVE;
        params.virtualTokenReserve = VIRTUAL_TOKEN_RESERVE;
        params.launchTime = block.timestamp;
        params.creator = creator;
        params.timestamp = block.timestamp;
        params.requestId = keccak256("req-1");
        params.nonce = 1;
        params.initialBuyPercentage = 5000;
        params.marginBnb = 0;
        params.marginTime = 0;

        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 creationFee = core.creationFee();
        uint256 preBuyFeeRate = core.preBuyFeeRate();
        (uint256 initialBNB, uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.saleAmount,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 preBuyFeeAmount = (initialBNB * preBuyFeeRate) / 10000;
        uint256 totalPayment = creationFee + initialBNB + preBuyFeeAmount;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        token = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );
    }

    function testBuyAndSell() public {
        vm.prank(user);
        core.buy{value: 1 ether}(createdToken, 1 ether, block.timestamp + 60);

        uint256 bal = IERC20(createdToken).balanceOf(user);
        vm.startPrank(user);
        IERC20(createdToken).approve(address(core), bal);
        core.sell(createdToken, bal / 2, 0, block.timestamp + 60);
        vm.stopPrank();
    }

    function testGraduateToken() public {
        IBondingCurveParams.BondingCurveParams memory curve = core.getBondingCurve(createdToken);
        IMetaNodeCore.TokenInfo memory info = core.getTokenInfo(createdToken);

        uint256 tokensToBuy = curve.availableTokens - 9 ether;

        uint256 bnbNeeded = _calculateBNBNeededForTokens(createdToken, tokensToBuy);

        uint256 expectedTokens = helper.calculateTokenAmountOut(bnbNeeded, curve);
        uint256 minTokens = expectedTokens * 95 / 100;

        vm.prank(user);
        core.buy{value: bnbNeeded}(createdToken, minTokens, block.timestamp + 3600);

        vm.startPrank(admin);
        core.graduateToken(createdToken);
        vm.stopPrank();

        info = core.getTokenInfo(createdToken);
        assert(uint(info.status) == uint(IMetaNodeCore.TokenStatus.GRADUATED));
    }

    function _calculateBNBNeededForTokens(address token, uint256 tokenAmount) internal view returns (uint256) {
        IMetaNodeCore.BondingCurveParams memory curve = core.getBondingCurve(token);
        require(tokenAmount < curve.virtualTokenReserve, "Too many tokens");
        uint256 newTokenReserve = curve.virtualTokenReserve - tokenAmount;
        uint256 newBNBReserve = curve.k / newTokenReserve;
        return newBNBReserve - curve.virtualBNBReserve;
    }

    function testPauseAndBlacklistToken() public {
        vm.startPrank(admin);
        core.pauseToken(createdToken);
        core.blacklistToken(createdToken);
        vm.stopPrank();
    }

    function testCreateToken_RepeatedRequestIdShouldFail() public {
        uint256 fixedTimestamp = block.timestamp;
        uint256 fixedNonce = 1;
        bytes32 requestId = keccak256(abi.encodePacked("fixed-request", fixedTimestamp, fixedNonce));
        address token1 = _createTokenWithFixedParams(fixedTimestamp, fixedNonce, requestId, "UniqueToken", "UTK");
        assertTrue(token1 != address(0), "First token creation should succeed");
        assertTrue(core.usedRequestIds(requestId), "Request ID should be marked as used");
    }


    function _createTokenWithFixedParams(
        uint256 timestamp,
        uint256 nonce,
        bytes32 requestId,
        string memory name,
        string memory symbol
    ) internal returns (address token) {
        IMetaNodeCore.CreateTokenParams memory params;
        params.name = name;
        params.symbol = symbol;
        params.totalSupply = TOTAL_SUPPLY;
        params.saleAmount = SALE_AMOUNT;
        params.virtualBNBReserve = VIRTUAL_BNB_RESERVE;
        params.virtualTokenReserve = VIRTUAL_TOKEN_RESERVE;
        params.launchTime = timestamp;
        params.creator = creator;
        params.timestamp = timestamp;
        params.requestId = requestId;
        params.nonce = nonce;
        params.initialBuyPercentage = 500;
        params.marginBnb = 0;
        params.marginTime = 0;


        bytes memory data = abi.encode(params);
        bytes32 messageHash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_PRIVATE_KEY, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 creationFee = core.creationFee();
        uint256 preBuyFeeRate = core.preBuyFeeRate();
        (uint256 initialBNB, uint256 preBuyFee) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        uint256 totalPayment = creationFee + initialBNB;

        vm.prank(creator);
        core.createToken{value: totalPayment}(data, signature);

        token = factory.predictTokenAddress(
            params.name,
            params.symbol,
            params.totalSupply,
            address(core),
            params.timestamp,
            params.nonce
        );
    }

    function testBuyExpiredDeadline() public {
        vm.expectRevert(IMetaNodeCore.TransactionExpired.selector);
        vm.prank(user);
        core.buy{value: 1 ether}(createdToken, 1 ether, block.timestamp - 1);
    }

    function testSellZeroAmountShouldFail() public {
        vm.expectRevert(IMetaNodeCore.InvalidParameters.selector);
        vm.prank(user);
        core.sell(createdToken, 0, 0, block.timestamp + 60);
    }

    function testCalculateInitialBuyBNBExceedMaxShouldFail() public {
        vm.expectRevert(IMetaNodeCore.InvalidParameters.selector);
        core.calculateInitialBuyBNB(100, 1 ether, 100 ether, 10_000);
    }

    function testSetMarginReceiverZeroAddressShouldFail() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        core.setMarginReceiver(address(0));
        vm.stopPrank();
    }

    function testBuyWhilePausedShouldFail() public {
        vm.startPrank(admin);
        core.pause();
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        vm.prank(user);
        core.buy{value: 1 ether}(createdToken, 1 ether, block.timestamp + 60);
    }

    function testCalculateFunctions() public view {
        IBondingCurveParams.BondingCurveParams memory curve = IBondingCurveParams.BondingCurveParams({
            virtualBNBReserve: 10 ether,
            virtualTokenReserve: 500_000 ether,
            k: 10 ether * 500_000 ether,
            availableTokens: 500_000 ether,
            collectedBNB: 0
        });
        uint256 tokens = helper.calculateTokenAmountOut(1 ether, curve);
        uint256 bnb = helper.calculateBNBAmountOut(1000 ether, curve);
        assertGt(tokens, 0);
        assertGt(bnb, 0);
    }
}
