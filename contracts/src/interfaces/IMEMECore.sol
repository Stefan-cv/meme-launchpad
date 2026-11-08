// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IVestingParams} from "./IVestingParams.sol";
import {IBondingCurveParams} from "./IBondingCurveParams.sol";

/**
 * @title IMEMECore
 * @notice MEME 发射器核心合约接口
 * 
 * ============ 项目整体架构 ============
 * 
 *                    ┌─────────────────┐
 *                    │   MEMECore      │  ← 核心业务逻辑（本接口）
 *                    │  (可升级代理)    │
 *                    └────────┬────────┘
 *                             │
 *        ┌────────────────────┼────────────────────┐
 *        │                    │                    │
 *        ▼                    ▼                    ▼
 * ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
 * │ MEMEFactory │     │ MEMEHelper  │     │ MEMEVesting │
 * │ (代币工厂)  │     │ (曲线计算)  │     │ (锁仓释放)  │
 * └─────────────┘     └─────────────┘     └─────────────┘
 *        │
 *        ▼
 * ┌─────────────┐
 * │ MetaNodeToken│  ← 每次发币创建的 ERC20 代币
 * └─────────────┘
 * 
 * ============ 代币生命周期 ============
 * 
 * 1. NOT_CREATED → 代币尚未创建
 * 2. TRADING     → 交易中（用户可买卖）
 * 3. PENDING_GRADUATION → 待毕业（可售量低于阈值）
 * 4. GRADUATED   → 已毕业（流动性已添加到 DEX）
 * 
 * 特殊状态：
 * - PAUSED      → 暂停交易（可恢复）
 * - BLACKLISTED → 黑名单（紧急情况）
 * 
 * ============ 主要业务流程 ============
 * 
 * 【发币流程】
 * 1. 前端生成参数 → 后端签名 → 用户调用 createToken
 * 2. 合约验证签名、扣除费用
 * 3. 工厂部署代币、初始化曲线
 * 4. （可选）执行初始买入、创建归属计划
 * 
 * 【买入流程】
 * 用户支付 BNB → 扣除手续费 → 按曲线计算代币量 → 转移代币
 * 
 * 【卖出流程】
 * 用户转入代币 → 按曲线计算 BNB → 扣除手续费 → 转移 BNB
 * 
 * 【毕业流程】
 * 可售量 < 阈值 → 管理员触发毕业 → 添加 DEX 流动性 → 开放自由交易
 */
interface IMEMECore is IVestingParams, IBondingCurveParams {

    // ============ 代币状态枚举 ============

    /**
     * @notice 代币生命周期状态
     */
    enum TokenStatus {
        NOT_CREATED,        // 0: 未创建（默认值）
        TRADING,            // 1: 交易中（正常买卖）
        PENDING_GRADUATION, // 2: 待毕业（等待添加流动性）
        GRADUATED,          // 3: 已毕业（在 DEX 自由交易）
        PAUSED,             // 4: 已暂停（临时停止交易）
        BLACKLISTED         // 5: 黑名单（紧急冻结）
    }

    // ============ 错误定义 ============

    /// @notice 签名验证失败
    error InvalidSigner();
    /// @notice 请求已过期（超过 REQUEST_EXPIRY）
    error RequestExpired();
    /// @notice 请求已被处理（防重放）
    error RequestAlreadyProcessed();
    /// @notice 支付金额不足
    error InsufficientFee();
    /// @notice 交易对地址无效
    error InvalidPair();
    /// @notice 代币非交易状态
    error TokenNotTrading();
    /// @notice 代币尚未开盘（launchTime 未到）
    error TokenNotLaunchedYet();
    /// @notice 滑点超出限制
    error SlippageExceeded();
    /// @notice 无效状态
    error InvalidStatus();
    /// @notice 未授权操作
    error Unauthorized();
    /// @notice 创建者参数无效
    error InvalidCreatorParameters();
    /// @notice 金额参数无效
    error InvalidAmountParameters();
    /// @notice 时长参数无效
    error InvalidDurationParameters();
    /// @notice 归属参数无效
    error InvalidVestingParameters();
    /// @notice 通用参数无效
    error InvalidParameters();
    /// @notice 销售参数无效
    error InvalidSaleParameters();
    /// @notice 初始买入百分比无效
    error InvalidInitialBuyPercentage();
    /// @notice 交易已过期（deadline）
    error TransactionExpired();
    /// @notice 原生币金额无效
    error InvalidNativeAmount();
    /// @notice 余额不足
    error InsufficientBalance();
    /// @notice 保证金不足
    error InsufficientMargin();
    /// @notice 保证金接收地址未设置
    error MarginReceiverNotSet();
    /// @notice 百分比基点无效
    error InvalidPercentageBP();
    /// @notice 非暂停状态
    error InvalidPausedStatus();
    /// @notice 非黑名单状态
    error InvalidBlackListedStatus();
    /// @notice 零地址
    error ZeroAddress();

