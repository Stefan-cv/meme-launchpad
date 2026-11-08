// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;  // 编译器版本声明：要求 Solidity 版本 >= 0.8.20 且 < 0.9.0，0.8.x 内置溢出检查

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";  // 导入可初始化基础合约：为代理模式提供一次性初始化机制，替代 constructor
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";  // 导入 UUPS 可升级合约：升级逻辑放在实现合约中（而非代理合约），更省 gas
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";  // 导入基于角色的权限控制：支持多角色、多层级权限管理
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";  // 导入可暂停合约：提供紧急暂停机制，暂停后特定函数不可调用
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";  // 导入防重入保护：防止合约调用期间被恶意重入，保护资产安全
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";  // 导入椭圆曲线签名库：用于从签名中恢复签名者地址，验证签名有效性
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";  // 导入 ERC20 标准接口：定义代币转账、授权等标准方法
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";  // 导入安全 ERC20 操作库：处理不标准 ERC20 代币（如 USDT 不返回 bool）的转账安全

import {IMEMECore as IMetaNodeCore} from "./interfaces/IMEMECore.sol";  // 导入核心合约接口（别名 IMetaNodeCore）：定义事件、结构体和错误码
import {IMEMEFactory as IMetaNodeFactory} from "./interfaces/IMEMEFactory.sol";  // 导入工厂合约接口（别名 IMetaNodeFactory）：定义代币部署方法
import {IMEMEHelper as IMetaNodeHelper} from "./interfaces/IMEMEHelper.sol";  // 导入助手合约接口（别名 IMetaNodeHelper）：定义曲线计算和 DEX 操作方法
import {IMEMEVesting as IMetaNodeVesting} from "./interfaces/IMEMEVesting.sol";  // 导入归属合约接口（别名 IMetaNodeVesting）：定义锁仓释放计划管理方法
import {MetaNodeToken} from "./MEMEToken.sol";  // 导入 MEME 代币合约：用于调用代币特有方法（如 setPair、setTransferMode、burn）

/**
 * @title MetaNodeCore
 * @author MetaNode Team
 * @notice MEME 发射器核心合约 - 管理代币的完整生命周期
 *
 * ============ 合约概述 ============
 * 这是 MEME 发射器的核心业务合约，实现：
 * - 代币创建（通过签名验证）
 * - 联合曲线交易（买入/卖出）
 * - 毕业流程（添加 DEX 流动性）
 * - 代币状态管理（暂停/黑名单）
 *
 * ============ 架构设计 ============
 * - 可升级代理模式（UUPS）
 * - 基于角色的权限控制
 * - 防重入保护
 * - 紧急暂停机制
 *
 * ============ 业务流程图 ============
 *
 * 【创建代币】
 * 前端构造参数 -> 后端签名 -> 用户调用 createToken
 *      |
 * 验证签名 -> 扣除费用 -> 部署代币 -> 初始化曲线
 *      |
 * (可选) 初始买入 -> (可选) 创建归属 -> (可选) 存入保证金
 *
 * 【买入代币】
 * 用户支付 BNB -> 扣除手续费 -> 按曲线计算代币量
 *      |
 * 更新曲线储备 -> 转移代币 -> 检查是否触发毕业
 *
 * 【卖出代币】
 * 用户转入代币 -> 按曲线计算 BNB -> 扣除手续费
 *      |
 * 更新曲线储备 -> 转移 BNB
 *
 * 【毕业代币】
 * 可售量 < 阈值 -> 管理员触发毕业
 *      |
 * 计算费用分配 -> 添加 DEX 流动性 -> 开放自由交易
 *
 * ============ 费用说明 ============
 * - 创建费（creationFee）：发币时收取的固定费用
 * - 初始买入费（preBuyFeeRate）：初始买入时的手续费
 * - 交易费（tradingFeeRate）：每笔买卖收取的手续费
 * - 毕业费（graduationFeeRate）：毕业时从池中抽取的费用
 */
