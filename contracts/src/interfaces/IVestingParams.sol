// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IVestingParams
 * @notice 代币归属（锁仓释放）参数接口
 * 
 * ============ 什么是代币归属？============
 * 归属（Vesting）是一种代币锁定机制：
 * - 代币在一段时间内逐步解锁
 * - 防止创建者立即抛售全部代币
 * - 保护普通投资者利益
 * 
 * ============ 本项目的归属场景 ============
 * 当创建者在发币时选择"初始买入"，可配置归属计划：
 * 1. BURN：直接销毁，减少总供应量
 * 2. CLIFF：悬崖期，到期后一次性解锁
 * 3. LINEAR：线性释放，按时间比例逐步解锁
 */
interface IVestingParams {
    /**
     * @notice 归属模式枚举
     * @dev 决定代币如何释放给受益人
     */
    enum VestingMode {
        /**
         * @notice 销毁模式
         * @dev 代币被永久销毁，不会释放给任何人
         * 用途：通缩机制，减少流通供应
         */
        BURN,

        /**
         * @notice 悬崖模式
         * @dev 在归属期结束前完全锁定，到期后一次性全部解锁
         * 用途：确保创建者长期持有
         */
        CLIFF,

        /**
         * @notice 线性模式
         * @dev 从开始到结束，按时间比例逐步解锁
         * 例如：锁定100代币，期限100天，则每天可领取1代币
         * 用途：平滑释放，减少市场冲击
         */
        LINEAR
    }

    /**
     * @notice 归属分配结构体
     * @dev 在创建代币时传入，定义初始买入代币的锁仓规则
     */
    struct VestingAllocation {
        /**
         * @notice 分配数量（基点，1/10000）
         * @dev 例如：500 表示初始买入量的 5%
         * 实际代币数 = totalSupply × initialBuyPercentage × amount / 10000 / 10000
         */
        uint256 amount;

        /**
         * @notice 归属起始时间（Unix 时间戳）
         * @dev 0 表示使用代币创建时间
         * 可设置为 launchTime 以对齐开盘时间
         */
        uint256 launchTime;

        /**
         * @notice 归属期限（秒）
         * @dev 从 launchTime 开始计算
         * 例如：86400 = 1天，2592000 = 30天
         * LINEAR 模式必须 > 0
         */
        uint256 duration;

        /**
         * @notice 归属模式
         * @dev BURN / CLIFF / LINEAR
         */
        VestingMode mode;
    }
}
