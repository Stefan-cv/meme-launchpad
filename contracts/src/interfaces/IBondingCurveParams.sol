// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IBondingCurveParams
 * @notice 联合曲线（Bonding Curve）参数接口
 * 
 * ============ 什么是联合曲线？============
 * 联合曲线是一种自动做市机制，价格由数学公式决定：
 * - 买入越多，价格越高（供应减少）
 * - 卖出越多，价格越低（供应增加）
 * 
 * 本项目使用恒定乘积公式：k = x * y
 * 其中 x 为 BNB 储备，y 为代币储备，k 为常数
 * 
 * ============ 虚拟储备的作用 ============
 * "虚拟"储备并非真实存在的资产，而是用于：
 * 1. 设定初始价格：price = virtualBNB / virtualToken
 * 2. 控制价格曲线的陡峭程度
 * 3. 避免极端价格波动
 * 
 * 例如：virtualBNB=10, virtualToken=1000000
 * 初始价格 = 10/1000000 = 0.00001 BNB/Token
 */
interface IBondingCurveParams {
    /**
     * @notice 联合曲线参数结构体
     * @dev 每个代币都有独立的曲线参数，存储在 MEMECore 中
     */
    struct BondingCurveParams {
        /**
         * @notice 虚拟 BNB 储备量（wei）
         * @dev 用于价格计算，随买入增加、卖出减少
         * 初始值由创建者设定，决定起始价格
         */
        uint256 virtualBNBReserve;

        /**
         * @notice 虚拟代币储备量（wei，18位精度）
         * @dev 用于价格计算，随买入减少、卖出增加
         * 初始值通常等于 saleAmount（可售代币总量）
         */
        uint256 virtualTokenReserve;

        /**
         * @notice 恒定乘积 k = virtualBNBReserve × virtualTokenReserve
         * @dev 在曲线生命周期内保持不变
         * 买入/卖出时：新BNB储备 × 新代币储备 = k
         * 该值在代币创建时计算并固定
         */
        uint256 k;

        /**
         * @notice 剩余可售代币数量（wei）
         * @dev 实际可供购买的代币余量
         * - 买入时减少
         * - 卖出时增加（用户退回代币）
         * - 低于阈值（MIN_LIQUIDITY）时触发毕业
         */
        uint256 availableTokens;

        /**
         * @notice 已收集的真实 BNB 数量（wei）
         * @dev 用户买入时累积，卖出时扣减
         * 毕业时用于添加 DEX 流动性
         * 注意：这是真实资产，非虚拟值
         */
        uint256 collectedBNB;
    }
}
