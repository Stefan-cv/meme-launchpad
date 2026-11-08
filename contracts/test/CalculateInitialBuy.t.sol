// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title CalculateInitialBuyTest
 * @notice 初始买入计算函数测试
 * @dev 测试 calculateInitialBuyBNB 函数的正确性
 *
 * 联合曲线计算公式：
 * - k = virtualBNBReserve * virtualTokenReserve (恒定乘积)
 * - 买入 tokenAmount 代币需要的 BNB：
 *   newTokenReserve = virtualTokenReserve - tokenAmount
 *   newBNBReserve = k / newTokenReserve
 *   bnbRequired = newBNBReserve - virtualBNBReserve
 *
 * 测试覆盖场景：
 * 1. 0% 初始买入 - 应返回0
 * 2. 10% 初始买入 - 验证计算准确性
 * 3. 50% 初始买入 - 验证中等比例计算
 * 4. 99.9% 初始买入 - 验证最大比例计算
 * 5. 不同虚拟储备配置 - 验证公式通用性
 * 6. 无效百分比 - 超过99.9%应该revert
 * 7. Gas效率 - 确保是view函数
 * 8. 模糊测试 - 随机百分比的边界测试
 */
import "forge-std/Test.sol";
import "../src/MEMECore.sol";
import "../src/MEMEFactory.sol";
import "../src/MEMEHelper.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockPancakeRouter} from "./mocks/MockPancakeRouter.sol";
import {MockWBNB} from "./mocks/MockWBNB.sol";

