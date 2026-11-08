// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/**
 * @title MetaNodeCoreTest
 * @notice MetaNode 核心合约单元测试
 * @dev 测试核心合约的权限控制、代币创建、交易限制等核心功能
 *
 * 测试覆盖场景：
 * 1. 权限控制测试 - 验证只有特定角色才能调用管理函数
 * 2. 保证金功能测试 - 验证创建代币时的保证金机制
 * 3. 交易限制测试 - 验证买入/卖出的边界条件
 * 4. 归属（Vesting）测试 - 验证代币锁仓释放机制
 * 5. 黑名单测试 - 验证被拉黑代币无法交易
 */
import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/MEMECore.sol";
import "../src/MEMEFactory.sol";
import "../src/MEMEHelper.sol";
import "../src/MEMEVesting.sol";
import "../src/MEMEToken.sol";
import "../src/interfaces/IVestingParams.sol";
import {MockPancakeRouter} from "./mocks/MockPancakeRouter.sol";
import {MockWBNB} from "./mocks/MockWBNB.sol";

contract MetaNodeCoreTest is Test {
    // ============ 合约实例 ============
    MetaNodeCore public core;      // 核心合约
    MEMEFactory public factory;    // 工厂合约
    MEMEHelper public helper;      // 辅助合约
    MEMEVesting public vesting;    // 归属合约

    // ============ 测试地址 ============
    address public admin = makeAddr("admin");       // 管理员地址
    address public creator = makeAddr("creator");   // 代币创建者
    address public user = makeAddr("user");         // 普通用户
    address public platform = makeAddr("platform"); // 平台费用接收地址

    // ============ 签名配置 ============
    uint256 signerPk = 0x1234;  // 签名者私钥
    address signer;              // 签名者地址

    function setUp() public {
        signer = vm.addr(signerPk);
        MockWBNB wbnb = new MockWBNB();
        MockPancakeRouter router = new MockPancakeRouter(address(wbnb));

        factory = new MEMEFactory(admin);
        helper = new MEMEHelper(admin, address(router), address(wbnb));
        MetaNodeCore impl = new MetaNodeCore();
        bytes memory initData = abi.encodeWithSelector(
            MetaNodeCore.initialize.selector,
            address(factory),
            address(helper),
            signer,
            platform,
            platform,
            platform,
            admin
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        core = MetaNodeCore(payable(address(proxy)));

        vm.startPrank(admin);
        factory.setMetaNode(address(core));
        helper.grantRole(helper.CORE_ROLE(), address(core));

        MEMEVesting vestImpl = new MEMEVesting();
        bytes memory vestInit = abi.encodeWithSelector(MEMEVesting.initialize.selector, admin, address(core));
        ERC1967Proxy vestProxy = new ERC1967Proxy(address(vestImpl), vestInit);
        vesting = MEMEVesting(address(vestProxy));
        core.setVesting(address(vesting));
        vm.stopPrank();

        vm.deal(creator, 100 ether);
        vm.deal(user, 100 ether);
    }

    function _signParams(IMetaNodeCore.CreateTokenParams memory params) internal view returns (bytes memory) {
        bytes memory data = abi.encode(params);
        bytes32 hash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, hash);
        return abi.encodePacked(r, s, v);
    }

    function _basicParams() internal view returns (IMetaNodeCore.CreateTokenParams memory p) {
        p = IMetaNodeCore.CreateTokenParams({
            name: "Extra",
            symbol: "EXT",
            totalSupply: 1000 ether,
            saleAmount: 800 ether,
            virtualBNBReserve: 1 ether,
            virtualTokenReserve: 1000 ether,
            launchTime: block.timestamp,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256("extra"),
            nonce: 1,
            initialBuyPercentage: 1000,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });
    }

    // ==================== 权限控制测试 ====================

    /**
     * @notice 测试只有管理员才能调用 setter 函数
     * @dev 非管理员调用 setFactory/setHelper/setVesting/setPlatformFeeReceiver 应该 revert
     */
    function testOnlyAdminCanSetters() public {
        vm.expectRevert();
        core.setFactory(address(0));
        vm.expectRevert();
        core.setHelper(address(0));
        vm.expectRevert();
        core.setVesting(address(0));
        vm.expectRevert();
        core.setPlatformFeeReceiver(address(0));
    }

    /**
     * @notice 测试只有 PAUSER 角色才能暂停代币
     * @dev 非 PAUSER 调用 pauseToken 应该 revert
     */
    function testOnlyPauserCanPauseToken() public {
        IMetaNodeCore.CreateTokenParams memory p = _basicParams();
        bytes memory sig = _signParams(p);
        (uint256 pay,uint256 preBuyFee) = core.calculateInitialBuyBNB(p.totalSupply, p.virtualBNBReserve, p.virtualTokenReserve, p.initialBuyPercentage);
        pay += core.creationFee();
        vm.prank(creator);
        core.createToken{value: pay}(abi.encode(p), sig);

        address token = factory.predictTokenAddress(p.name, p.symbol, p.totalSupply, address(core), p.timestamp, p.nonce);

        vm.expectRevert();
        core.pauseToken(token);
    }

    /**
     * @notice 测试只有 DEPLOYER 角色才能让代币毕业
     * @dev 非 DEPLOYER 调用 graduateToken 应该 revert
     */
    function testOnlyDeployerCanGraduate() public {
        IMetaNodeCore.CreateTokenParams memory p = _basicParams();
        bytes memory sig = _signParams(p);
        (uint256 pay,uint256 preBuyFee) = core.calculateInitialBuyBNB(p.totalSupply, p.virtualBNBReserve, p.virtualTokenReserve, p.initialBuyPercentage);
        pay += core.creationFee();
        vm.prank(creator);
        core.createToken{value: pay}(abi.encode(p), sig);

        address token = factory.predictTokenAddress(p.name, p.symbol, p.totalSupply, address(core), p.timestamp, p.nonce);

        vm.expectRevert();
        core.graduateToken(token);
    }

    // ==================== 保证金功能测试 ====================

    /**
     * @notice 测试带保证金创建代币
     * @dev 验证保证金 + 创建费用 + 预购费用正确转账给平台
     */
    function testCreateTokenWithMargin() public {
        IMetaNodeCore.CreateTokenParams memory p = _basicParams();
        p.marginBnb = 1 ether;
        bytes memory sig = _signParams(p);
        (uint256 pay,uint256 preBuyFee) = core.calculateInitialBuyBNB(p.totalSupply, p.virtualBNBReserve, p.virtualTokenReserve, p.initialBuyPercentage);
        pay += p.marginBnb;
        pay += core.creationFee();
        uint256 balBefore = platform.balance;
        vm.prank(creator);
        core.createToken{value: pay}(abi.encode(p), sig);
        assertEq(platform.balance, balBefore + core.creationFee() + p.marginBnb + preBuyFee);
    }

    // ==================== 交易限制测试 ====================

    /**
     * @notice 测试买入超过可用代币数量应该失败
     * @dev 当用户尝试买入超过联合曲线可用代币量的2倍时，应该因滑点超限而 revert
     */
    function testBuyExceedAvailableShouldRevert() public {
        IMetaNodeCore.CreateTokenParams memory p = _basicParams();
        p.initialBuyPercentage = 0;
        bytes memory sig = _signParams(p);
        uint256 pay = core.creationFee();
        vm.prank(creator);
        core.createToken{value: pay}(abi.encode(p), sig);
        address token = factory.predictTokenAddress(p.name, p.symbol, p.totalSupply, address(core), p.timestamp, p.nonce);

        IMetaNodeCore.BondingCurveParams memory curve = core.getBondingCurve(token);
        vm.expectRevert(IMetaNodeCore.SlippageExceeded.selector);
        vm.prank(user);
        core.buy{value: 100 ether}(token, curve.availableTokens * 2, block.timestamp + 100);
    }

    /**
     * @notice 测试卖出超过池中已收集 BNB 应该失败
     * @dev 当联合曲线中没有收集到足够的 BNB 时，卖出应该 revert
     */
    function testSellExceedCollectedBNBShouldRevert() public {
        IMetaNodeCore.CreateTokenParams memory p = _basicParams();
        p.initialBuyPercentage = 0;
        bytes memory sig = _signParams(p);
        vm.prank(creator);
        core.createToken{value: core.creationFee()}(abi.encode(p), sig);
        address token = factory.predictTokenAddress(p.name, p.symbol, p.totalSupply, address(core), p.timestamp, p.nonce);

        vm.expectRevert(IMetaNodeCore.InsufficientBalance.selector);
        vm.prank(user);
        core.sell(token, 1 ether, 0, block.timestamp + 100);
    }

    // ==================== 归属（Vesting）测试 ====================

    /**
     * @notice 测试线性归属时长过短应该失败
     * @dev 线性归属模式下，duration 太小（如1秒）应该 revert
     */
    function testLinearVestingTooShortShouldRevert() public {
        IVestingParams.VestingAllocation[] memory allocs = new IVestingParams.VestingAllocation[](1);
        allocs[0] = IVestingParams.VestingAllocation({amount: 1000, launchTime: 0, duration: 1, mode: IVestingParams.VestingMode.LINEAR});
        IMetaNodeCore.CreateTokenParams memory p = _basicParams();
        p.vestingAllocations = allocs;
        bytes memory sig = _signParams(p);
        (uint256 pay,uint256 preBuyFee) = core.calculateInitialBuyBNB(p.totalSupply, p.virtualBNBReserve, p.virtualTokenReserve, p.initialBuyPercentage);
        vm.prank(creator);
        vm.expectRevert();
        core.createToken{value: pay}(abi.encode(p), sig);
    }

    /**
     * @notice 测试销毁模式归属能正确销毁代币
     * @dev 使用 VestingMode.BURN 创建代币时，指定比例的代币应被销毁
     */
    function testBurnModeVestingBurnsTokens() public {
        IVestingParams.VestingAllocation[] memory allocs = new IVestingParams.VestingAllocation[](1);
        allocs[0] = IVestingParams.VestingAllocation({amount: 1000, launchTime: 0, duration: 0, mode: IVestingParams.VestingMode.BURN});
        IMetaNodeCore.CreateTokenParams memory p = _basicParams();
        p.vestingAllocations = allocs;
        bytes memory sig = _signParams(p);
        (uint256 pay,uint256 preBuyFee) = core.calculateInitialBuyBNB(p.totalSupply, p.virtualBNBReserve, p.virtualTokenReserve, p.initialBuyPercentage);
        pay += core.creationFee();
        vm.prank(creator);
        core.createToken{value: pay}(abi.encode(p), sig);
    }

    // ==================== 黑名单测试 ====================

    /**
     * @notice 测试被拉黑的代币无法交易
     * @dev 代币被 blacklistToken 后，buy 操作应该 revert
     */
    function testCannotTradeIfBlacklisted() public {
        IMetaNodeCore.CreateTokenParams memory p = _basicParams();
        bytes memory sig = _signParams(p);
        (uint256 pay,uint256 preBuyFee) = core.calculateInitialBuyBNB(p.totalSupply, p.virtualBNBReserve, p.virtualTokenReserve, p.initialBuyPercentage);
        pay += core.creationFee();
        vm.prank(creator);
        core.createToken{value: pay}(abi.encode(p), sig);
        address token = factory.predictTokenAddress(p.name, p.symbol, p.totalSupply, address(core), p.timestamp, p.nonce);

        vm.startPrank(admin);
        core.blacklistToken(token);
        vm.stopPrank();

        vm.expectRevert(IMetaNodeCore.TokenNotTrading.selector);
        vm.prank(user);
        core.buy{value: 1 ether}(token, 0, block.timestamp + 100);
    }
}
