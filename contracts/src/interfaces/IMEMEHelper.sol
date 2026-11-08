// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IMEMECore.sol";

/**
 * @title IMEMEHelper
 * @notice 曲线计算与 DEX 集成助手接口
 * 
 * ============ 主要职责 ============
 * 1. 联合曲线数学计算（买入/卖出/价格）
 * 2. PancakeSwap V2 流动性操作
 * 3. 交易对地址预测
 * 
 * ============ 恒定乘积公式 ============
 * k = x × y（始终不变）
 * 
 * 买入 dy 代币需要支付 dx BNB：
 * (x + dx) × (y - dy) = k
 * dx = k / (y - dy) - x
 * 
 * 卖出 dy 代币可获得 dx BNB：
 * (x - dx) × (y + dy) = k
 * dx = x - k / (y + dy)
 */
interface IMEMEHelper {
    /// @notice 曲线参数无效
    error InvalidCurve();
    /// @notice 流动性不足
    error InsufficientLiquidity();
    /// @notice 金额为零
    error ZeroAmount();
    /// @notice 零地址
    error ZeroAddress();

    /**
     * @notice 计算买入可获得的代币数量
     * @param bnbIn 输入的 BNB 数量（wei）
     * @param curve 当前曲线参数
     * @return 可获得的代币数量（wei）
     * 
     * 计算公式：
     * newBNBReserve = virtualBNBReserve + bnbIn
     * newTokenReserve = k / newBNBReserve
     * tokenOut = virtualTokenReserve - newTokenReserve
     */
    function calculateTokenAmountOut(uint256 bnbIn, IMEMECore.BondingCurveParams memory curve) external pure returns (uint256);

    /**
     * @notice 计算购买指定数量代币需要的 BNB
     * @param tokenOut 期望获得的代币数量
     * @param curve 当前曲线参数
     * @return 需要支付的 BNB 数量
     * 
     * 计算公式（反向）：
     * newTokenReserve = virtualTokenReserve - tokenOut
     * newBNBReserve = k / newTokenReserve
     * bnbIn = newBNBReserve - virtualBNBReserve
     */
    function calculateRequiredBNB(uint256 tokenOut, IMEMECore.BondingCurveParams memory curve) external pure returns (uint256);

    /**
     * @notice 计算买入（含手续费明细）
     * @param bnbIn 输入的 BNB 数量
     * @param curve 当前曲线参数
     * @param feeRate 手续费率（基点，如 100 = 1%）
     * @return tokenOut 可获得的代币数量
     * @return netBNB 扣除手续费后的 BNB
     * @return feeBNB 手续费
     */
    function calculateTokenAmountOutWithFee(uint256 bnbIn, IMEMECore.BondingCurveParams memory curve, uint256 feeRate) external pure returns (uint256 tokenOut, uint256 netBNB, uint256 feeBNB);

    /**
     * @notice 计算卖出可获得的 BNB
     * @param tokenIn 输入的代币数量
     * @param curve 当前曲线参数
     * @return 可获得的 BNB 数量
     * 
     * 计算公式：
     * newTokenReserve = virtualTokenReserve + tokenIn
     * newBNBReserve = k / newTokenReserve
     * bnbOut = virtualBNBReserve - newBNBReserve
     */
    function calculateBNBAmountOut(uint256 tokenIn, IMEMECore.BondingCurveParams memory curve) external pure returns (uint256);

    /**
     * @notice 计算卖出（含手续费明细）
     * @param tokenIn 输入的代币数量
     * @param curve 当前曲线参数
     * @param feeRate 手续费率（基点）
     * @return netBNB 扣除手续费后可获得的 BNB
     * @return feeBNB 手续费
     */
    function calculateBNBAmountOutWithFee(uint256 tokenIn, IMEMECore.BondingCurveParams memory curve, uint256 feeRate) external pure returns (uint256 netBNB, uint256 feeBNB);

    /**
     * @notice 添加 PancakeSwap V2 流动性
     * @dev 毕业时由 MEMECore 调用
     * @param token 代币地址
     * @param bnbAmount 添加的 BNB 数量
     * @param tokenAmount 添加的代币数量
     * @return liquidity 获得的 LP 代币数量
     * 
     * 流程：
     * 1. 从调用者转入代币
     * 2. 授权路由合约
     * 3. 调用 addLiquidityETH
     * 4. LP 代币发送到死地址（永久锁定）
     */
    function addLiquidityV2(address token, uint256 bnbAmount, uint256 tokenAmount) external payable returns (uint256 liquidity);

    /**
     * @notice 获取当前代币价格
     * @param curve 曲线参数
     * @return 价格（BNB/Token × 1e18）
     * 
     * price = virtualBNBReserve × 1e18 / virtualTokenReserve
     */
    function getPrice(IMEMECore.BondingCurveParams memory curve) external pure returns (uint256);

    /**
     * @notice 获取/预测交易对地址
     * @param token 代币地址
     * @return 交易对合约地址
     * 
     * 如果交易对已存在，直接返回；
     * 否则使用 CREATE2 公式预测
     */
    function getPairAddress(address token) external view returns (address);
}
