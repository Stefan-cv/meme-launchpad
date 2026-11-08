// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVestingParams} from "./IVestingParams.sol";

/**
 * @title IMEMEVesting
 * @notice 代币归属（锁仓释放）合约接口
 * 
 * ============ 归属合约用途 ============
 * 当创建者在发币时进行"初始买入"，可以选择将部分代币锁定：
 * - 防止创建者立即抛售（Rug Pull）
 * - 增强项目可信度
 * - 支持多种释放模式
 * 
 * ============ 归属模式说明 ============
 * 
 * 【BURN 销毁模式】
 * 代币被永久销毁，减少总供应量
 * 用于通缩机制，提升剩余代币价值
 * 
 * 【CLIFF 悬崖模式】
 * |------ 锁定期 ------|全部解锁
 * 到期前：0 可领取
 * 到期后：100% 可领取
 * 
 * 【LINEAR 线性模式】
 * |------ 释放期 ------|
 * 按时间比例逐步释放
 * 例如：30天释放期，第15天可领取50%
 * 
 * ============ 存储结构 ============
 * token → beneficiary → scheduleId → VestingSchedule
 * 每个用户可以有多个归属计划
 */
interface IMEMEVesting is IVestingParams {
    // ============ 错误定义 ============

    /// @notice 参数无效
    error InvalidParameters();
    /// @notice 地址参数无效
    error InvalidAddressParameters();
    /// @notice 数组长度无效
    error InvalidLengthParameters();
    /// @notice 金额参数无效
    error InvalidAmountParameters();
    /// @notice 无可领取金额
    error NoClaimableAmount();
    /// @notice 归属计划不存在
    error ScheduleNotFound();
    /// @notice 归属计划已撤销
    error ScheduleRevoked();
    /// @notice 余额不足
    error InsufficientBalance();
    /// @notice 未授权
    error Unauthorized();
    /// @notice 百分比无效
    error InvalidPercentage();

    // ============ 数据结构 ============

    /**
     * @notice 归属计划详情
     * @dev 每个归属计划独立存储
     */
    struct VestingSchedule {
        /// @notice 锁定的代币总量
        uint256 totalAmount;
        /// @notice 归属开始时间（通常=代币创建时间或 launchTime）
        uint256 startTime;
        /// @notice 归属结束时间（startTime + duration）
        uint256 endTime;
        /// @notice 已领取的代币数量
        uint256 claimedAmount;
        /// @notice 是否已被撤销
        bool revoked;
        /// @notice 归属模式（BURN/CLIFF/LINEAR）
        VestingMode mode;
    }

    // ============ 事件定义 ============

    /// @notice 归属计划创建事件
    event VestingScheduleCreated(
        address indexed token,      // 代币地址
        address indexed beneficiary,// 受益人地址
        uint256 scheduleId,         // 计划ID
        uint256 amount,             // 锁定数量
        uint256 startTime,          // 开始时间
        uint256 endTime             // 结束时间
    );

    /// @notice 代币领取事件
    event TokensClaimed(
        address indexed token,      // 代币地址
        address indexed beneficiary,// 受益人地址
        uint256 scheduleId,         // 计划ID
        uint256 amount              // 领取数量
    );

    /// @notice 归属计划撤销事件
    event VestingScheduleRevoked(
        address indexed token,
        address indexed beneficiary,
        uint256 scheduleId,
        uint256 remainingAmount     // 返还给管理员的剩余代币
    );

    /// @notice 紧急提取事件
    event EmergencyWithdraw(
        address indexed token,
        address indexed beneficiary,
        uint256 amount
    );

    // ============ 核心函数 ============

    /**
     * @notice 批量创建归属计划
     * @dev 仅限 OPERATOR_ROLE（MEMECore）调用
     * @param token 代币地址
     * @param beneficiary 受益人地址
     * @param allocations 归属分配数组
     * @return scheduleIds 创建的计划ID数组
     * 
     * 流程：
     * 1. 校验参数
     * 2. 从调用者转入代币
     * 3. 逐个创建归属计划
     * 4. 记录统计信息
     */
    function createVestingSchedules(address token, address beneficiary, VestingAllocation[] calldata allocations) external returns (uint256[] memory scheduleIds);

    /**
     * @notice 领取单个计划的可用代币
     * @param token 代币地址
     * @param scheduleId 计划ID
     * @return claimableAmount 实际领取的数量
     * 
     * 可领取数量计算：
     * - BURN: 始终为 0
     * - CLIFF: 未到期=0，到期后=totalAmount-claimedAmount
     * - LINEAR: (已过时间/总时长) × totalAmount - claimedAmount
     */
    function claim(address token, uint256 scheduleId) external returns (uint256 claimableAmount);

    /**
     * @notice 领取所有计划的可用代币
     * @param token 代币地址
     * @return totalClaimed 总领取数量
     */
    function claimAll(address token) external returns (uint256 totalClaimed);

    // ============ 查询函数 ============

    /**
     * @notice 获取归属计划详情
     */
    function getVestingSchedule(address token, address beneficiary, uint256 scheduleId) external view returns (VestingSchedule memory);

    /**
     * @notice 获取用户的归属计划数量
     */
    function getVestingScheduleCount(address token, address beneficiary) external view returns (uint256);

    /**
     * @notice 获取单个计划的可领取数量
     */
    function getClaimableAmount(address token, address beneficiary, uint256 scheduleId) external view returns (uint256);

    /**
     * @notice 获取所有计划的可领取总量
     */
    function getTotalClaimableAmount(address token, address beneficiary) external view returns (uint256);

    /**
     * @notice 获取归属统计信息
     * @return vested 已解锁数量
     * @return claimed 已领取数量
     * @return locked 仍锁定数量
     */
    function getTotalVestedAmount(address token, address beneficiary) external view returns (uint256 vested, uint256 claimed, uint256 locked);

    // ============ 管理函数 ============

    /**
     * @notice 撤销归属计划（管理员）
     * @dev 先将已解锁部分发给受益人，剩余返还管理员
     */
    function revokeVestingSchedule(address token, address beneficiary, uint256 scheduleId) external;

    /**
     * @notice 紧急提取（管理员）
     */
    function emergencyWithdrawToken(address token, uint256 amount) external;
}