    // ============ 数据结构 ============

    /**
     * @notice 代币基础信息
     * @dev 创建后不可变（除 status）
     */
    struct TokenInfo {
        /// @notice 创建者地址（接收毕业创作者奖励）
        address creator;
        /// @notice 创建时间戳
        uint256 createdAt;
        /// @notice 开盘时间（0 表示立即开盘）
        uint256 launchTime;
        /// @notice 当前状态
        TokenStatus status;
        /// @notice 预计算的 DEX 交易对地址
        address liquidityPool;
    }

    /**
     * @notice 创建代币参数
     * @dev 由前端构造、后端签名、用户提交
     */
    struct CreateTokenParams {
        /// @notice 代币名称（如 "Doge Coin"）
        string name;
        /// @notice 代币符号（如 "DOGE"）
        string symbol;
        /// @notice 代币总供应量（包含18位小数）
        uint256 totalSupply;
        /// @notice 可售数量（进入曲线的代币量）
        uint256 saleAmount;
        /// @notice 初始虚拟 BNB 储备（决定起始价格）
        uint256 virtualBNBReserve;
        /// @notice 初始虚拟代币储备（通常等于 saleAmount）
        uint256 virtualTokenReserve;
        /// @notice 开盘时间戳（0=立即，未来时间=延迟开盘）
        uint256 launchTime;
        /// @notice 创建者地址（接收奖励、初始买入代币）
        address creator;
        /// @notice 请求时间戳（用于签名和过期校验）
        uint256 timestamp;
        /// @notice 请求唯一标识（防重放攻击）
        bytes32 requestId;
        /// @notice 随机数（用于 CREATE2 地址计算）
        uint256 nonce;
        /// @notice 初始买入百分比（基点，0-9990，如 1000=10%）
        uint256 initialBuyPercentage;
        /// @notice 保证金数量（wei，0=无保证金）
        uint256 marginBnb;
        /// @notice 保证金锁定期（秒）
        uint256 marginTime;
        /// @notice 初始买入代币的归属计划
        VestingAllocation[] vestingAllocations;
    }

    // ============ 事件定义 ============

    /// @notice 代币创建事件
    event TokenCreated(
        address indexed token,      // 代币合约地址
        address indexed creator,    // 创建者地址
        string name,                // 代币名称
        string symbol,              // 代币符号
        uint256 totalSupply,        // 总供应量
        bytes32 requestId           // 请求ID
    );

    /// @notice 买入事件
    event TokenBought(
        address indexed token,      // 代币地址
        address indexed buyer,      // 买家地址
        uint256 bnbAmount,          // 支付的 BNB（扣费后）
        uint256 tokenAmount,        // 获得的代币数量
        uint256 tradingFee,         // 交易手续费
        uint256 virtualBNBReserve,  // 更新后的虚拟 BNB 储备
        uint256 virtualTokenReserve,// 更新后的虚拟代币储备
        uint256 availableTokens,    // 剩余可售代币
        uint256 collectedBNB        // 累计收集的 BNB
    );

    /// @notice 卖出事件
    event TokenSold(
        address indexed token,      // 代币地址
        address indexed seller,     // 卖家地址
        uint256 tokenAmount,        // 卖出的代币数量
        uint256 bnbAmount,          // 获得的 BNB（扣费后）
        uint256 tradingFee,         // 交易手续费
        uint256 virtualBNBReserve,  // 更新后的虚拟 BNB 储备
        uint256 virtualTokenReserve,// 更新后的虚拟代币储备
        uint256 availableTokens,    // 剩余可售代币
        uint256 collectedBNB        // 累计收集的 BNB
    );

    /// @notice 毕业事件（添加 DEX 流动性）
    event TokenGraduated(
        address indexed token,      // 代币地址
        uint256 liquidityBNB,       // 添加的 BNB 流动性
        uint256 liquidityTokens,    // 添加的代币流动性
        uint256 liquidityResult     // 获得的 LP 代币数量
    );

    /// @notice 状态变更事件
    event TokenStatusChanged(
        address indexed token,
        TokenStatus oldStatus,
        TokenStatus newStatus
    );

