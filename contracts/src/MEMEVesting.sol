// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;  // 编译器版本声明：要求 Solidity 版本 >= 0.8.20 且 < 0.9.0；0.8.x 内置算术溢出/下溢检查

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";  // 导入可升级版本的初始化器：替代 constructor，确保初始化函数只能被调用一次
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";  // 导入 UUPS 可升级模式：升级逻辑放在实现合约中（而非代理合约），比透明代理更省 gas
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";  // 导入可升级版本的访问控制：基于角色的权限管理（RBAC），支持合约升级
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";  // 导入可升级版本的暂停机制：允许管理员暂停/恢复合约，暂停时关键操作被阻止
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";  // 导入可升级版本的重入保护：防止合约函数在执行中被重入调用，避免重入攻击
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";  // 导入 ERC20 标准接口：定义了代币的基本操作（transfer、approve、balanceOf 等）
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";  // 导入安全 ERC20 操作库：处理不合规 ERC20 代币（如 USDT 不返回 bool），确保转账操作安全
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";  // 导入可销毁 ERC20 扩展：提供 burn 函数让持有者销毁自己的代币（本合约中未直接使用，但作为接口参考）
import {IMEMEVesting} from "./interfaces/IMEMEVesting.sol";  // 导入归属合约接口：定义了归属合约必须实现的外部函数、事件和数据结构

/**
 * @title MEMEVesting
 * @author MetaNode Team
 * @notice 代币归属（锁仓释放）合约
 *
 * ============ 合约概述 ============
 * 管理 MEME 代币的锁仓和释放机制。
 * 当创建者在发币时进行"初始买入"，可以选择将部分代币锁定，
 * 按照指定的模式和时间表逐步释放。
 *
 * ============ 升级模式说明 ============
 * 本合约使用 UUPS（Universal Upgradeable Proxy Standard）升级模式：
 * - 代理合约存储状态，逻辑合约执行代码
 * - 升级时只需部署新逻辑合约，代理指向新地址
 * - 升级权限由 _authorizeUpgrade 控制（仅 ADMIN_ROLE）
 * - 构造函数中 _disableInitializers() 防止逻辑合约被直接初始化
 *
 * ============ 归属模式 ============
 *
 * 【BURN - 销毁模式】
 * 代币在创建时被永久销毁，不会释放给任何人。
 * 用于通缩机制，提升剩余代币价值。
 * 计算：可领取量始终为 0
 *
 * 【CLIFF - 悬崖模式】
 * 代币在整个归属期内完全锁定，到期后一次性全部解锁。
 * 适用于确保创建者长期持有的场景。
 *
 * 时间线：
 * |------- 锁定期 -------|一次性全部解锁
 * 0%                     100%
 *
 * 计算公式：
 * - 当前时间 < endTime：vestedAmount = 0
 * - 当前时间 >= endTime：vestedAmount = totalAmount
 * - claimable = vestedAmount - claimedAmount
 *
 * 【LINEAR - 线性模式】
 * 代币从开始时间到结束时间按比例逐步解锁。
 * 可领取数量 = 总量 × (已过时间 / 总时长) - 已领取数量
 *
 * 时间线：
 * |------- 逐步释放 -------|
 * 10%  20%  30%  ...  90%  100%
 *
 * 计算公式：
 * - 当前时间 <= startTime：vestedAmount = 0
 * - 当前时间 >= endTime：vestedAmount = totalAmount
 * - startTime < 当前时间 < endTime：
 *   vestedAmount = totalAmount × (当前时间 - startTime) / (endTime - startTime)
 * - claimable = vestedAmount - claimedAmount
 *
 * ============ 存储结构 ============
 *
 * vestingSchedules[token][beneficiary][scheduleId] = VestingSchedule
 *
 * 每个用户可以对同一代币有多个归属计划，
 * 每个计划独立计算可领取数量。
 *
 * ============ 调用流程 ============
 *
 * 1. MEMECore.createToken() 创建代币时
 *    → 调用 createVestingSchedules() 创建归属计划
 *
 * 2. 受益人等待归属期
 *    → 调用 getClaimableAmount() 查看可领取数量
 *
 * 3. 受益人领取代币
 *    → 调用 claim() 领取单个计划，或 claimAll() 领取全部
 *
 * 4. 管理员紧急操作（如需要）
 *    → 调用 revokeVestingSchedule() 撤销计划
 *    → 调用 emergencyWithdrawToken() 紧急提取
 *
 * ============ 访问控制 ============
 * - DEFAULT_ADMIN_ROLE：合约部署者，可授权其他角色
 * - ADMIN_ROLE：管理员，可撤销计划、紧急提取、暂停合约
 * - OPERATOR_ROLE：操作员（MEMECore），可创建归属计划
 */