contract CalculateInitialBuyTest is Test {
    MetaNodeCore public core;

    function setUp() public {
        MockWBNB wbnb = new MockWBNB();
        MockPancakeRouter router = new MockPancakeRouter(address(wbnb));
        // Deploy minimal setup for testing the calculation function
        MEMEFactory factory = new MEMEFactory(address(this));
        MEMEHelper helper = new MEMEHelper(address(this), address(router), address(wbnb));

        MetaNodeCore coreImpl = new MetaNodeCore();
        bytes memory coreInitData = abi.encodeWithSelector(
            MetaNodeCore.initialize.selector,
            address(factory),
            address(helper),
            address(this),
            address(this),
            address(this),
            address(this),
            address(this)
        );
        ERC1967Proxy coreProxy = new ERC1967Proxy(address(coreImpl), coreInitData);
        core = MetaNodeCore(payable(address(coreProxy)));
    }

    function testCalculateInitialBuyBNB() public view {
        // Test case 1: 0% should return 0
        (uint256 bnbRequired,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            800000 ether,  // saleAmount
            1 ether,         // virtualBNBReserve
            800000 ether,  // virtualTokenReserve
            0                // 0%
        );
        assertEq(bnbRequired, 0);

        // Test case 2: 10% initial buy
        (bnbRequired, preBuyFee) = core.calculateInitialBuyBNB(
            800000 ether,
            1 ether,
            800000 ether,
            1000  // 10%
        );

        // Calculate expected: 10% of 800000 = 80000 tokens
        // k = 1 ether * 800000 ether = 800000 * 1e36
        // newTokenReserve = (800000 - 80000) ether = 720000 ether
        // newBNBReserve = k / newTokenReserve = (800000 * 1e36) / (720000 ether) = 1.111... ether
        // bnbRequired = 1.111... - 1 = 0.111... ether
        uint256 k = 1 ether * 800000 ether;
        uint256 newTokenReserve = 720000 ether;
        uint256 baseBNB = k / newTokenReserve - 1 ether;

        uint256 preBuyFeeRate = core.preBuyFeeRate();
        uint256 preBuyFeeVal = (baseBNB * preBuyFeeRate) / 10000;
        uint256 expectedBNB = baseBNB + preBuyFeeVal;
        assertApproxEqRel(bnbRequired, expectedBNB, 0.001e18); // 0.1% tolerance

        // Test case 3: 50% initial buy
        uint256 virtualBNBReserve = 1 ether;
        (bnbRequired, preBuyFee) = core.calculateInitialBuyBNB(
            800000 ether,
            virtualBNBReserve,
            800000 ether,
            5000  // 50%
        );

        // 50% of 800000 = 400000 tokens
        // newTokenReserve = 400000
        // newBNBReserve = 800000 / 400000 = 2
        // bnbRequired = 2 - 1 = 1
        virtualBNBReserve += virtualBNBReserve * core.preBuyFeeRate() / 10000;
        assertEq(bnbRequired, virtualBNBReserve);

        // Test case 4: 99.9% initial buy
        (bnbRequired, preBuyFee) = core.calculateInitialBuyBNB(
            800000 ether,
            1 ether,
            800000 ether,
            9990  // 99.9%
        );

        k = 1 ether * 800000 ether;
        newTokenReserve = (800000 ether * 10) / 10000;
        baseBNB = k / newTokenReserve - 1 ether;

        preBuyFeeVal = (baseBNB * preBuyFeeRate) / 10000;
        uint256 expectedTotal = baseBNB + preBuyFeeVal;

        assertEq(bnbRequired, expectedTotal);
    }

    function testCalculateWithDifferentReserves() public view {
        // Test with different virtual reserves
        (uint256 bnbRequired,uint256 preBuyFee) = core.calculateInitialBuyBNB(
            1000000 ether,  // saleAmount
            5 ether,          // virtualBNBReserve
            1000000 ether,  // virtualTokenReserve
            2500              // 25%
        );

        // 25% of 1000000 = 250000 tokens
        // k = 5 * 1000000 = 5000000
        // newTokenReserve = 750000
        // newBNBReserve = 5000000 / 750000 = 6.666...
        // bnbRequired = 6.666... - 5 = 1.666...
        uint256 k = 5 ether * 1000000;
        uint256 newTokenReserve = 750000;
        uint256 baseBNB = (k * 1e18) / (newTokenReserve * 1e18) - 5 ether;

        uint256 preBuyFeeRate = core.preBuyFeeRate();
        uint256 preBuyFeeVal = (baseBNB * preBuyFeeRate) / 10000;
        uint256 expectedBNB = baseBNB + preBuyFeeVal;
        assertApproxEqRel(bnbRequired, expectedBNB, 0.001e18);
    }

    function testRevertOnInvalidPercentage() public {
        // Should revert on > 99.9%
        vm.expectRevert(IMetaNodeCore.InvalidParameters.selector);
        core.calculateInitialBuyBNB(
            800000 ether,
            1 ether,
            800000 ether,
            10000  // 100%
        );

        vm.expectRevert(IMetaNodeCore.InvalidParameters.selector);
        core.calculateInitialBuyBNB(
            800000 ether,
            1 ether,
            800000 ether,
            9991  // 99.91%
        );
    }

    function testGasEfficiency() public view {
        // Test that the function is gas efficient (should be view/pure)
        uint256 virtualBNBReserve = 1 ether;
        (uint256 result,uint256 preBuyFee)= core.calculateInitialBuyBNB(
            800000 ether,
            virtualBNBReserve,
            800000 ether,
            5000
        );

        // Just verify it returns a reasonable value
        // The fact that this is a view function proves it's gas efficient
        uint256 preBuyFeeRate = core.preBuyFeeRate();
        virtualBNBReserve += virtualBNBReserve * preBuyFeeRate / 10000;
        assertEq(result, virtualBNBReserve);
    }

    // Fuzz testing for various percentages
    function testFuzzCalculateInitialBuy(uint256 percentageBP) public view {
        // Bound percentage to valid range
        percentageBP = bound(percentageBP, 0, 9990);

        uint256 saleAmount = 1000000 ether;
        uint256 virtualBNBReserve = 1 ether;
        uint256 virtualTokenReserve = 1000000 ether;

        (uint256 bnbRequired,uint256 preBuyFee)= core.calculateInitialBuyBNB(
            saleAmount,
            virtualBNBReserve,
            virtualTokenReserve,
            percentageBP
        );

        if (percentageBP == 0) {
            assertEq(bnbRequired, 0);
        } else {
            // BNB required should be positive
            assertGt(bnbRequired, 0);

            // Higher percentage should require more BNB
            if (percentageBP < 9990) {
                (uint256 higherBNB,uint256 preBuyFeeVal) = core.calculateInitialBuyBNB(
                    saleAmount,
                    virtualBNBReserve,
                    virtualTokenReserve,
                    percentageBP + 1
                );
                assertGt(higherBNB, bnbRequired);
            }
        }
    }
}