    /// @notice 代币暂停事件
    event TokenPaused(address indexed token);
    /// @notice 代币恢复事件
    event TokenUnpaused(address indexed token);
    /// @notice 代币拉黑事件
    event TokenBlacklisted(address indexed token);
    /// @notice 代币解除黑名单事件
    event TokenRemovedFromBlacklist(address indexed token);
    /// @notice 创作者费用重定向事件（接收失败时）
    event CreatorFeeRedirected(address indexed to, address indexed platformFeeReceiver, uint256 amount);
    /// @notice 平台费接收地址变更
    event PlatformFeeReceiverChanged(address indexed oldReceiver, address indexed newReceiver);
    /// @notice 毕业费接收地址变更
    event GraduateFeeReceiverChanged(address indexed oldReceiver, address indexed newReceiver);
    /// @notice 工厂合约变更
    event FactoryChanged(address indexed oldFactory, address indexed newFactory);
    /// @notice 助手合约变更
    event HelperChanged(address indexed oldHelper, address indexed newHelper);
    /// @notice 归属合约变更
    event VestingChanged(address indexed oldVesting, address indexed newVesting);
    /// @notice 保证金接收地址变更
    event MarginReceiverChanged(address indexed oldMarginReceiver, address indexed newMarginReceiver);
    /// @notice 创建费变更
    event CreationFeeChanged(uint256 creationFee);
    /// @notice 初始买入费率变更
    event PreBuyFeeRateChanged(uint256 preBuyFeeRate);
    /// @notice 交易费率变更
    event TradingFeeRateChanged(uint256 tradingFeeRate);
    /// @notice 毕业费率变更
    event GraduationFeeRatesChanged(uint256 platformRate, uint256 creatorRate);
    /// @notice 最小锁仓时间变更
    event MinLockTimeChanged(uint256 minLockTime);

    /// @notice 带初始买入的代币创建事件
    event TokenCreatedWithInitialBuy(
        address indexed token,
        address indexed creator,
        uint256 initialTokensPurchased,  // 初始购买的代币数量
        uint256 initialBNBSpent,         // 初始购买花费的 BNB
        uint256 actualPercentage         // 实际购买百分比
    );

    /// @notice 保证金存入事件
    event MarginDeposited(
        address indexed token,
        address indexed creator,
        uint256 marginAmount,            // 保证金金额
        uint256 lockTime                 // 锁定时间
    );

    /// @notice 归属计划创建事件
    event VestingCreated(
        address indexed token,
        address indexed beneficiary,
        uint256 totalVestedAmount,       // 总归属数量
        uint256 scheduleCount            // 归属计划数量
    );

    /// @notice 代币销毁事件
    event MetaNodeTokensBurned(address indexed token, uint256 amount);

    // ============ 核心函数 ============

    /**
     * @notice 创建新代币
     * @param data ABI 编码的 CreateTokenParams
     * @param signature 后端签名
     * @return 新部署的代币地址
     */
    function createToken(bytes calldata data, bytes calldata signature) external payable returns (address);

    /**
     * @notice 从曲线买入代币
     * @param token 代币地址
     * @param minTokenAmount 最小获得数量（滑点保护）
     * @param deadline 交易截止时间
     */
    function buy(address token, uint256 minTokenAmount, uint256 deadline) external payable;

    /**
     * @notice 向曲线卖出代币
     * @param token 代币地址
     * @param tokenAmount 卖出数量
     * @param minBNBAmount 最小获得 BNB（滑点保护）
     * @param deadline 交易截止时间
     */
    function sell(address token, uint256 tokenAmount, uint256 minBNBAmount, uint256 deadline) external;

    /**
     * @notice 毕业代币（添加 DEX 流动性）
     * @param token 代币地址
     */
    function graduateToken(address token) external;

    /**
     * @notice 暂停代币交易
     * @param token 代币地址
     */
    function pauseToken(address token) external;

    /**
     * @notice 拉黑代币
     * @param token 代币地址
     */
    function blacklistToken(address token) external;

    // ============ 查询函数 ============

    /**
     * @notice 获取代币基础信息
     */
    function getTokenInfo(address token) external view returns (TokenInfo memory);

    /**
     * @notice 获取曲线参数
     */
    function getBondingCurve(address token) external view returns (BondingCurveParams memory);

    /**
     * @notice 计算买入可获得的代币数量（不含手续费）
     */
    function calculateBuyAmount(address token, uint256 bnbAmount) external view returns (uint256);

    /**
     * @notice 计算买入可获得的代币数量（含手续费明细）
     */
    function calculateBuyAmountWithFee(address token, uint256 bnbAmount) external view returns (uint256 tokenOut, uint256 netBNB, uint256 feeBNB);

    /**
     * @notice 计算卖出可获得的 BNB（不含手续费）
     */
    function calculateSellReturn(address token, uint256 tokenAmount) external view returns (uint256);

    /**
     * @notice 计算卖出可获得的 BNB（含手续费明细）
     */
    function calculateSellReturnWithFee(address token, uint256 tokenAmount) external view returns (uint256 netBNB, uint256 feeBNB);
}