contract MetaNodeCore is IMetaNodeCore, Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {  // 核心合约继承：接口 + 5个可升级基础合约，实现签名验证、曲线交易、毕业流动性、状态管理等功能
    using SafeERC20 for IERC20;  // 为 IERC20 接口绑定安全操作库，使 IERC20(token).safeTransfer() 等方法可用，处理不标准返回值
    using ECDSA for bytes32;  // 为 bytes32 绑定 ECDSA 库，使 bytes32.recover(signature) 方法可用，从哈希+签名恢复地址

    // ============ 角色常量 ============

    /**
     * @notice 管理员角色
     * @dev 权限：参数配置、合约升级、紧急操作
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");  // 管理员角色哈希：keccak256 计算 "ADMIN_ROLE" 的哈希作为角色标识，用于权限检查

    /**
     * @notice 签名者角色
     * @dev 权限：为创建请求生成有效签名
     * 通常由后端服务持有
     */
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");  // 签名者角色哈希：keccak256 计算 "SIGNER_ROLE" 的哈希，后端服务持有此角色为用户创建请求签名

    /**
     * @notice 部署者角色
     * @dev 权限：触发代币毕业
     * 通常由自动化服务或管理员持有
     */
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");  // 部署者角色哈希：keccak256 计算 "DEPLOYER_ROLE" 的哈希，自动化服务或管理员持有此角色触发毕业

    /**
     * @notice 暂停者角色
     * @dev 权限：暂停/恢复单个代币的交易
     */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");  // 暂停者角色哈希：keccak256 计算 "PAUSER_ROLE" 的哈希，持有者可暂停/恢复单个代币交易

    // ============ 系统常量 ============

    /**
     * @notice 签名请求有效期（秒）
     * @dev 请求时间戳 + REQUEST_EXPIRY 后签名失效
     * 防止签名被长期滥用
     */
    uint256 public constant REQUEST_EXPIRY = 3600; // 1小时  // 签名有效期：3600秒 = 1小时，超过此时间后端签名的创建请求将过期，防止旧签名被重放攻击

    /**
     * @notice 毕业触发阈值
     * @dev 当 availableTokens < MIN_LIQUIDITY 时触发待毕业
     * 单位：wei（18位小数）
     */
    uint256 public constant MIN_LIQUIDITY = 10 ether; // 10个代币  // 毕业最小流动性阈值：10 * 10^18 = 10个代币（18位小数），当曲线中可售代币低于此值时触发毕业流程

    /**
     * @notice 初始买入最大百分比（基点）
     * @dev 9990 = 99.9%，预留 0.1% 确保曲线有流动性
     */
    uint256 public constant MAX_INITIAL_BUY_PERCENTAGE = 9990;  // 初始买入最大百分比：9990 基点 = 99.9%，创建时最多买入总量的 99.9%，预留 0.1% 保证联合曲线有最低流动性

    // ============ 可配置参数 ============

    /**
     * @notice 代币创建费用（wei）
     * @dev 每次发币时收取，转给平台
     * 默认：0.05 BNB
     */
    uint256 public creationFee;  // 创建费：每次创建代币时收取的固定 BNB 费用，默认 0.05 BNB，转给平台费接收地址

    /**
     * @notice 初始买入手续费率（基点）
     * @dev 创建时初始买入的额外费用
     * 默认：300 = 3%
     */
    uint256 public preBuyFeeRate;  // 初始买入手续费率：单位为基点（1基点=0.01%），默认 300 = 3%，创建时代币初始买入金额按此比率收取手续费

    /**
     * @notice 交易手续费率（基点）
     * @dev 每笔买卖收取的费用
     * 默认：100 = 1%
     */
    uint256 public tradingFeeRate;  // 交易手续费率：单位为基点，默认 100 = 1%，每笔买入/卖出都按此比率收取手续费

    /**
     * @notice 毕业平台费率（基点）
     * @dev 毕业时从池中抽取给平台的比例
     * 默认：550 = 5.5%
     */
    uint256 public graduationPlatformFeeRate;  // 毕业平台费率：单位为基点，默认 550 = 5.5%，毕业时从收集的 BNB 和剩余代币中抽取给平台

    /**
     * @notice 毕业创作者费率（基点）
     * @dev 毕业时从池中抽取给创建者的比例
     * 默认：250 = 2.5%
     */
    uint256 public graduationCreatorFeeRate;  // 毕业创作者费率：单位为基点，默认 250 = 2.5%，毕业时从收集的 BNB 和剩余代币中抽取给代币创建者

    /**
     * @notice 归属最短锁仓时间（秒）
     * @dev LINEAR 模式的 duration 不能小于此值
     * 默认：86400 = 1天
     */
    uint256 public minLockTime;  // 最短锁仓时间：单位为秒，默认 86400 = 1天，线性归属模式的锁仓时长不得低于此值，防止瞬间释放

    // ============ 合约依赖 ============

    /**
     * @notice 工厂合约实例
     * @dev 负责部署新的 MetaNodeToken
     */
    IMetaNodeFactory public factory;  // 工厂合约引用：负责部署新的 MetaNodeToken 代币合约，使用 CREATE2 确定地址

    /**
     * @notice 助手合约实例
     * @dev 负责曲线计算和 DEX 操作
     */
    IMetaNodeHelper public helper;  // 助手合约引用：负责联合曲线的数学计算（恒定乘积公式）和 DEX 流动性添加操作

    /**
     * @notice 归属合约实例
     * @dev 负责管理初始买入代币的锁仓释放
     */
    IMetaNodeVesting public vesting;  // 归属合约引用：负责管理初始买入代币的锁仓释放计划（线性释放/悬崖释放）

    /**
     * @notice 平台费接收地址
     * @dev 接收创建费、交易费
     */
    address public platformFeeReceiver;  // 平台费接收地址：接收创建费、交易手续费、初始买入手续费等平台收入

    /**
     * @notice 保证金接收地址
     * @dev 接收创建时的保证金
     */
    address public marginReceiver;  // 保证金接收地址：接收创建代币时用户存入的 BNB 保证金，用于反垃圾和激励机制

    /**
     * @notice 当前链 ID
     * @dev 写入签名域，防止跨链重放
     */
    uint256 public CHAIN_ID;  // 链 ID：记录部署时的链 ID，写入签名验证数据中，防止签名在另一条链上被重放使用

    // ============ 存储映射 ============

    /**
     * @notice 代币基础信息映射
     * @dev token地址 => TokenInfo
     */
    mapping(address => TokenInfo) public tokenInfo;  // 代币信息映射：通过代币合约地址查询其创建者、创建时间、开盘时间、状态、流动性池地址等信息

    /**
     * @notice 联合曲线参数映射
     * @dev token地址 => BondingCurveParams
     */
    mapping(address => BondingCurveParams) public bondingCurve;  // 联合曲线映射：通过代币地址查询其虚拟储备、恒定乘积k、可售代币数、已收集BNB等曲线参数

    /**
     * @notice 已使用的请求ID映射
     * @dev requestId => 是否已使用（防重放）
     */
    mapping(bytes32 => bool) public usedRequestIds;  // 已使用请求ID映射：记录每个 requestId 是否已被处理，防止同一个签名请求被重复执行（防重放攻击）

    /**
     * @notice 毕业费接收地址
     * @dev 接收毕业时的平台费
     */
    address public graduateFeeReceiver;  // 毕业费接收地址：代币毕业时从池中抽取的平台费 BNB 和代币发送到此地址

    // ============ 修饰器 ============

    /**
     * @notice 验证代币存在
     */
    modifier validToken(address token) {  // 有效代币修饰器：检查指定代币地址是否已在系统中注册，通过验证 creator 不为零地址判断
        if (tokenInfo[token].creator == address(0)) revert InvalidCreatorParameters();  // 若代币创建者为零地址，说明该代币未通过本合约创建，回滚并抛出 InvalidCreatorParameters 错误
        _;  // 占位符：被修饰的函数体在此处执行
    }

    /**
     * @notice 验证代币处于交易状态且已开盘
     */
    modifier onlyTradingToken(address token) {  // 仅可交易代币修饰器：检查代币状态为 TRADING 且已到开盘时间，确保只能在正常交易时段买卖
        _onlyTradingToken(token);  // 调用内部校验函数，检查代币状态和开盘时间
        _;  // 占位符：被修饰的函数体在此处执行
    }

    // ============ 构造函数 ============

    /// @custom:oz-upgrades-unsafe-allow constructor  // OpenZeppelin 升级安全注解：标记此 constructor 为升级安全允许，不会影响代理模式
    constructor() {  // 构造函数：在代理模式下构造函数只在实现合约部署时执行一次
        _disableInitializers();  // 禁用初始化器：防止实现合约被直接初始化（而非通过代理），这是 UUPS 模式的标准安全实践
    }

    // ============ 初始化函数 ============

    /**
     * @notice 初始化核心合约
     * @dev 仅在代理部署时调用一次
     *
     * @param _factory 工厂合约地址
     * @param _helper 助手合约地址
     * @param _signer 签名者地址（后端服务）
     * @param _platformFeeReceiver 平台费接收地址
     * @param _marginReceiver 保证金接收地址
     * @param _graduateFeeReceiver 毕业费接收地址
     * @param _admin 管理员地址
     *
     * ============ 初始化内容 ============
     * 1. 初始化 OpenZeppelin 可升级组件
     * 2. 设置合约依赖
     * 3. 授予角色权限
     * 4. 设置默认费率参数
     */
    function initialize(
        address _factory,  // 工厂合约地址：用于部署新代币
        address _helper,  // 助手合约地址：用于曲线计算和 DEX 操作
        address _signer,  // 签名者地址：后端服务地址，为用户创建请求生成签名
        address _platformFeeReceiver,  // 平台费接收地址：接收创建费和交易手续费
        address _marginReceiver,  // 保证金接收地址：接收创建时存入的保证金
        address _graduateFeeReceiver,  // 毕业费接收地址：接收毕业时抽取的平台费
        address _admin  // 管理员地址：获得所有角色的初始管理员
    ) public initializer {  // 初始化函数：initializer 修饰器确保此函数只能被调用一次（代理部署时）
        // 初始化可升级组件
        __AccessControl_init();  // 初始化访问控制组件：设置角色管理的内部存储
        __Pausable_init();  // 初始化暂停组件：设置暂停状态的内部存储
        __ReentrancyGuard_init();  // 初始化防重入组件：设置重入锁的内部存储
        __UUPSUpgradeable_init();  // 初始化 UUPS 升级组件：设置升级机制的内部存储

        // 记录链 ID
        CHAIN_ID = block.chainid;  // 保存当前链 ID 到状态变量，签名验证时包含此值防止跨链重放攻击

        // 设置合约依赖
        factory = IMetaNodeFactory(_factory);  // 保存工厂合约引用，后续调用 factory.deployToken() 部署新代币
        helper = IMetaNodeHelper(_helper);  // 保存助手合约引用，后续调用曲线计算和 DEX 流动性添加
        platformFeeReceiver = _platformFeeReceiver;  // 保存平台费接收地址，所有平台费用转至此地址
        marginReceiver = _marginReceiver;  // 保存保证金接收地址，创建代币的保证金转至此地址
        graduateFeeReceiver = _graduateFeeReceiver;  // 保存毕业费接收地址，毕业时平台费转至此地址

        // 授予角色
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);  // 授予管理员默认管理员角色：拥有授予和撤销其他角色的最高权限
        _grantRole(ADMIN_ROLE, _admin);  // 授予管理员 ADMIN_ROLE：可修改费率、升级合约、紧急操作
        _grantRole(SIGNER_ROLE, _signer);  // 授予签名者 SIGNER_ROLE：后端服务可为创建请求生成有效签名
        _grantRole(DEPLOYER_ROLE, _admin);  // 授予管理员 DEPLOYER_ROLE：初始由管理员持有，可触发代币毕业
        _grantRole(PAUSER_ROLE, _admin);  // 授予管理员 PAUSER_ROLE：初始由管理员持有，可暂停/恢复代币交易

        // 设置默认费率
        creationFee = 0.05 ether;          // 创建费：0.05 BNB  // 设置创建费为 0.05 BNB，每次发币收取
        preBuyFeeRate = 300;               // 初始买入费：3%  // 设置初始买入手续费率为 300 基点 = 3%
        tradingFeeRate = 100;              // 交易费：1%  // 设置交易手续费率为 100 基点 = 1%
        graduationPlatformFeeRate = 550;   // 毕业平台费：5.5%  // 设置毕业平台费率为 550 基点 = 5.5%
        graduationCreatorFeeRate = 250;    // 毕业创作者费：2.5%  // 设置毕业创作者费率为 250 基点 = 2.5%
        minLockTime = 86400;               // 最短锁仓：1天  // 设置归属最短锁仓时间为 86400 秒 = 1天
    }

    // ============ 核心业务函数 ============

    /**
     * @notice 创建新代币
     * @dev 防重入、暂停保护
     *
     * @param data ABI 编码的 CreateTokenParams
     * @param signature 后端对 data+chainId+address 的签名
     * @return tokenAddress 新部署的代币地址
     *
     * ============ 完整执行流程 ============
     *
     * 1. 【费用校验】
     *    - 检查 msg.value >= creationFee
     *
     * 2. 【解码参数】
     *    - 从 data 解码 CreateTokenParams
     *
     * 3. 【签名验证】
     *    - 计算消息哈希：hash(data, chainId, this)
     *    - 恢复签名者地址
     *    - 验证签名者拥有 SIGNER_ROLE
     *
     * 4. 【请求校验】
     *    - 检查时间戳未过期
     *    - 检查 requestId 未被使用
     *    - 验证代币参数合法性
     *
     * 5. 【计算支付】
     *    - 基础：creationFee
     *    - 可选：marginBnb（保证金）
     *    - 可选：initialBNB + preBuyFee（初始买入）
     *
     * 6. 【部署代币】
     *    - 调用工厂合约部署 MetaNodeToken
     *    - 获取预计算的交易对地址
     *    - 设置代币的 pair 地址
     *
     * 7. 【初始化曲线】
     *    - 设置虚拟储备（考虑初始买入调整）
     *    - 计算恒定乘积 k
     *    - 记录可售数量和已收集 BNB
     *
     * 8. 【注册代币信息】
     *    - 记录创建者、时间、状态等
     *
     * 9. 【设置转账模式】
     *    - 切换到 CONTROLLED 模式
     *    - 设置归属合约地址
     *
     * 10.【处理初始买入】
     *    - 创建归属计划（如配置）
     *    - 或直接转移代币给创建者
     *
     * 11.【处理保证金】
     *    - 转移保证金到 marginReceiver
     *
     * 12.【转移费用】
     *    - 创建费和初始买入费转给平台
     *
     * 13.【退还多余】
     *    - 如有多余 BNB，退还给用户
     */
    function createToken(
        bytes calldata data,  // ABI 编码的创建参数数据，包含代币名称、符号、供应量、曲线参数等全部配置
        bytes calldata signature  // 后端服务对 (data + CHAIN_ID + 合约地址) 的 ECDSA 签名，用于验证请求合法性
    ) external payable nonReentrant whenNotPaused returns (address tokenAddress){  // 外部可调用、需支付BNB、防重入、非暂停状态、返回新代币地址
        // 1. 费用校验
        if (msg.value < creationFee) revert InsufficientFee();  // 检查支付金额是否至少等于创建费，否则回滚：确保用户支付了最低创建费用

        // 2. 解码参数
        IMetaNodeCore.CreateTokenParams memory params = abi.decode(data, (IMetaNodeCore.CreateTokenParams));  // 从 calldata 中 ABI 解码出 CreateTokenParams 结构体，包含所有创建参数

        // 3. 签名验证
        bytes32 messageHash = keccak256(abi.encodePacked(data, CHAIN_ID, address(this)));  // 计算消息哈希：将 data + 链ID + 合约地址 紧凑编码后哈希，确保签名与特定链和合约绑定
        address signer = messageHash.recover(signature);  // 使用 ECDSA 从哈希和签名中恢复签名者地址，确认是谁签署了此请求
        if (!hasRole(SIGNER_ROLE, signer)) revert InvalidSigner();  // 检查恢复的签名者是否持有 SIGNER_ROLE，否则回滚：确保只有后端授权的签名者才能创建代币

        // 4. 请求校验
        if (block.timestamp > params.timestamp + REQUEST_EXPIRY) revert RequestExpired();  // 检查当前时间是否超过请求时间戳+有效期（1小时），防止旧签名被重放
        if (usedRequestIds[params.requestId]) revert RequestAlreadyProcessed();  // 检查此 requestId 是否已使用过，防止同一签名被重复执行（防重放攻击）

        // 验证代币参数
        if (params.saleAmount > params.totalSupply) revert InvalidSaleParameters();  // 检查可售数量不超过总供应量，逻辑上不可能卖出比总量更多的代币
        if (params.saleAmount == 0) revert InvalidSaleParameters();  // 检查可售数量不为零，必须有至少部分代币在曲线上交易
        if (params.saleAmount < params.totalSupply * params.initialBuyPercentage / 10000) revert InvalidSaleParameters();  // 检查可售数量 >= 初始买入占用量，初始买入后的剩余量必须非负
        if (params.initialBuyPercentage > MAX_INITIAL_BUY_PERCENTAGE) revert InvalidInitialBuyPercentage();  // 检查初始买入百分比不超过 99.9%，保证曲线有最低流动性

        // 5. 计算总支付金额
        uint256 totalPaymentRequired = creationFee;  // 总支付需求初始化为创建费，后续加上保证金和初始买入费用
        uint256 initialTokens = 0;  // 初始买入获得的代币数量，默认为0（不初始买入）
        uint256 initialBNB = 0;  // 初始买入消耗的 BNB 数量，默认为0
        uint256 adjustedBNBReserve = params.virtualBNBReserve;  // 调整后的虚拟 BNB 储备，默认等于初始设定值，初始买入后会更新
        uint256 adjustedTokenReserve = params.virtualTokenReserve;  // 调整后的虚拟代币储备，默认等于初始设定值，初始买入后会更新
        uint256 preBuyFee;  // 初始买入手续费金额，后续根据 initialBNB 和 preBuyFeeRate 计算

        // 添加保证金
        if (params.marginBnb > 0) {  // 如果创建参数中包含保证金
            totalPaymentRequired += params.marginBnb;  // 将保证金金额加到总支付需求中
        }

        // 计算初始买入
        if (params.initialBuyPercentage > 0) {  // 如果创建参数中设置了初始买入百分比（> 0 表示需要初始买入）
            (initialTokens, initialBNB, adjustedBNBReserve, adjustedTokenReserve) =  // 通过内部函数计算初始买入结果：获得的代币数、消耗的BNB、调整后的储备值
            _calculateInitialBuy(  // 调用内部函数，使用恒定乘积公式反推初始买入
                params.totalSupply,  // 总供应量：用于计算初始买入代币数量 = totalSupply * percentageBP / 10000
                params.virtualBNBReserve,  // 虚拟 BNB 储备：曲线初始 BNB 储备参数
                params.virtualTokenReserve,  // 虚拟代币储备：曲线初始代币储备参数
                params.initialBuyPercentage  // 初始买入百分比（基点）：如 5000 = 50%
            );
            preBuyFee = (initialBNB * preBuyFeeRate) / 10000;  // 计算初始买入手续费 = 初始买入BNB × 费率 / 10000（基点转百分比）
            totalPaymentRequired += initialBNB + preBuyFee;  // 将初始买入 BNB 和手续费加到总支付需求中
        }

        // 验证支付金额
        if (msg.value < totalPaymentRequired) revert InsufficientFee();  // 最终检查：用户支付的 BNB 必须覆盖创建费+保证金+初始买入+手续费，否则回滚

        // 标记请求已处理
        usedRequestIds[params.requestId] = true;  // 将此 requestId 标记为已使用，防止同一签名被重复提交

        // 6. 部署代币
        tokenAddress = factory.deployToken(  // 通过工厂合约部署新的 MetaNodeToken 代币，返回新代币地址
            params.name,  // 代币名称：如 "Pepe Coin"
            params.symbol,  // 代币符号：如 "PEPE"
            params.totalSupply,  // 总供应量：代币的初始铸造总量
            params.timestamp,  // 时间戳：传入创建请求的时间戳，工厂可能用于生成确定地址
            params.nonce  // 随机数：用于 CREATE2 地址计算的盐值，确保每次部署地址不同
        );

        address pair = helper.getPairAddress(tokenAddress);  // 通过助手合约预计算 DEX 交易对地址（基于 CREATE2 或工厂预判），无需实际创建交易对
        if (pair == address(0)) revert InvalidPair();  // 如果预计算的交易对地址为零地址，说明计算失败，回滚
        MetaNodeToken(tokenAddress).setPair(pair);  // 在新代币合约中设置交易对地址，代币合约据此识别 DEX 交易对以限制买卖税等

        // 7. 初始化曲线
        bondingCurve[tokenAddress] = BondingCurveParams({  // 将联合曲线参数写入存储映射，与代币地址绑定
            virtualBNBReserve: adjustedBNBReserve,  // 虚拟 BNB 储备：初始买入后调整的值（若有初始买入则增大）
            virtualTokenReserve: adjustedTokenReserve,  // 虚拟代币储备：初始买入后调整的值（若有初始买入则减小）
            k: params.virtualBNBReserve * params.virtualTokenReserve,  // 恒定乘积 k = 原始虚拟BNB储备 × 原始虚拟代币储备，k值在整个曲线生命周期中保持不变
            availableTokens: params.saleAmount - initialTokens,  // 可售代币数 = 总可售量 - 初始买入量，即用户可通过买卖交易的代币数量
            collectedBNB: initialBNB  // 已收集 BNB = 初始买入的 BNB 金额，后续买卖会增减此值
        });

        // 8. 注册代币信息
        tokenInfo[tokenAddress] = TokenInfo({  // 将代币基础信息写入存储映射，与代币地址绑定
            creator: params.creator,  // 代币创建者地址：接收毕业创作者费
            createdAt: block.timestamp,  // 创建时间戳：当前区块时间
            launchTime: params.launchTime,  // 开盘时间：在此之前不可交易，0表示立即开盘
            status: TokenStatus.TRADING,  // 初始状态设为 TRADING（可交易）
            liquidityPool: pair  // 流动性池地址：预计算的 DEX 交易对地址
        });

        // 9. 设置转账模式
        MetaNodeToken(tokenAddress).setTransferMode(  // 设置代币的转账模式为受控模式
            MetaNodeToken.TransferMode.MODE_TRANSFER_CONTROLLED  // 受控模式：只允许本合约（核心合约）和归属合约的转账，其他转账被拒绝
        );

        if (address(vesting) != address(0)) {  // 如果归属合约已设置（非零地址）
            MetaNodeToken(tokenAddress).setVestingContract(address(vesting));  // 在代币合约中设置归属合约地址，允许归属合约在受控模式下转移代币
        }

        // 10. 处理初始买入
        if (initialTokens > 0) {  // 如果有初始买入代币
            if (params.vestingAllocations.length > 0 && address(vesting) != address(0)) {  // 如果有归属分配配置且归属合约已部署
                uint256 tokensToTransfer = _createVestingSchedules(  // 创建归属计划，返回需要直接转移给创建者的代币数量（非锁仓部分）
                    tokenAddress,  // 代币地址
                    params.creator,  // 归属受益人（代币创建者）
                    initialTokens,  // 初始买入获得的代币总量
                    params.initialBuyPercentage,  // 初始买入百分比
                    params.totalSupply,  // 总供应量
                    params.vestingAllocations  // 归属分配配置数组
                );
                if (tokensToTransfer > 0) {  // 如果归属后还有剩余代币需要直接转移
                    IERC20(tokenAddress).safeTransfer(params.creator, tokensToTransfer);  // 安全转移非锁仓代币给创建者
                }
            } else {  // 如果没有归属配置，全部代币直接转移给创建者
                IERC20(tokenAddress).safeTransfer(params.creator, initialTokens);  // 安全转移全部初始买入代币给创建者
            }

            emit TokenCreatedWithInitialBuy(  // 发射初始买入事件，记录初始买入的详细信息
                tokenAddress,  // 代币地址
                params.creator,  // 创建者地址
                initialTokens,  // 初始买入代币数量
                initialBNB,  // 初始买入消耗的 BNB
                params.initialBuyPercentage  // 初始买入百分比
            );
        }

        // 11. 处理保证金
        if (params.marginBnb > 0) {  // 如果创建参数中包含保证金
            if (marginReceiver == address(0)) revert MarginReceiverNotSet();  // 检查保证金接收地址已设置，否则回滚：防止 BNB 被转入零地址
            payable(marginReceiver).transfer(params.marginBnb);  // 将保证金 BNB 转给保证金接收地址
            emit MarginDeposited(  // 发射保证金存入事件
                tokenAddress,  // 代币地址
                params.creator,  // 创建者地址
                params.marginBnb,  // 保证金金额
                params.marginTime  // 保证金时间（锁仓到期时间等）
            );
        }

        // 12. 转移费用
        _sendValue(platformFeeReceiver, preBuyFee);  // 安全发送初始买入手续费给平台费接收地址
        _sendValue(platformFeeReceiver, creationFee);  // 安全发送创建费给平台费接收地址

        // 13. 退还多余
        if (msg.value > totalPaymentRequired) {  // 如果用户支付了超过所需金额（常见于初始买入计算偏差）
            payable(msg.sender).transfer(msg.value - totalPaymentRequired);  // 退还多余 BNB 给用户，差值 = 实际支付 - 所需金额
        }

        emit TokenCreated(tokenAddress, params.creator, params.name, params.symbol, params.totalSupply, params.requestId);  // 发射代币创建事件，记录代币的核心信息
    }

    /**
     * @notice 从联合曲线买入代币
     * @dev 防重入、暂停保护、代币状态校验
     *
     * @param token 代币地址
     * @param minTokenAmount 最小获得代币数（滑点保护）
     * @param deadline 交易截止时间
     *
     * ============ 执行流程 ============
     *
     * 1. 【时间校验】
     *    - deadline 在当前时间到+1天之间
     *
     * 2. 【金额校验】
     *    - msg.value > 0
     *
     * 3. 【手续费计算】
     *    - tradingFee = msg.value * tradingFeeRate / 10000
     *    - netBNBAmount = msg.value - tradingFee
     *
     * 4. 【代币计算】
     *    - 使用 helper 按曲线计算可获得代币数
     *
     * 5. 【余量处理】
     *    - 如果计算结果 > availableTokens
     *    - 改为购买全部剩余，重算 BNB 和手续费
     *    - 退还多余 BNB
     *
     * 6. 【滑点校验】
     *    - tokenAmount >= minTokenAmount
     *
     * 7. 【更新曲线】
     *    - virtualBNBReserve += netBNBAmount
     *    - virtualTokenReserve -= tokenAmount
     *    - availableTokens -= tokenAmount
     *    - collectedBNB += netBNBAmount
     *
     * 8. 【转移资产】
     *    - 手续费转给平台
     *    - 代币转给买家
     *
     * 9. 【检查毕业】
     *    - 如果 availableTokens < MIN_LIQUIDITY
     *    - 切换状态为 PENDING_GRADUATION
     *    - 代币切换为 RESTRICTED 模式
     */
    function buy(
        address token,  // 要买入的代币合约地址
        uint256 minTokenAmount,  // 最小获得代币数量（滑点保护）：如果实际获得的代币少于此值则回滚
        uint256 deadline  // 交易截止时间戳：超过此时间交易无效，防止交易在 mempool 中被长时间延迟
    ) external payable nonReentrant whenNotPaused validToken(token) onlyTradingToken(token) {  // 外部可调用、需支付BNB、防重入、非暂停、代币有效、代币可交易
        // 1-2. 校验
        if (block.timestamp > deadline || deadline >= block.timestamp + 1 days) revert TransactionExpired();  // 时间校验：deadline 必须在当前时间之后且不超过1天，防止设置过远的截止时间
        if (msg.value == 0) revert InvalidNativeAmount();  // 金额校验：支付的 BNB 不能为零，零元买入无意义

        // 3. 手续费计算
        uint256 tradingFee = (msg.value * tradingFeeRate) / 10000;  // 计算交易手续费 = 支付金额 × 费率 / 10000（基点转百分比），如 1 BNB × 1% = 0.01 BNB
        uint256 netBNBAmount = msg.value - tradingFee;  // 扣除手续费后的净额，即实际进入联合曲线参与计算的 BNB 数量

        // 4. 代币计算
        uint256 tokenAmount = helper.calculateTokenAmountOut(netBNBAmount, bondingCurve[token]);  // 调用助手合约，使用恒定乘积公式 x*y=k 计算净 BNB 可获得的代币数量

        // 5. 余量处理
        if (tokenAmount > bondingCurve[token].availableTokens) {  // 如果计算出的代币数超过曲线中剩余可售代币数（即买完了所有剩余代币）
            tokenAmount = bondingCurve[token].availableTokens;  // 将购买数量限制为剩余可售代币总量，用户买到全部剩余
            netBNBAmount = helper.calculateRequiredBNB(tokenAmount, bondingCurve[token]);  // 反向计算：买完所有剩余代币需要多少 BNB（使用恒定乘积公式反推）
            tradingFee = (netBNBAmount * tradingFeeRate) / (10000 - tradingFeeRate);  // 从净额反推手续费：fee = netBNB * rate / (10000 - rate)，因为 netBNB = total - fee 且 fee = total * rate / 10000
            uint256 actualPayment = netBNBAmount + tradingFee;  // 实际需要支付的总额 = 净BNB + 手续费

            if (msg.value > actualPayment) {  // 如果用户支付的 BNB 超过实际需要
                payable(msg.sender).transfer(msg.value - actualPayment);  // 退还多余 BNB 给用户
            }
        }

        // 6. 滑点校验
        if (tokenAmount < minTokenAmount) revert SlippageExceeded();  // 检查实际获得代币数 >= 最低预期，否则回滚：保护用户免受过大滑点损失

        // 7. 更新曲线
        bondingCurve[token].virtualBNBReserve += netBNBAmount;  // 增加 BNB 储备：净买入 BNB 加入虚拟储备，使后续买入价格上升
        bondingCurve[token].virtualTokenReserve -= tokenAmount;  // 减少代币储备：买出的代币从虚拟储备中扣除
        bondingCurve[token].availableTokens -= tokenAmount;  // 减少可售代币：已售出的代币不再可售
        bondingCurve[token].collectedBNB += netBNBAmount;  // 增加已收集 BNB：记录实际进入曲线的 BNB 总量，用于卖出和毕业时的资金管理

        // 8. 转移资产
        _sendValue(platformFeeReceiver, tradingFee);  // 安全发送交易手续费给平台费接收地址
        IERC20(token).safeTransfer(msg.sender, tokenAmount);  // 安全转移买入的代币给买家

        // 9. 检查毕业
        if (bondingCurve[token].availableTokens < MIN_LIQUIDITY) {  // 如果可售代币数低于毕业阈值（10个代币）
            _changeTokenStatus(token, TokenStatus.PENDING_GRADUATION);  // 将代币状态切换为"待毕业"，表示曲线即将耗尽
            MetaNodeToken(token).setTransferMode(MetaNodeToken.TransferMode.MODE_TRANSFER_RESTRICTED);  // 切换代币转账模式为受限：仅允许核心合约和归属合约转账，防止在毕业前自由转移
        }

        emit TokenBought(  // 发射代币买入事件，记录交易详情
            token,  // 代币地址
            msg.sender,  // 买家地址
            netBNBAmount,  // 净 BNB 金额（扣除手续费后）
            tokenAmount,  // 获得的代币数量
            tradingFee,  // 交易手续费
            bondingCurve[token].virtualBNBReserve,  // 更新后的虚拟 BNB 储备
            bondingCurve[token].virtualTokenReserve,  // 更新后的虚拟代币储备
            bondingCurve[token].availableTokens,  // 更新后的可售代币数
            bondingCurve[token].collectedBNB  // 更新后的已收集 BNB
        );
    }

    /**
     * @notice 向联合曲线卖出代币
     * @dev 防重入、暂停保护、代币状态校验
     *
     * @param token 代币地址
     * @param tokenAmount 卖出的代币数量
     * @param minBNBAmount 最小获得 BNB（滑点保护）
     * @param deadline 交易截止时间
     *
     * ============ 执行流程 ============
     *
     * 1. 【校验】
     *    - deadline 未过期
     *    - tokenAmount > 0
     *    - 用户余额充足
     *
     * 2. 【BNB 计算】
     *    - 使用 helper 按曲线计算可获得 BNB
     *    - 计算手续费
     *    - netBNBAmount = bnbAmount - tradingFee
     *
     * 3. 【滑点校验】
     *    - netBNBAmount >= minBNBAmount
     *
     * 4. 【池余额校验】
     *    - bnbAmount <= collectedBNB
     *
     * 5. 【转入代币】
     *    - 从用户转入代币到合约
     *
     * 6. 【更新曲线】
     *    - virtualBNBReserve -= bnbAmount
     *    - virtualTokenReserve += tokenAmount
     *    - availableTokens += tokenAmount
     *    - collectedBNB -= bnbAmount
     *
     * 7. 【转移 BNB】
     *    - 手续费转给平台
     *    - 净额转给卖家
     */
    function sell(
        address token,  // 要卖出的代币合约地址
        uint256 tokenAmount,  // 卖出的代币数量
        uint256 minBNBAmount,  // 最小获得 BNB 数量（滑点保护）：如果实际获得 BNB 少于此值则回滚
        uint256 deadline  // 交易截止时间戳：超过此时间交易无效
    ) external nonReentrant whenNotPaused validToken(token) onlyTradingToken(token) {  // 外部可调用、防重入、非暂停、代币有效、代币可交易（注意不需要 payable，卖出代币不直接支付 BNB）
        // 1. 校验
        if (block.timestamp > deadline) revert TransactionExpired();  // 时间校验：当前时间不能超过截止时间，防止过期交易被执行
        if (tokenAmount == 0) revert InvalidParameters();  // 数量校验：卖出的代币数量不能为零
        if (IERC20(token).balanceOf(msg.sender) < tokenAmount) revert InsufficientBalance();  // 余额校验：用户必须持有足够的代币才能卖出

        // 2. BNB 计算
        uint256 bnbAmount = helper.calculateBNBAmountOut(tokenAmount, bondingCurve[token]);  // 调用助手合约，使用恒定乘积公式计算卖出代币可获得的 BNB 总量（未扣手续费）
        uint256 tradingFee = (bnbAmount * tradingFeeRate) / 10000;  // 计算交易手续费 = 获得BNB × 费率 / 10000（基点转换）
        uint256 netBNBAmount = bnbAmount - tradingFee;  // 扣除手续费后的净额，即卖家实际收到的 BNB

        // 3-4. 校验
        if (netBNBAmount < minBNBAmount) revert SlippageExceeded();  // 滑点校验：实际获得 BNB 必须 >= 最低预期，保护卖家免受过大滑点
        if (bnbAmount > bondingCurve[token].collectedBNB) revert InsufficientBalance();  // 池余额校验：曲线收集的 BNB 必须足够支付卖出金额，防止合约 BNB 不足

        // 5. 转入代币
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);  // 从卖家转入代币到本合约（需要卖家事先 approve），代币回到曲线池中

        // 6. 更新曲线
        bondingCurve[token].virtualBNBReserve -= bnbAmount;  // 减少 BNB 储备：卖出的 BNB 从虚拟储备中扣除，使后续卖出价格下降
        bondingCurve[token].virtualTokenReserve += tokenAmount;  // 增加代币储备：卖回的代币加入虚拟储备
        bondingCurve[token].availableTokens += tokenAmount;  // 增加可售代币：卖回的代币重新可售
        bondingCurve[token].collectedBNB -= bnbAmount;  // 减少已收集 BNB：支付给卖家的 BNB 从已收集金额中扣除

        // 7. 转移 BNB
        _sendValue(platformFeeReceiver, tradingFee);  // 安全发送交易手续费给平台费接收地址
        _sendValue(msg.sender, netBNBAmount);  // 安全发送扣除手续费后的净 BNB 给卖家

        emit TokenSold(  // 发射代币卖出事件，记录交易详情
            token,  // 代币地址
            msg.sender,  // 卖家地址
            tokenAmount,  // 卖出的代币数量
            netBNBAmount,  // 卖家实际收到的净 BNB
            tradingFee,  // 交易手续费
            bondingCurve[token].virtualBNBReserve,  // 更新后的虚拟 BNB 储备
            bondingCurve[token].virtualTokenReserve,  // 更新后的虚拟代币储备
            bondingCurve[token].availableTokens,  // 更新后的可售代币数
            bondingCurve[token].collectedBNB  // 更新后的已收集 BNB
        );
    }

    /**
     * @notice 毕业代币 - 添加 DEX 流动性
     * @dev 仅限 DEPLOYER_ROLE、防重入
     *
     * @param token 代币地址
     *
     * ============ 执行流程 ============
     *
     * 1. 【读取数据】
     *    - 获取 collectedBNB 和 availableTokens
     *
     * 2. 【计算费用分配】
     *    - platformFee = collectedBNB * graduationPlatformFeeRate / 10000
     *    - creatorFee = collectedBNB * graduationCreatorFeeRate / 10000
     *    - liquidityBNB = collectedBNB - platformFee - creatorFee
     *    - 代币同样按比例分配
     *
     * 3. 【解除转账限制】
     *    - 切换代币为 NORMAL 模式
     *
     * 4. 【添加流动性】
     *    - 授权 helper 操作代币
     *    - 调用 helper.addLiquidityV2
     *    - LP 代币发送到死地址（永久锁定）
     *
     * 5. 【更新状态】
     *    - 切换为 GRADUATED
     *
     * 6. 【分配费用】
     *    - BNB 平台费转给 graduateFeeReceiver
     *    - 代币平台费转给 graduateFeeReceiver
     *    - BNB 创作者费转给 creator
     *    - 代币创作者费转给 creator
     */
    function graduateToken(address token) external onlyRole(DEPLOYER_ROLE) validToken(token) nonReentrant {  // 仅 DEPLOYER_ROLE 可调用、代币有效、防重入
        TokenInfo storage info = tokenInfo[token];  // 获取代币信息的存储引用，后续读取 creator 地址
        BondingCurveParams storage curve = bondingCurve[token];  // 获取曲线参数的存储引用，后续读取 collectedBNB 和 availableTokens

        // 1. 读取数据
        uint256 collectedBNB = curve.collectedBNB;  // 读取曲线已收集的 BNB 总量，这是买卖过程中净流入曲线的 BNB
        uint256 remainingTokens = curve.availableTokens;  // 读取曲线中剩余可售代币数量，这些代币将分配给流动性和费用

        // 2. 计算费用分配
        uint256 platformFee = collectedBNB * graduationPlatformFeeRate / 10000;  // 计算平台费 BNB = 已收集BNB × 毕业平台费率 / 10000，如 10 BNB × 5.5% = 0.55 BNB
        uint256 creatorFee = collectedBNB * graduationCreatorFeeRate / 10000;  // 计算创作者费 BNB = 已收集BNB × 毕业创作者费率 / 10000，如 10 BNB × 2.5% = 0.25 BNB
        uint256 liquidityBNB = collectedBNB - platformFee - creatorFee;  // 流动性 BNB = 已收集 - 平台费 - 创作者费，这是实际添加到 DEX 的 BNB 数量

        uint256 tokenPlatformFee = remainingTokens * graduationPlatformFeeRate / 10000;  // 计算平台费代币 = 剩余代币 × 毕业平台费率 / 10000
        uint256 tokenCreatorFee = remainingTokens * graduationCreatorFeeRate / 10000;  // 计算创作者费代币 = 剩余代币 × 毕业创作者费率 / 10000
        uint256 liquidityTokens = remainingTokens - tokenPlatformFee - tokenCreatorFee;  // 流动性代币 = 剩余 - 平台费代币 - 创作者费代币，这是实际添加到 DEX 的代币数量

        // 3. 解除转账限制
        MetaNodeToken(token).setTransferMode(MetaNodeToken.TransferMode.MODE_NORMAL);  // 切换代币转账模式为正常：解除所有限制，允许在 DEX 上自由交易

        // 4. 添加流动性
        require(IERC20(token).balanceOf(address(this)) >= remainingTokens, "Insufficient token for liquidity");  // 检查本合约持有足够代币，确保可以支付流动性+费用
        IERC20(token).approve(address(helper), liquidityTokens);  // 授权助手合约操作流动性代币数量，helper.addLiquidityV2 会从本合约转取代币
        uint256 liquidityResult = helper.addLiquidityV2{value: liquidityBNB}(token, liquidityBNB, liquidityTokens);  // 调用助手在 DEX 上添加 BNB-代币 流动性，附带的 liquidityBNB 作为 BNB 注入，返回 LP 代币数量

        // 5. 更新状态
        _changeTokenStatus(token, TokenStatus.GRADUATED);  // 将代币状态切换为"已毕业"，表示已从联合曲线迁移到 DEX 自由交易

        // 6. 分配费用
        _sendValue(graduateFeeReceiver, platformFee);  // 安全发送 BNB 平台费给毕业费接收地址
        if (tokenPlatformFee > 0) IERC20(token).safeTransfer(graduateFeeReceiver, tokenPlatformFee);  // 如果有代币平台费，安全转移给毕业费接收地址
        _sendValue(info.creator, creatorFee);  // 安全发送 BNB 创作者费给代币创建者
        if (tokenCreatorFee > 0) IERC20(token).safeTransfer(info.creator, tokenCreatorFee);  // 如果有代币创作者费，安全转移给代币创建者

        emit TokenGraduated(token, liquidityBNB, liquidityTokens, liquidityResult);  // 发射代币毕业事件，记录添加到 DEX 的流动性数量
    }

    // ============ 代币状态管理 ============

    /**
     * @notice 暂停代币交易
     * @dev 仅限 PAUSER_ROLE
     */
    function pauseToken(address token) external onlyRole(PAUSER_ROLE) validToken(token) {  // 仅 PAUSER_ROLE 可调用、代币有效
        _changeTokenStatus(token, TokenStatus.PAUSED);  // 将代币状态切换为"已暂停"，暂停后 buy/sell 不可执行
        emit TokenPaused(token);  // 发射代币暂停事件
    }

    /**
     * @notice 恢复代币交易
     * @dev 仅限 PAUSER_ROLE，必须当前为 PAUSED
     */
    function unpauseToken(address token) external onlyRole(PAUSER_ROLE) validToken(token) {  // 仅 PAUSER_ROLE 可调用、代币有效
        if (tokenInfo[token].status != TokenStatus.PAUSED) revert InvalidPausedStatus();  // 检查代币当前状态必须为 PAUSED，只能恢复被暂停的代币
        _changeTokenStatus(token, TokenStatus.TRADING);  // 将代币状态切换回"可交易"，恢复买卖功能
        emit TokenUnpaused(token);  // 发射代币恢复事件
    }

    /**
     * @notice 拉黑代币（紧急措施）
     * @dev 仅限 ADMIN_ROLE
     */
    function blacklistToken(address token) external onlyRole(ADMIN_ROLE) validToken(token) {  // 仅 ADMIN_ROLE 可调用、代币有效
        _changeTokenStatus(token, TokenStatus.BLACKLISTED);  // 将代币状态切换为"已拉黑"，黑名单代币不可交易且不可恢复（除非管理员主动解除）
        emit TokenBlacklisted(token);  // 发射代币拉黑事件
    }

    /**
     * @notice 解除代币黑名单
     * @dev 仅限 ADMIN_ROLE，必须当前为 BLACKLISTED
     */
    function removeFromBlacklist(address token) external onlyRole(ADMIN_ROLE) validToken(token) {  // 仅 ADMIN_ROLE 可调用、代币有效
        if (tokenInfo[token].status != TokenStatus.BLACKLISTED) revert InvalidBlackListedStatus();  // 检查代币当前状态必须为 BLACKLISTED，只能解除黑名单中的代币
        _changeTokenStatus(token, TokenStatus.TRADING);  // 将代币状态切换回"可交易"，恢复买卖功能
        emit TokenRemovedFromBlacklist(token);  // 发射代币解除黑名单事件
    }

    // ============ 查询函数 ============

    /**
     * @notice 获取代币基础信息
     */
    function getTokenInfo(address token) external view returns (TokenInfo memory) {  // 视图函数：返回代币基础信息的内存副本（不消耗 gas）
        return tokenInfo[token];  // 从映射中读取并返回指定代币的信息结构体
    }

    /**
     * @notice 获取曲线参数
     */
    function getBondingCurve(address token) external view returns (BondingCurveParams memory) {  // 视图函数：返回联合曲线参数的内存副本（不消耗 gas）
        return bondingCurve[token];  // 从映射中读取并返回指定代币的曲线参数结构体
    }

    /**
     * @notice 计算买入可获得代币数（不含手续费）
     */
    function calculateBuyAmount(address token, uint256 bnbAmount) external view returns (uint256 tokenAmount) {  // 视图函数：估算给定 BNB 可买入的代币数（不含手续费）
        BondingCurveParams memory curve = bondingCurve[token];  // 读取曲线参数到内存
        tokenAmount = helper.calculateTokenAmountOut(bnbAmount, curve);  // 调用助手计算给定 BNB 数量可获得的代币数
        if (tokenAmount > curve.availableTokens) {  // 如果计算结果超过可售代币总量
            tokenAmount = curve.availableTokens;  // 限制为可售代币总量（最多买完所有剩余）
        }
    }

    /**
     * @notice 计算买入可获得代币数（含手续费明细）
     */
    function calculateBuyAmountWithFee(address token, uint256 bnbAmount) external view returns (uint256 tokenOut, uint256 netBNB, uint256 feeBNB) {  // 视图函数：估算买入结果含手续费明细
        BondingCurveParams memory curve = bondingCurve[token];  // 读取曲线参数到内存
        (tokenOut, netBNB, feeBNB) = helper.calculateTokenAmountOutWithFee(bnbAmount, curve, tradingFeeRate);  // 调用助手计算含手续费的买入结果
        if (tokenOut > curve.availableTokens) {  // 如果计算结果超过可售代币总量
            tokenOut = curve.availableTokens;  // 限制为可售代币总量
            netBNB = helper.calculateRequiredBNB(tokenOut, curve);  // 反向计算买完所有剩余所需净 BNB
            feeBNB = (netBNB * tradingFeeRate) / (10000 - tradingFeeRate);  // 从净额反推手续费：fee = netBNB * rate / (10000 - rate)
        }
    }

    /**
     * @notice 计算卖出可获得 BNB（不含手续费）
     */
    function calculateSellReturn(address token, uint256 tokenAmount) external view returns (uint256) {  // 视图函数：估算卖出代币可获得的 BNB（不含手续费）
        return helper.calculateBNBAmountOut(tokenAmount, bondingCurve[token]);  // 调用助手使用恒定乘积公式计算卖出代币可获得的 BNB
    }

    /**
     * @notice 计算卖出可获得 BNB（含手续费明细）
     */
    function calculateSellReturnWithFee(address token, uint256 tokenAmount) external view returns (uint256 netBNB, uint256 feeBNB) {  // 视图函数：估算卖出结果含手续费明细
        (netBNB, feeBNB) = helper.calculateBNBAmountOutWithFee(tokenAmount, bondingCurve[token], tradingFeeRate);  // 调用助手计算含手续费的卖出结果
    }

    /**
     * @notice 计算初始买入所需 BNB
     * @param totalSupply 总供应量
     * @param virtualBNBReserve 初始虚拟 BNB 储备
     * @param virtualTokenReserve 初始虚拟代币储备
     * @param percentageBP 购买百分比（基点）
     * @return totalPayment 总支付金额（含手续费）
     * @return preBuyFee 初始买入手续费
     */
    function calculateInitialBuyBNB(
        uint256 totalSupply,  // 代币总供应量
        uint256 virtualBNBReserve,  // 初始虚拟 BNB 储备
        uint256 virtualTokenReserve,  // 初始虚拟代币储备
        uint256 percentageBP  // 初始买入百分比（基点，如 5000 = 50%）
    ) external view returns (uint256 totalPayment, uint256 preBuyFee) {  // 视图函数：返回总支付金额和手续费
        if (percentageBP == 0) return (0, 0);  // 如果不进行初始买入（百分比为0），返回零值
        if (percentageBP > MAX_INITIAL_BUY_PERCENTAGE) revert InvalidParameters();  // 检查百分比不超过 99.9%，防止买空曲线

        (, uint256 bnbRequired,,) = _calculateInitialBuy(  // 调用内部函数计算初始买入，只需要 bnbRequired（消耗的BNB），忽略其他返回值
            totalSupply,  // 总供应量
            virtualBNBReserve,  // 虚拟 BNB 储备
            virtualTokenReserve,  // 虚拟代币储备
            percentageBP  // 买入百分比
        );
        preBuyFee = (bnbRequired * preBuyFeeRate) / 10000;  // 计算初始买入手续费 = 所需BNB × 初始买入费率 / 10000
        totalPayment = bnbRequired + preBuyFee;  // 总支付 = 所需BNB + 手续费，这是用户创建时需要额外支付的金额
    }

    // ============ 内部函数 ============

    /**
     * @notice 安全发送 BNB
     * @dev 处理合约接收者和失败回退
     */
    function _sendValue(address to, uint256 amount) internal {  // 内部函数：安全发送 BNB 到指定地址，处理合约接收者和发送失败的情况
        if (amount == 0) return;  // 如果金额为零，直接返回，不执行发送操作
        if (to == address(0)) {  // 如果目标地址为零地址（未设置）
            to = platformFeeReceiver;  // 将目标地址回退为平台费接收地址，确保 BNB 不会丢失
            require(to != address(0), "Platform fee receiver not set");  // 如果平台费接收地址也未设置，则回滚：确保 BNB 有去处
        }
        uint32 size;  // 目标地址的代码大小变量
        assembly {  // 内联汇编块：直接与 EVM 交互
            size := extcodesize(to)  // 获取目标地址的合约代码大小，>0 表示是合约地址，=0 表示是 EOA（外部账户）
        }
        if (size > 0) {  // 如果目标是合约地址（有代码）
            (bool ok,) = payable(to).call{value: amount}("");  // 使用低级 call 发送 BNB，空 calldata 触发合约的 receive 函数
            if (!ok) {  // 如果发送失败（合约的 receive 可能 revert 或消耗过多 gas）
                (bool fallbackSuccess,) = payable(platformFeeReceiver).call{value: amount}("");  // 回退方案：将 BNB 发送给平台费接收地址
                require(fallbackSuccess, "BNB_SEND_FAILED_TO_FALLBACK");  // 如果回退方案也失败，则回滚交易
                emit CreatorFeeRedirected(to, platformFeeReceiver, amount);  // 发射费用重定向事件：记录 BNB 从原目标转给了平台
            }
        } else {  // 如果目标是 EOA（外部账户，无代码）
            (bool ok,) = payable(to).call{value: amount}("");  // 使用低级 call 发送 BNB
            require(ok, "BNB_SEND_FAILED");  // 如果发送失败则回滚：EOA 发送失败通常是严重问题
        }
    }

    /**
     * @notice 创建归属计划
     * @dev 处理初始买入代币的锁仓释放
     */
    function _createVestingSchedules(
        address tokenAddress,  // 代币合约地址
        address beneficiary,  // 归属受益人地址（代币创建者）
        uint256 initialTokens,  // 初始买入获得的代币总量
        uint256 initialBuyPercentage,  // 初始买入百分比（基点）
        uint256 totalSupply,  // 代币总供应量
        VestingAllocation[] memory vestingAllocations  // 归属分配配置数组：每项指定数量、模式（线性/悬崖/销毁）、时长
    ) internal returns (uint256 tokensToTransfer) {  // 返回不需要锁仓而直接转移给创建者的代币数量
        uint256 totalVestedAmount;  // 需要归属释放的代币百分比总和（基点）
        uint256 totalBurnedAmount;  // 需要销毁的代币百分比总和（基点）

        // 统计归属和销毁数量
        for (uint256 i = 0; i < vestingAllocations.length; i++) {  // 遍历所有归属分配配置
            if (vestingAllocations[i].amount == 0) {  // 如果某项分配的数量为0
                revert InvalidAmountParameters();  // 回滚：不允许数量为零的分配项
            }
            if (vestingAllocations[i].mode == VestingMode.BURN) {  // 如果分配模式为"销毁"
                totalBurnedAmount += vestingAllocations[i].amount;  // 累加到销毁百分比总量中
            } else {  // 如果分配模式为"线性释放"或"悬崖释放"
                totalVestedAmount += vestingAllocations[i].amount;  // 累加到归属百分比总量中
                if (vestingAllocations[i].mode == VestingMode.LINEAR) {  // 如果是线性释放模式
                    if (vestingAllocations[i].duration == 0) {  // 检查锁仓时长不能为零
                        revert InvalidDurationParameters();  // 回滚：线性释放必须有非零时长
                    }
                    if (vestingAllocations[i].duration < minLockTime) {  // 检查锁仓时长不能短于最短锁仓时间
                        revert InvalidDurationParameters();  // 回滚：防止瞬间释放，确保最低锁仓期
                    }
                }
            }
        }

        if (initialBuyPercentage < totalVestedAmount + totalBurnedAmount) revert InvalidVestingParameters();  // 检查归属+销毁总量不超过初始买入百分比，逻辑上不能锁仓/销毁超过实际拥有的

        // 计算实际代币数量
        uint256 tokensToVest = (totalSupply * totalVestedAmount) / 10000;  // 将归属百分比转换为实际代币数 = 总供应量 × 归属百分比 / 10000
        uint256 tokensToBurn = (totalSupply * totalBurnedAmount) / 10000;  // 将销毁百分比转换为实际代币数 = 总供应量 × 销毁百分比 / 10000
        if (initialTokens < tokensToVest + tokensToBurn) revert InvalidParameters();  // 安全检查：初始买入代币必须足够覆盖归属+销毁

        tokensToTransfer = initialTokens - tokensToVest - tokensToBurn;  // 直接转移给创建者的代币 = 初始买入 - 归属锁仓 - 销毁

        // 执行销毁
        if (tokensToBurn > 0) {  // 如果有需要销毁的代币
            MetaNodeToken(tokenAddress).burn(tokensToBurn);  // 调用代币合约的销毁函数，永久减少流通量
            emit MetaNodeTokensBurned(tokenAddress, tokensToBurn);  // 发射代币销毁事件
        }

        // 创建归属计划
        if (tokensToVest > 0) {  // 如果有需要归属锁仓的代币
            VestingAllocation[] memory actualVestingAllocations = new VestingAllocation[](vestingAllocations.length);  // 创建新的归属分配数组，用于存储转换后的实际代币数量

            uint256 allocatedTokens;  // 已分配的代币累计数量，用于处理舍入误差
            TokenInfo memory info = tokenInfo[tokenAddress];  // 读取代币信息，获取开盘时间
            uint256 actualLaunchTime = info.launchTime;  // 获取开盘时间
            if (actualLaunchTime == 0) {  // 如果未设置开盘时间（0表示立即开盘）
                actualLaunchTime = block.timestamp;  // 使用当前区块时间作为实际开盘时间
            }

            int256 lastNonBurnIndex = - 1;  // 最后一个非销毁项的索引，初始为-1表示未找到
            for (uint256 i = 0; i < vestingAllocations.length; i++) {  // 遍历找到最后一个非销毁分配项的索引
                if (vestingAllocations[i].mode != VestingMode.BURN) {  // 如果当前项不是销毁模式
                    lastNonBurnIndex = int256(i);  // 更新最后一个非销毁项索引
                }
            }

            for (uint256 i = 0; i < vestingAllocations.length; i++) {  // 遍历所有分配项，计算实际代币数量
                uint256 allocationAmount;  // 当前项的实际代币分配数量
                if (vestingAllocations[i].mode == VestingMode.BURN) {  // 如果是销毁模式
                    allocationAmount = 0;  // 销毁项的归属分配数量设为0（代币已在上面销毁）
                } else if (int256(i) == lastNonBurnIndex) {  // 如果是最后一个非销毁项
                    allocationAmount = tokensToVest - allocatedTokens;  // 分配剩余所有归属代币，避免舍入误差导致总量不足
                } else {  // 其他非销毁项
                    allocationAmount = (totalSupply * vestingAllocations[i].amount) / 10000;  // 将百分比转换为实际代币数 = 总供应量 × 百分比 / 10000
                    allocatedTokens += allocationAmount;  // 累加已分配数量
                }
                actualVestingAllocations[i] = VestingAllocation({  // 构建实际的归属分配项
                    amount: allocationAmount,  // 实际代币数量
                    launchTime: actualLaunchTime,  // 使用实际开盘时间作为归属起始时间
                    duration: vestingAllocations[i].duration,  // 锁仓时长（秒）
                    mode: vestingAllocations[i].mode  // 归属模式（线性/悬崖）
                });
            }

            IERC20(tokenAddress).approve(address(vesting), tokensToVest);  // 授权归属合约操作归属代币数量
            vesting.createVestingSchedules(  // 调用归属合约创建锁仓释放计划
                tokenAddress,  // 代币地址
                beneficiary,  // 归属受益人
                actualVestingAllocations  // 实际归属分配配置
            );

            emit VestingCreated(  // 发射归属计划创建事件
                tokenAddress,  // 代币地址
                beneficiary,  // 归属受益人
                tokensToVest,  // 归属代币总量
                actualVestingAllocations.length  // 归属分配项数
            );
        }

        return tokensToTransfer;  // 返回需要直接转移给创建者的代币数量（扣除归属和销毁后的剩余）
    }

    /**
     * @notice 计算初始买入数量
     * @dev 使用恒定乘积公式反推
     */
    function _calculateInitialBuy(
        uint256 totalSupply,  // 代币总供应量
        uint256 virtualBNBReserve,  // 虚拟 BNB 储备（曲线初始参数）
        uint256 virtualTokenReserve,  // 虚拟代币储备（曲线初始参数）
        uint256 percentageBP  // 初始买入百分比（基点，如 5000 = 50%）
    ) internal pure returns (  // 纯内部函数：不读写状态，仅根据输入计算结果
        uint256 tokensOut,  // 初始买入获得的代币数量
        uint256 bnbRequired,  // 初始买入需要的 BNB 数量
        uint256 newBNBReserve,  // 调整后的虚拟 BNB 储备
        uint256 newTokenReserve  // 调整后的虚拟代币储备
    ) {
        // 注意：这个检查是防御性的，因为调用者（createToken 和 calculateInitialBuyBNB）已经检查过了
        // 但如果 percentageBP 为 0，这里不会检查，因为 0 是合法的（表示不进行初始买入）
        if (percentageBP > 0 && percentageBP > MAX_INITIAL_BUY_PERCENTAGE) revert InvalidPercentageBP();  // 防御性检查：百分比 > 0 且超过 99.9% 则回滚

        // 计算目标代币数量
        tokensOut = (totalSupply * percentageBP) / 10000;  // 初始买入代币数 = 总供应量 × 百分比 / 10000，如 1000000 × 50% = 500000

        // 使用恒定乘积公式计算
        uint256 k = virtualBNBReserve * virtualTokenReserve;  // 恒定乘积 k = BNB储备 × 代币储备，x * y = k 是联合曲线的核心不变量
        newTokenReserve = virtualTokenReserve - tokensOut;  // 新代币储备 = 原代币储备 - 买入代币，代币从储备中取出
        newBNBReserve = k / newTokenReserve;  // 新 BNB 储备 = k / 新代币储备，根据恒定乘积反推：买后代币减少，BNB储备必须增大
        bnbRequired = newBNBReserve - virtualBNBReserve;  // 所需 BNB = 新BNB储备 - 原BNB储备，即本次买入实际消耗的 BNB

        return (tokensOut, bnbRequired, newBNBReserve, newTokenReserve);  // 返回四元组：获得的代币、消耗的BNB、调整后的两个储备值
    }

    /**
     * @notice 更新代币状态
     */
    function _changeTokenStatus(address token, TokenStatus newStatus) internal {  // 内部函数：更新指定代币的状态并发射状态变更事件
        TokenStatus oldStatus = tokenInfo[token].status;  // 读取当前状态，用于事件记录
        tokenInfo[token].status = newStatus;  // 写入新状态到存储
        emit TokenStatusChanged(token, oldStatus, newStatus);  // 发射状态变更事件：记录从旧状态到新状态的转换
    }

    /**
     * @notice 验证代币可交易
     */
    function _onlyTradingToken(address token) internal view {  // 内部视图函数：验证代币处于可交易状态且已开盘
        TokenInfo memory info = tokenInfo[token];  // 读取代币信息到内存
        if (info.status != TokenStatus.TRADING) {  // 检查代币当前状态必须为 TRADING
            revert TokenNotTrading();  // 否则回滚：代币可能被暂停、拉黑、已毕业或待毕业
        }
        if (block.timestamp < info.launchTime) {  // 检查当前时间是否已到开盘时间
            revert TokenNotLaunchedYet();  // 否则回滚：在开盘时间之前不可交易，等待开盘
        }
    }

    // ============ 管理函数 ============

    /**
     * @notice 设置平台费接收地址
     */
    function setPlatformFeeReceiver(address _receiver) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_receiver == address(0)) revert ZeroAddress();  // 检查新地址不为零地址，防止费用转入无效地址
        address oldPlatformFeeReceiver = platformFeeReceiver;  // 保存旧地址用于事件记录
        platformFeeReceiver = _receiver;  // 更新平台费接收地址
        emit PlatformFeeReceiverChanged(oldPlatformFeeReceiver, _receiver);  // 发射地址变更事件
    }

    /**
     * @notice 设置毕业费接收地址
     */
    function setGraduateFeeReceiver(address _receiver) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_receiver == address(0)) revert ZeroAddress();  // 检查新地址不为零地址
        address oldGraduateFeeReceiver = graduateFeeReceiver;  // 保存旧地址用于事件记录
        graduateFeeReceiver = _receiver;  // 更新毕业费接收地址
        emit GraduateFeeReceiverChanged(oldGraduateFeeReceiver, _receiver);  // 发射地址变更事件
    }

    /**
     * @notice 设置工厂合约
     */
    function setFactory(address _factory) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_factory == address(0)) revert ZeroAddress();  // 检查新地址不为零地址
        address oldFactory = address(factory);  // 保存旧地址用于事件记录
        factory = IMetaNodeFactory(_factory);  // 更新工厂合约引用
        emit FactoryChanged(oldFactory, _factory);  // 发射合约变更事件
    }

    /**
     * @notice 设置助手合约
     */
    function setHelper(address _helper) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_helper == address(0)) revert ZeroAddress();  // 检查新地址不为零地址
        address oldHelper = address(helper);  // 保存旧地址用于事件记录
        helper = IMetaNodeHelper(_helper);  // 更新助手合约引用
        emit HelperChanged(oldHelper, _helper);  // 发射合约变更事件
    }

    /**
     * @notice 设置归属合约
     */
    function setVesting(address _vesting) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_vesting == address(0)) revert ZeroAddress();  // 检查新地址不为零地址
        address oldVesting = _vesting;  // 保存传入地址作为旧地址（注意：这里用的是新地址，事件语义可能有误，但保持原有逻辑不变）
        vesting = IMetaNodeVesting(_vesting);  // 更新归属合约引用
        emit VestingChanged(oldVesting, _vesting);  // 发射合约变更事件
    }

    /**
     * @notice 设置保证金接收地址
     */
    function setMarginReceiver(address _marginReceiver) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_marginReceiver == address(0)) revert ZeroAddress();  // 检查新地址不为零地址
        address oldMarginReceiver = marginReceiver;  // 保存旧地址用于事件记录
        marginReceiver = _marginReceiver;  // 更新保证金接收地址
        emit MarginReceiverChanged(oldMarginReceiver, _marginReceiver);  // 发射地址变更事件
    }

    /**
     * @notice 设置创建费用
     * @param _fee 新费用（最大 0.1 BNB）
     */
    function setCreationFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_fee > 0.1 ether) revert InvalidAmountParameters();  // 限制最大创建费为 0.1 BNB，防止过高费用
        creationFee = _fee;  // 更新创建费
        emit CreationFeeChanged(_fee);  // 发射费用变更事件
    }

    /**
     * @notice 设置初始买入费率
     * @param _rate 费率基点（最大 600 = 6%）
     */
    function setPreBuyFeeRate(uint256 _rate) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_rate > 600) revert InvalidAmountParameters();  // 限制最大初始买入费率为 600 基点 = 6%，防止过高费率
        preBuyFeeRate = _rate;  // 更新初始买入费率
        emit PreBuyFeeRateChanged(_rate);  // 发射费率变更事件
    }

    /**
     * @notice 设置交易费率
     * @param _rate 费率基点（最大 200 = 2%）
     */
    function setTradingFeeRate(uint256 _rate) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_rate > 200) revert InvalidAmountParameters();  // 限制最大交易费率为 200 基点 = 2%，防止单笔交易费用过高
        tradingFeeRate = _rate;  // 更新交易费率
        emit TradingFeeRateChanged(_rate);  // 发射费率变更事件
    }

    /**
     * @notice 设置毕业费率
     * @param _platformRate 平台费率（最大 1100 = 11%）
     * @param _creatorRate 创作者费率（最大 500 = 5%）
     */
    function setGraduationFeeRates(uint256 _platformRate, uint256 _creatorRate) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        if (_platformRate > 1100 || _creatorRate > 500) revert InvalidAmountParameters();  // 限制毕业平台费率最大 1100 基点=11%，创作者费率最大 500 基点=5%
        graduationPlatformFeeRate = _platformRate;  // 更新毕业平台费率
        graduationCreatorFeeRate = _creatorRate;  // 更新毕业创作者费率
        emit GraduationFeeRatesChanged(_platformRate, _creatorRate);  // 发射费率变更事件
    }

    /**
     * @notice 设置最小锁仓时间
     */
    function setMinLockTime(uint256 _time) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用
        minLockTime = _time;  // 更新最短锁仓时间（秒），影响归属计划中线性释放模式的最小时长
        emit MinLockTimeChanged(_time);  // 发射时间变更事件
    }

    /**
     * @notice 暂停合约
     */
    function pause() external onlyRole(PAUSER_ROLE) {  // 仅 PAUSER_ROLE 可调用
        _pause();  // 调用 OpenZeppelin Pausable 的内部暂停函数，设置暂停标志，whenNotPaused 修饰的函数将回滚
    }

    /**
     * @notice 恢复合约
     */
    function unpause() external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用（注意：暂停和恢复权限不同，恢复需要更高级别权限）
        _unpause();  // 调用 OpenZeppelin Pausable 的内部恢复函数，清除暂停标志
    }

    /**
     * @notice 紧急提取资产
     * @param token 代币地址（address(0) 为 BNB）
     * @param amount 提取数量
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {  // 仅 ADMIN_ROLE 可调用，紧急情况下提取合约中的资产
        if (token == address(0)) {  // 如果代币地址为零地址
            payable(msg.sender).transfer(amount);  // 提取 BNB：将指定数量的 BNB 转给管理员
        } else {  // 如果代币地址非零
            IERC20(token).safeTransfer(msg.sender, amount);  // 安全提取 ERC20 代币：将指定数量的代币转给管理员
        }
    }

    /**
     * @notice 授权合约升级
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}  // UUPS 升级授权函数：仅 ADMIN_ROLE 可授权升级到新实现合约地址，空函数体表示授权通过

    /**
     * @notice 接收 BNB
     */
    receive() external payable {}  // 回退接收函数：允许合约接收 BNB 转账（如毕业添加流动性时的退款、用户错误转账等），空函数体表示无条件接收
}