contract MEMEVesting is IMEMEVesting, Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {  // 合约声明：继承接口和五个可升级基础合约；继承顺序影响初始化调用顺序
    using SafeERC20 for IERC20;  // 将 SafeERC20 库函数附加到 IERC20 类型；使得 IERC20(token).safeTransfer(...) 等安全操作可用；处理 USDT 等不返回 bool 的代币

    // ============ 角色常量 ============

    /**
     * @notice 管理员角色
     * @dev 权限：参数配置、紧急操作、撤销归属计划、暂停/恢复合约
     * 由 initialize 函数授予初始管理员
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");  // 管理员角色标识：keccak256 哈希 "ADMIN_ROLE" 得到 32 字节常量；public 允许外部查询，constant 不占用存储槽

    /**
     * @notice 操作员角色
     * @dev 权限：创建归属计划（createVestingSchedules）
     * 通常授予 MEMECore 合约，因为归属计划在创建代币时同步建立
     */
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");  // 操作员角色标识：keccak256 哈希 "OPERATOR_ROLE" 得到 32 字节常量；通常授予 MEMECore 合约地址

    // ============ 存储映射 ============

    /**
     * @notice 归属计划存储
     * @dev 三层映射：token地址 => 受益人地址 => 计划ID => VestingSchedule
     * 每个受益人可以对同一代币拥有多个独立的归属计划
     * 例如：用户可能对某代币有 CLIFF 和 LINEAR 两种计划
     */
    mapping(address => mapping(address => mapping(uint256 => VestingSchedule))) public vestingSchedules;  // 三层嵌套映射：第一层 key 是代币地址，第二层 key 是受益人地址，第三层 key 是计划 ID，value 是归属计划结构体

    /**
     * @notice 归属计划计数
     * @dev token地址 => 受益人地址 => 计划数量
     * 用于分配新的计划ID（自增），也用于遍历用户的所有计划
     * 新计划 ID = 当前计数（从 0 开始）
     */
    mapping(address => mapping(address => uint256)) public scheduleCount;  // 双层映射：记录每个代币下每个受益人的归属计划数量；新计划的 ID = scheduleCount[token][beneficiary]（从 0 自增）

    /**
     * @notice 用户总归属数量
     * @dev token地址 => 受益人地址 => 总归属代币数
     * 便于快速查询用户的归属总量（包含已领取和未领取）
     * 注意：此值包含 BURN 模式的数量（虽然 BURN 不可领取）
     */
    mapping(address => mapping(address => uint256)) public totalVestedAmount;  // 双层映射：记录每个代币下每个受益人的归属代币总量；包含所有模式（含 BURN）的 amount；用于统计和撤销时扣减

    /**
     * @notice 合约锁定总量
     * @dev token地址 => 合约内锁定的代币总量（实际持有的代币）
     * 用于紧急提款时的余额校验，以及追踪合约资产
     * 注意：不包含 BURN 模式（BURN 代币未转入合约）
     */
    mapping(address => uint256) public totalTokenLocked;  // 单层映射：记录每种代币在合约中的锁定总量；仅包含非 BURN 模式的代币（BURN 模式的代币已销毁，不在合约内）；领取和撤销时递减

    // ============ 构造函数 ============

    /**
     * @notice 构造函数
     * @dev UUPS 升级模式要求：
     * 1. 逻辑合约的构造函数中禁用初始化器
     * 2. 实际初始化通过代理合约调用 initialize 完成
     * 3. 防止攻击者直接初始化逻辑合约
     *
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    /// @custom:oz-upgrades-unsafe-allow constructor  // OpenZeppelin 升级插件注解：允许此构造函数通过升级安全检查（默认构造函数会被标记为不安全）
    constructor() {  // 构造函数：在逻辑合约部署时执行一次
        _disableInitializers();  // 禁用初始化器：防止逻辑合约被直接调用 initialize；只有通过代理合约才能初始化；这是 UUPS 升级模式的标准做法，防止攻击者直接在逻辑合约上初始化并获得管理员权限
    }

    // ============ 初始化函数 ============

    /**
     * @notice 初始化归属合约
     * @dev 仅在代理部署时调用一次（initializer 修饰符保证）
     * 初始化 OpenZeppelin 基础合约和角色权限
     *
     * @param _admin 管理员地址，获得 DEFAULT_ADMIN_ROLE 和 ADMIN_ROLE
     * @param _operator 操作员地址（通常是 MEMECore），获得 OPERATOR_ROLE
     *
     * ============ 初始化顺序 ============
     * 1. __AccessControl_init() - 访问控制
     * 2. __Pausable_init() - 可暂停
     * 3. __ReentrancyGuard_init() - 重入保护
     * 4. __UUPSUpgradeable_init() - UUPS 升级
     * 5. 授予角色
     */
    function initialize(
        address _admin,  // 管理员地址：将获得 DEFAULT_ADMIN_ROLE（可管理所有角色）和 ADMIN_ROLE（可执行管理操作）
        address _operator  // 操作员地址：通常是 MEMECore 合约地址，获得 OPERATOR_ROLE（可创建归属计划）
    ) public initializer {  // public：可从外部（代理合约）调用；initializer：确保此函数只能被调用一次，后续调用会回滚
        __AccessControl_init();  // 初始化访问控制模块：设置基础存储槽，必须在授予角色之前调用
        __Pausable_init();  // 初始化暂停模块：设置暂停相关的存储槽，初始状态为未暂停
        __ReentrancyGuard_init();  // 初始化重入保护模块：设置重入锁状态，初始状态为未锁定
        __UUPSUpgradeable_init();  // 初始化 UUPS 升级模块：设置升级相关的存储槽

        // 授予管理员角色
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);  // 授予 _admin 默认管理员角色：此角色是 OpenZeppelin AccessControl 的最高权限角色，可以授予和撤销任何其他角色
        _grantRole(ADMIN_ROLE, _admin);  // 授予 _admin 自定义管理员角色：拥有暂停/恢复合约、撤销归属计划、紧急提取代币等管理权限

        // 授予操作员角色（MEMECore 合约）
        _grantRole(OPERATOR_ROLE, _operator);  // 授予 _operator 操作员角色：允许调用 createVestingSchedules 创建归属计划；_operator 通常是 MEMECore 合约地址
    }

    // ============ 核心业务函数 ============

    /**
     * @notice 批量创建归属计划
     * @dev 仅限 OPERATOR_ROLE（MEMECore）调用
     * 在创建代币时同步建立归属计划
     *
     * @param token 代币地址
     * @param beneficiary 受益人地址（通常是代币创建者）
     * @param allocations 归属分配数组，每个元素定义一个归属计划
     * @return scheduleIds 创建的计划ID数组
     *
     * ============ 执行流程 ============
     *
     * 1. 【参数校验】
     *    - token 和 beneficiary 非零地址
     *    - allocations 数组非空
     *
     * 2. 【计算总量】
     *    - 累加所有非 BURN 分配的代币数量
     *    - BURN 模式的代币在 MEMECore 中已销毁，不转入本合约
     *
     * 3. 【转入代币】
     *    - 从调用者（MEMECore）转入总归属代币到本合约
     *    - 使用 SafeERC20 防止转账失败
     *
     * 4. 【创建计划】
     *    - 为每个分配创建独立的 VestingSchedule
     *    - 分配唯一的 scheduleId（自增）
     *    - 设置开始时间和结束时间
     *    - BURN 模式也需要创建记录（用于追踪和统计）
     *
     * 5. 【更新统计】
     *    - 更新用户总归属数量（totalVestedAmount）
     *    - 更新合约锁定总量（totalTokenLocked，不含 BURN）
     *    - 触发 VestingScheduleCreated 事件
     */
    function createVestingSchedules(
        address token,  // 代币合约地址：归属的 ERC20 代币地址
        address beneficiary,  // 受益人地址：代币归属的接收者，通常是代币创建者
        VestingAllocation[] calldata allocations  // 归属分配数组：calldata 表示数据直接从调用数据读取，不复制到内存，节省 gas；每个元素包含 mode（模式）、amount（数量）、launchTime（开始时间）、duration（持续时长）
    ) external override onlyRole(OPERATOR_ROLE) whenNotPaused returns (uint256[] memory scheduleIds) {  // external：仅外部调用；override：实现接口函数；onlyRole(OPERATOR_ROLE)：仅操作员可调用；whenNotPaused：合约未暂停时可调用；returns：返回创建的计划 ID 数组
        // ======== 第一步：参数校验 ========
        // 1. 参数校验：确保地址有效且分配数组非空
        if (token == address(0) || beneficiary == address(0)) revert InvalidAddressParameters();  // 校验代币地址和受益人地址均不为零地址；零地址表示无效，若传入则代币会被永久锁定
        if (allocations.length == 0) revert InvalidLengthParameters();  // 校验分配数组不为空；空数组意味着无需创建任何归属计划，属于无效调用

        // 初始化返回值：创建与 allocations 等长的数组，用于存储每个分配的计划 ID
        scheduleIds = new uint256[](allocations.length);  // 在内存中分配新数组，长度等于 allocations 的长度；所有元素初始值为 0

        // ======== 第二步：计算需要转入合约的代币总量 ========
        // 2. 计算总量：累加所有非 BURN 分配的代币数量
        // BURN 模式的代币已在 MEMECore 中销毁，不需要转入本合约
        uint256 totalAmount = 0;  // 累计需要从调用者转入本合约的代币总量；初始为 0
        for (uint256 i = 0; i < allocations.length; i++) {  // 遍历所有归属分配
            if (allocations[i].mode != VestingMode.BURN) {  // 仅非 BURN 模式需要转入代币；BURN 模式的代币已在 MEMECore 中直接销毁，不需要转入归属合约
                // 非 BURN 模式必须有大于零的数量
                if (allocations[i].amount == 0) revert InvalidAmountParameters();  // 非 BURN 模式的数量必须大于 0；否则没有代币可供归属，属于无效参数
                totalAmount += allocations[i].amount;  // 累加非 BURN 模式的代币数量到总量中
            }
        }

        // ======== 第三步：转入代币 ========
        // 3. 转入代币：从调用者（MEMECore）转入总归属代币
        // 只有非 BURN 的代币需要转入（BURN 已销毁）
        if (totalAmount > 0) {  // 仅当有代币需要转入时执行转账；避免无意义的 ERC20 调用（节省 gas）
            IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);  // 安全转账：从调用者（MEMECore）将 totalAmount 数量的代币转入本合约；使用 safeTransferFrom 需要调用者事先 approve；safeTransferFrom 处理不返回 bool 的代币
        }

        // ======== 第四步：创建归属计划 ========
        // 4. 创建计划：为每个分配创建独立的归属计划
        for (uint256 i = 0; i < allocations.length; i++) {  // 遍历所有归属分配
            // 分配新的计划ID（自增）
            uint256 scheduleId = scheduleCount[token][beneficiary];  // 获取当前计划数量作为新计划的 ID（从 0 开始自增）
            scheduleCount[token][beneficiary]++;  // 计划数量加 1，为下次创建做准备

            // 计算时间参数
            // launchTime 为 0 表示使用当前区块时间
            uint256 startTime = allocations[i].launchTime;  // 读取分配中指定的开始时间
            if (startTime == 0) {  // 如果 launchTime 为 0，表示未指定开始时间
                startTime = block.timestamp;  // 使用当前区块时间戳作为开始时间；block.timestamp 是当前区块的 Unix 时间戳（秒）
            }
            // 结束时间 = 开始时间 + 归属期限
            uint256 endTime = startTime + allocations[i].duration;  // 计算归属结束时间：开始时间 + 持续时长（秒）；duration 为 0 表示即时解锁

            // 创建归属计划结构体
            vestingSchedules[token][beneficiary][scheduleId] = VestingSchedule({  // 在三层映射中存储归属计划；key 为 (token, beneficiary, scheduleId)
                totalAmount: allocations[i].amount,    // 锁定总量：此计划归属的代币总数量
                startTime: startTime,                  // 归属开始时间：从此时间起开始计算归属进度
                endTime: endTime,                      // 归属结束时间：此时间后代币全部解锁
                claimedAmount: 0,                      // 已领取数量：初始为 0，每次领取后递增
                revoked: false,                        // 撤销标志：初始为 false，管理员撤销后设为 true
                mode: allocations[i].mode              // 归属模式：BURN/CLIFF/LINEAR，决定解锁计算方式
            });

            scheduleIds[i] = scheduleId;  // 将新创建的计划 ID 存入返回数组中的对应位置

            // ======== 第五步：更新统计信息 ========
            // 5. 更新统计信息
            totalVestedAmount[token][beneficiary] += allocations[i].amount;  // 累加用户对该代币的归属总量；包含所有模式（含 BURN）的 amount
            // BURN 模式的代币未转入合约，不计入锁定总量
            if (allocations[i].mode != VestingMode.BURN) {  // 仅非 BURN 模式的代币才计入合约锁定总量
                totalTokenLocked[token] += allocations[i].amount;  // 累加该代币在合约中的锁定总量；用于追踪合约实际持有的代币数量
            }

            // 触发归属计划创建事件
            emit VestingScheduleCreated(  // 发出 VestingScheduleCreated 事件，便于链下监听和索引
                token,  // 代币地址
                beneficiary,  // 受益人地址
                scheduleId,  // 计划 ID
                allocations[i].amount,  // 归属代币数量
                startTime,  // 归属开始时间
                endTime  // 归属结束时间
            );
        }
    }

    /**
     * @notice 领取单个归属计划的代币
     * @dev 防重入保护（nonReentrant），暂停时不可领取（whenNotPaused）
     *
     * @param token 代币地址
     * @param scheduleId 计划ID
     * @return claimableAmount 实际领取的数量
     *
     * ============ 执行流程 ============
     *
     * 1. 【读取计划】
     *    - 获取调用者（msg.sender）的指定 VestingSchedule
     *    - 验证计划存在（totalAmount > 0）
     *    - 验证计划未撤销（revoked == false）
     *
     * 2. 【计算可领取】
     *    - 调用 _calculateClaimableAmount 内部函数
     *    - BURN 模式返回 0
     *    - CLIFF 模式：未到期 = 0，到期后 = 全部
     *    - LINEAR 模式：按时间比例计算
     *
     * 3. 【更新状态】
     *    - 增加已领取数量（claimedAmount += claimableAmount）
     *    - 减少合约锁定总量（totalTokenLocked -= claimableAmount）
     *
     * 4. 【转移代币】
     *    - 将可领取代币转给调用者（受益人）
     *    - 使用 SafeERC20 确保转账安全
     *    - 触发 TokensClaimed 事件
     */
    function claim(
        address token,  // 代币合约地址
        uint256 scheduleId  // 要领取的归属计划 ID
    ) public override nonReentrant whenNotPaused returns (uint256 claimableAmount) {  // public：允许外部和内部调用；override：实现接口；nonReentrant：防重入锁，防止递归调用；whenNotPaused：合约未暂停时可调用；returns：返回实际领取的代币数量
        // ======== 第一步：读取并验证归属计划 ========
        // 1. 读取计划：获取调用者的归属计划
        VestingSchedule storage schedule = vestingSchedules[token][msg.sender][scheduleId];  // 从三层映射中获取归属计划的存储指针；storage 表示直接引用存储，修改会影响链上状态；msg.sender 即为受益人

        // 验证计划存在：totalAmount 为 0 表示该 ID 未使用
        if (schedule.totalAmount == 0) revert ScheduleNotFound();  // 如果计划总量为 0，说明此 ID 不存在（未创建或 ID 越界）；回滚交易并返回 ScheduleNotFound 错误

        // 验证计划未撤销
        if (schedule.revoked) revert ScheduleRevoked();  // 如果计划已被管理员撤销，不可再领取；回滚交易并返回 ScheduleRevoked 错误

        // ======== 第二步：计算可领取数量 ========
        // 2. 计算可领取数量
        claimableAmount = _calculateClaimableAmount(schedule);  // 调用内部函数计算当前可领取的代币数量；根据模式（BURN/CLIFF/LINEAR）和时间计算
        if (claimableAmount == 0) revert NoClaimableAmount();  // 如果可领取数量为 0（尚未解锁或已全部领取），回滚交易；避免无意义的零转账

        // ======== 第三步：更新状态 ========
        // 3. 更新状态：标记已领取
        schedule.claimedAmount += claimableAmount;  // 增加该计划的已领取数量；下次计算可领取量时会扣除这部分，防止重复领取
        totalTokenLocked[token] -= claimableAmount;  // 减少该代币在合约中的锁定总量；反映代币已从合约转出

        // ======== 第四步：转移代币 ========
        // 4. 转移代币：将代币转给受益人
        IERC20(token).safeTransfer(msg.sender, claimableAmount);  // 安全转账：将可领取数量的代币从本合约转给调用者（受益人）；使用 safeTransfer 处理不合规 ERC20 代币

        // 触发领取事件
        emit TokensClaimed(token, msg.sender, scheduleId, claimableAmount);  // 发出 TokensClaimed 事件，记录代币地址、受益人、计划 ID 和领取数量；便于链下监听和索引
    }

    /**
     * @notice 领取所有归属计划的代币
     * @dev 遍历所有计划，一次性领取全部可领取代币
     * 比多次调用 claim() 更省 gas
     *
     * @param token 代币地址
     * @return totalClaimed 总领取数量
     *
     * ============ 执行流程 ============
     * 1. 获取用户对该代币的所有计划数量
     * 2. 遍历每个计划，计算可领取数量
     * 3. 跳过不存在或已撤销的计划
     * 4. 批量更新状态并累计领取数量
     * 5. 一次性转移总领取数量
     */
    function claimAll(
        address token  // 代币合约地址：领取此代币的所有可领取归属计划
    ) external override nonReentrant whenNotPaused returns (uint256 totalClaimed) {  // external：仅外部调用；override：实现接口；nonReentrant：防重入；whenNotPaused：未暂停；returns：返回总领取数量
        // 获取用户对该代币的计划数量
        uint256 count = scheduleCount[token][msg.sender];  // 读取该用户对此代币的归属计划总数；用于遍历所有计划（ID 从 0 到 count-1）

        // 遍历所有计划
        for (uint256 i = 0; i < count; i++) {  // 遍历每个归属计划；i 为计划 ID
            VestingSchedule storage schedule = vestingSchedules[token][msg.sender][i];  // 获取第 i 个归属计划的存储指针

            // 跳过不存在或已撤销的计划
            if (schedule.totalAmount == 0 || schedule.revoked) continue;  // 如果计划不存在（totalAmount == 0）或已被撤销（revoked == true），跳过此计划；continue 跳到下一次循环

            // 计算可领取数量
            uint256 claimableAmount = _calculateClaimableAmount(schedule);  // 调用内部函数计算此计划当前可领取的代币数量
            if (claimableAmount > 0) {  // 仅当有可领取数量时才更新状态
                // 更新状态
                schedule.claimedAmount += claimableAmount;  // 增加此计划的已领取数量；防止重复领取
                totalTokenLocked[token] -= claimableAmount;  // 减少该代币在合约中的锁定总量
                totalClaimed += claimableAmount;  // 累加到总领取数量；最终会一次性转给用户

                // 触发单个计划的领取事件
                emit TokensClaimed(token, msg.sender, i, claimableAmount);  // 为每个领取的计划分别发出事件；便于追踪每个计划的领取情况
            }
        }

        // 一次性转移总领取数量（如果大于 0）
        if (totalClaimed > 0) {  // 仅当有代币需要领取时执行转账
            IERC20(token).safeTransfer(msg.sender, totalClaimed);  // 安全转账：将所有计划的可领取代币一次性转给用户；比逐个转账更省 gas（只需一次 ERC20 调用）
        }
    }

    // ============ 内部函数 ============

    /**
     * @notice 计算归属计划的可领取数量
     * @dev 核心计算函数，根据模式和时间计算可领取量
     *
     * @param schedule 归属计划（memory，只读）
     * @return 可领取代币数量
     *
     * ============ 计算逻辑 ============
     *
     * 【BURN 模式】
     * 始终返回 0（代币已销毁，不可领取）
     *
     * 【时间未开始】
     * 当前时间 <= startTime → 返回 0
     *
     * 【已完全解锁】
     * 当前时间 >= endTime → vestedAmount = totalAmount
     * 所有代币已解锁，可领取剩余全部
     *
     * 【进行中 - CLIFF】
     * startTime < 当前时间 < endTime → 返回 0
     * CLIFF 模式在到期前不可领取任何代币
     *
     * 【进行中 - LINEAR】
     * vestedAmount = totalAmount × (当前时间 - 开始时间) / (结束时间 - 开始时间)
     *
     * 【最终计算】
     * claimable = vestedAmount - claimedAmount
     * 如果 vestedAmount <= claimedAmount，返回 0
     */
    function _calculateClaimableAmount(
        VestingSchedule memory schedule  // 归属计划结构体，使用 memory 传递（只读，不修改存储）；因为只需读取数据用于计算
    ) private view returns (uint256) {  // private：仅本合约内部可调用；view：只读，不修改状态；returns：返回可领取的代币数量
        // ======== BURN 模式：代币已销毁，不可领取 ========
        if (schedule.mode == VestingMode.BURN) {  // 如果归属模式为 BURN（销毁）
            return 0;  // BURN 模式的代币在创建时已被永久销毁，不存在于任何合约中，因此始终不可领取；返回 0
        }

        // ======== 归属未开始：当前时间 <= 开始时间 ========
        if (block.timestamp <= schedule.startTime) {  // 如果当前区块时间戳 <= 归属开始时间，说明归属期尚未开始
            return 0;  // 归属尚未开始，没有代币解锁，返回 0
        }

        // 声明已解锁数量变量
        uint256 vestedAmount;  // 已解锁数量：根据时间和模式计算得出的已归属（已解锁）代币数量；默认初始值为 0

        // ======== 已完全解锁：当前时间 >= 结束时间 ========
        if (block.timestamp >= schedule.endTime) {  // 如果当前区块时间戳 >= 归属结束时间，说明归属期已完全结束
            vestedAmount = schedule.totalAmount;  // 归属期已结束，所有代币都已解锁；vestedAmount = 总量
        } else {
            // ======== 归属进行中：开始时间 < 当前时间 < 结束时间 ========
            if (schedule.mode == VestingMode.CLIFF) {  // 如果是 CLIFF（悬崖）模式
                // CLIFF 模式：未到期返回 0
                // 到期后在上面的分支中处理（全部解锁）
                // CLIFF 的特点：在到达 endTime 之前，没有任何代币解锁；到达 endTime 后，全部代币一次性解锁
                // 当前处于 startTime < block.timestamp < endTime 区间，所以尚未到期
                vestedAmount = 0;  // CLIFF 模式在归属期结束前不释放任何代币；vestedAmount 保持为 0
            } else if (schedule.mode == VestingMode.LINEAR) {  // 如果是 LINEAR（线性）模式
                // LINEAR 模式：按时间比例线性解锁
                // 公式：vestedAmount = totalAmount × (已过时间 / 总时长)
                // Solidity 不支持浮点数，所以先乘后除以保证精度
                // 即：vestedAmount = (totalAmount × timePassed) / totalDuration

                // 已过时间 = 当前时间 - 开始时间
                uint256 timePassed = block.timestamp - schedule.startTime;  // 计算从归属开始到现在已经过了多少秒；因为前面已确认 block.timestamp > schedule.startTime，所以不会下溢

                // 总时长 = 结束时间 - 开始时间
                uint256 totalDuration = schedule.endTime - schedule.startTime;  // 计算归属的总时长（秒）；endTime = startTime + duration，所以 totalDuration == duration

                // 已解锁数量 = 总量 × (已过时间 / 总时长)
                // 先乘后除：vestedAmount = (totalAmount * timePassed) / totalDuration
                // 这样做的原因：Solidity 整数除法向下取整，先乘后除可以减少精度损失
                // 例如：totalAmount=1000, timePassed=3, totalDuration=10
                //   (1000 * 3) / 10 = 3000 / 10 = 300（正确）
                //   如果先除后乘：(1000 / 10) * 3 = 100 * 3 = 300（此例相同，但其他情况可能不同）
                //   例如：totalAmount=1000, timePassed=1, totalDuration=3
                //     先乘后除：(1000 * 1) / 3 = 333（向下取整，损失不到 1 个 wei）
                //     先除后乘：(1000 / 3) * 1 = 333 * 1 = 333（损失更多精度）
                vestedAmount = (schedule.totalAmount * timePassed) / totalDuration;  // 已解锁数量 = 总量 × 已过时间 ÷ 总时长；先乘后除以减少整数除法的精度损失；结果向下取整
            }
        }

        // ======== 最终计算：扣除已领取数量 ========
        // 可领取量 = 已解锁量 - 已领取量
        // 使用条件判断防止下溢（虽然 vestedAmount 应该始终 >= claimedAmount）
        // 正常情况下 vestedAmount >= claimedAmount，因为每次领取后 claimedAmount 会更新
        // 但使用条件判断是防御性编程，避免潜在的整数下溢（0.8.x 会自动回滚，但此写法更明确）
        return vestedAmount > schedule.claimedAmount ? vestedAmount - schedule.claimedAmount : 0;  // 如果已解锁量 > 已领取量，返回差值（即当前可领取量）；否则返回 0（已全部领取或计算异常）
    }

    // ============ 查询函数 ============

    /**
     * @notice 获取归属计划详情
     * @dev 只读函数，无 gas 成本（view）
     * @param token 代币地址
     * @param beneficiary 受益人地址
     * @param scheduleId 计划ID
     * @return VestingSchedule 归属计划详情
     */
    function getVestingSchedule(
        address token,  // 代币合约地址
        address beneficiary,  // 受益人地址
        uint256 scheduleId  // 计划 ID
    ) external view override returns (VestingSchedule memory) {  // external：仅外部调用；view：只读，不消耗 gas；override：实现接口；returns：返回归属计划结构体的内存副本
        return vestingSchedules[token][beneficiary][scheduleId];  // 从三层映射中读取并返回归属计划；返回 memory 副本，不影响存储
    }

    /**
     * @notice 获取用户的归属计划数量
     * @dev 用于遍历用户的所有归属计划
     * @param token 代币地址
     * @param beneficiary 受益人地址
     * @return 归属计划数量
     */
    function getVestingScheduleCount(
        address token,  // 代币合约地址
        address beneficiary  // 受益人地址
    ) external view override returns (uint256) {  // external：仅外部调用；view：只读；override：实现接口；returns：返回归属计划数量
        return scheduleCount[token][beneficiary];  // 返回该用户对此代币的归属计划数量；计划 ID 从 0 到 count-1
    }

    /**
     * @notice 获取单个计划的可领取数量
     * @dev 只读函数，用于前端显示"可领取 X 代币"
     * @param token 代币地址
     * @param beneficiary 受益人地址
     * @param scheduleId 计划ID
     * @return 可领取代币数量
     */
    function getClaimableAmount(
        address token,  // 代币合约地址
        address beneficiary,  // 受益人地址
        uint256 scheduleId  // 计划 ID
    ) external view override returns (uint256) {  // external：仅外部调用；view：只读；override：实现接口；returns：返回可领取代币数量
        VestingSchedule memory schedule = vestingSchedules[token][beneficiary][scheduleId];  // 读取归属计划到内存；使用 memory 避免修改存储
        // 计划不存在或已撤销，返回 0
        if (schedule.totalAmount == 0 || schedule.revoked) return 0;  // 如果计划不存在或已被撤销，直接返回 0；避免调用计算函数
        return _calculateClaimableAmount(schedule);  // 调用内部计算函数，根据模式和时间返回可领取数量
    }

    /**
     * @notice 获取所有计划的可领取总量
     * @dev 遍历所有计划，累加可领取数量
     * @param token 代币地址
     * @param beneficiary 受益人地址
     * @return totalClaimable 可领取总量
     */
    function getTotalClaimableAmount(
        address token,  // 代币合约地址
        address beneficiary  // 受益人地址
    ) external view override returns (uint256 totalClaimable) {  // external：仅外部调用；view：只读；override：实现接口；returns：返回所有计划的可领取总量
        uint256 count = scheduleCount[token][beneficiary];  // 获取该用户对此代币的归属计划数量
        for (uint256 i = 0; i < count; i++) {  // 遍历所有计划
            VestingSchedule memory schedule = vestingSchedules[token][beneficiary][i];  // 读取第 i 个归属计划到内存
            if (schedule.totalAmount > 0 && !schedule.revoked) {  // 仅统计存在且未撤销的计划
                totalClaimable += _calculateClaimableAmount(schedule);  // 累加该计划的可领取数量到总量中
            }
        }
    }

    /**
     * @notice 获取归属统计信息
     * @dev 返回用户的整体归属状态，用于前端仪表盘
     * @param token 代币地址
     * @param beneficiary 受益人地址
     * @return vested 已解锁数量（可领取 + 已领取）
     * @return claimed 已领取数量
     * @return locked 仍锁定数量（未解锁）
     *
     * ============ 计算说明 ============
     * vested = 所有计划已解锁数量之和
     * claimed = 所有计划已领取数量之和
     * locked = 所有计划剩余锁定数量之和
     * 关系：vested + locked = totalAmount（对于每个未撤销计划）
     */
    function getTotalVestedAmount(
        address token,  // 代币合约地址
        address beneficiary  // 受益人地址
    ) external view override returns (uint256 vested, uint256 claimed, uint256 locked) {  // external：仅外部调用；view：只读；override：实现接口；returns：返回三个统计值——已解锁量、已领取量、仍锁定量
        uint256 count = scheduleCount[token][beneficiary];  // 获取该用户对此代币的归属计划数量

        for (uint256 i = 0; i < count; i++) {  // 遍历所有归属计划
            VestingSchedule memory schedule = vestingSchedules[token][beneficiary][i];  // 读取第 i 个归属计划到内存
            // 跳过不存在或已撤销的计划
            if (schedule.totalAmount > 0 && !schedule.revoked) {  // 仅统计存在且未撤销的计划
                // BURN 模式不计入统计（已销毁）
                if (schedule.mode == VestingMode.BURN) {  // BURN 模式的代币已永久销毁
                    continue;  // 跳过 BURN 模式，不计入 vested/claimed/locked 统计
                }

                uint256 vestedForSchedule;  // 该计划的已解锁数量；默认为 0

                // 计算该计划的已解锁数量
                if (block.timestamp >= schedule.endTime) {  // 如果当前时间 >= 结束时间，归属期已完全结束
                    // 已完全解锁
                    vestedForSchedule = schedule.totalAmount;  // 归属期结束，所有代币都已解锁；vestedForSchedule = 总量
                } else if (block.timestamp > schedule.startTime) {  // 如果当前时间 > 开始时间（且 < 结束时间），归属正在进行中
                    // 归属进行中
                    if (schedule.mode == VestingMode.LINEAR) {  // LINEAR 模式：按时间比例计算已解锁量
                        // LINEAR 模式：按时间比例
                        // 公式：vestedForSchedule = totalAmount × (已过时间 / 总时长)
                        uint256 timePassed = block.timestamp - schedule.startTime;  // 已过时间 = 当前区块时间 - 归属开始时间
                        uint256 totalDuration = schedule.endTime - schedule.startTime;  // 总时长 = 结束时间 - 开始时间
                        vestedForSchedule = (schedule.totalAmount * timePassed) / totalDuration;  // 已解锁数量 = 总量 × 已过时间 ÷ 总时长；先乘后除以保持精度；整数除法向下取整
                    }
                    // CLIFF 模式进行中：vestedForSchedule 保持 0
                    // CLIFF 模式在到期前不释放任何代币，所以 vestedForSchedule 保持默认值 0
                }
                // 如果未开始（block.timestamp <= startTime）：vestedForSchedule 保持 0

                // 累加统计
                vested += vestedForSchedule;  // 累加已解锁数量：所有计划的已解锁量之和
                claimed += schedule.claimedAmount;  // 累加已领取数量：所有计划中已领取的代币总量
                locked += (schedule.totalAmount - vestedForSchedule);  // 累加仍锁定数量：每个计划的总量减去已解锁量 = 仍锁定量；关系验证：vested + locked = totalAmount
            }
        }

        return (vested, claimed, locked);  // 返回三个统计值：已解锁量、已领取量、仍锁定量
    }

    // ============ 管理函数 ============

    /**
     * @notice 撤销归属计划
     * @dev 仅限 ADMIN_ROLE，用于紧急情况或违规处理
     *
     * @param token 代币地址
     * @param beneficiary 受益人地址
     * @param scheduleId 计划ID
     *
     * ============ 执行流程 ============
     *
     * 1. 验证计划存在且未撤销
     * 2. 计算并发放已解锁的代币给受益人（公平原则）
     * 3. 返还剩余锁定代币给管理员（撤销回收）
     * 4. 标记计划为已撤销
     *
     * ============ 资金分配 ============
     * - 已解锁部分 → 受益人（已赚取的部分）
     * - 未解锁部分 → 管理员（回收）
     *
     * ============ 安全考虑 ============
     * - 仅管理员可调用（防止恶意撤销）
     * - 受益人仍可获得已解锁部分（保护已赚取权益）
     * - 更新 totalTokenLocked 和 totalVestedAmount 保持账目一致
     */
    function revokeVestingSchedule(
        address token,  // 代币合约地址
        address beneficiary,  // 受益人地址
        uint256 scheduleId  // 要撤销的归属计划 ID
    ) external override onlyRole(ADMIN_ROLE) {  // external：仅外部调用；override：实现接口；onlyRole(ADMIN_ROLE)：仅管理员可调用
        VestingSchedule storage schedule = vestingSchedules[token][beneficiary][scheduleId];  // 获取归属计划的存储指针；storage 引用，修改直接影响链上状态

        // 验证计划存在
        if (schedule.totalAmount == 0) revert ScheduleNotFound();  // 如果计划总量为 0，说明该 ID 不存在；回滚交易
        // 验证计划未撤销（防止重复撤销）
        if (schedule.revoked) revert ScheduleRevoked();  // 如果计划已被撤销，不允许重复撤销；回滚交易

        // 声明剩余未解锁数量变量
        uint256 remainingAmount;  // 剩余未解锁的代币数量，将返还给管理员；默认为 0

        // BURN 模式无需处理代币转移（已销毁）
        if (schedule.mode != VestingMode.BURN) {  // 非 BURN 模式需要处理代币转移；BURN 模式的代币已销毁，不在合约中
            // ======== 第一步：发放已解锁部分给受益人 ========
            // 计算已解锁部分并发放给受益人
            uint256 claimableAmount = _calculateClaimableAmount(schedule);  // 计算受益人当前可领取的已解锁数量
            if (claimableAmount > 0) {  // 如果有可领取的代币
                // 更新已领取状态
                schedule.claimedAmount += claimableAmount;  // 增加该计划的已领取数量；标记这部分代币已被"领取"
                totalTokenLocked[token] -= claimableAmount;  // 减少合约锁定总量；这部分代币将转出合约
                // 转移已解锁代币给受益人
                IERC20(token).safeTransfer(beneficiary, claimableAmount);  // 将已解锁的代币转给受益人；公平原则：受益人已"赚取"的部分不应被剥夺
            }

            // ======== 第二步：返还剩余锁定部分给管理员 ========
            // 计算剩余未解锁数量 = 总量 - 已领取量（包含刚发放的可领取部分）
            remainingAmount = schedule.totalAmount - schedule.claimedAmount;  // 剩余未解锁量 = 总量 - 已领取量（包含刚刚发放给受益人的部分）
            if (remainingAmount > 0) {  // 如果还有剩余未解锁的代币
                // 更新锁定统计
                totalTokenLocked[token] -= remainingAmount;  // 减少合约锁定总量；这些代币将返还给管理员
                // 更新用户总归属数量（减去被撤销的部分）
                totalVestedAmount[token][beneficiary] -= remainingAmount;  // 从用户总归属量中减去被撤销回收的部分；保持统计账目一致
                // 将剩余代币返还给管理员
                IERC20(token).safeTransfer(msg.sender, remainingAmount);  // 将剩余锁定的代币转给调用者（管理员）；实现撤销回收
            }
        }

        // ======== 第三步：标记计划为已撤销 ========
        schedule.revoked = true;  // 设置撤销标志为 true；后续任何领取操作都会因 revoked 检查而失败

        // 触发撤销事件
        emit VestingScheduleRevoked(token, beneficiary, scheduleId, remainingAmount);  // 发出撤销事件，记录代币地址、受益人、计划 ID 和返还给管理员的剩余数量
    }

    /**
     * @notice 紧急提取代币
     * @dev 仅限 ADMIN_ROLE，用于紧急情况（如合约漏洞、资金卡住）
     * @param token 代币地址
     * @param amount 提取数量（wei）
     *
     * ============ 安全考虑 ============
     * - 仅限管理员调用
     * - 检查余额充足
     * - 应谨慎使用，避免滥用提取用户资金
     * - 提取金额不受 totalTokenLocked 限制（紧急情况可能超出）
     */
    function emergencyWithdrawToken(
        address token,  // 代币合约地址
        uint256 amount  // 要提取的代币数量（单位：wei，即最小精度）
    ) external override onlyRole(ADMIN_ROLE) {  // external：仅外部调用；override：实现接口；onlyRole(ADMIN_ROLE)：仅管理员可调用
        // 检查合约余额
        uint256 balance = IERC20(token).balanceOf(address(this));  // 查询本合约持有的该代币数量；address(this) 是当前合约的地址
        if (amount > balance) revert InsufficientBalance();  // 如果提取数量超过合约实际持有量，回滚交易；防止提取不存在的代币
        // 转移代币给管理员
        IERC20(token).safeTransfer(msg.sender, amount);  // 将指定数量的代币转给调用者（管理员）；注意：此操作不更新 totalTokenLocked，可能导致统计不一致；仅在紧急情况使用
        // 触发紧急提取事件
        emit EmergencyWithdraw(token, msg.sender, amount);  // 发出紧急提取事件，记录代币地址、接收者（管理员）和提取数量；便于审计追踪
    }

    /**
     * @notice 暂停合约
     * @dev 仅限 ADMIN_ROLE
     * 暂停后：创建归属计划、领取代币等操作被禁止
     * 不影响已存在的归属计划时间计算
     */
    function pause() external onlyRole(ADMIN_ROLE) {  // external：仅外部调用；onlyRole(ADMIN_ROLE)：仅管理员可调用
        _pause();  // 调用 OpenZeppelin Pausable 的内部函数，设置暂停标志；之后所有带 whenNotPaused 的函数都会回滚
    }

    /**
     * @notice 恢复合约
     * @dev 仅限 ADMIN_ROLE
     * 恢复后：所有功能恢复正常
     */
    function unpause() external onlyRole(ADMIN_ROLE) {  // external：仅外部调用；onlyRole(ADMIN_ROLE)：仅管理员可调用
        _unpause();  // 调用 OpenZeppelin Pausable 的内部函数，清除暂停标志；之后所有带 whenNotPaused 的函数恢复正常执行
    }

    /**
     * @notice 授权合约升级
     * @dev UUPS 升级的核心函数，仅限 ADMIN_ROLE 可升级
     * @param newImplementation 新逻辑合约地址
     *
     * ============ 升级安全 ============
     * - 仅管理员可授权升级
     * - 升级前应在测试网充分验证新实现
     * - 新实现合约不应有状态变量冲突
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(ADMIN_ROLE) {}  // internal：仅内部和子合约可调用；override：实现 UUPSUpgradeable 的抽象函数；onlyRole(ADMIN_ROLE)：仅管理员可授权升级；空函数体：授权逻辑完全由角色控制决定，无需额外检查
}
