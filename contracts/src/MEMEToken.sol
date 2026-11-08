// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;  // 编译器版本声明：使用 Solidity 0.8.20 及以上版本；0.8.x 内置算术溢出/下溢检查，无需 SafeMath

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";  // 导入 OpenZeppelin 的 ERC20Burnable 合约，它继承自 ERC20 并添加了 burn 和 burnFrom 函数；ERC20 提供标准代币功能（transfer、approve、balanceOf 等），ERC20Burnable 增加可销毁能力

/**
 * @title MetaNodeToken
 * @author MetaNode Team
 * @notice MEME 发射器部署的 ERC20 代币合约
 *
 * ============ 合约职责 ============
 * 1. 标准 ERC20 代币功能
 * 2. 可销毁（用于归属计划的 BURN 模式）
 * 3. 转账限制（保护上线前的代币流通）
 *
 * ============ 转账模式说明 ============
 *
 * 【MODE_TRANSFER_RESTRICTED】初始状态
 * - 禁止所有转账（除铸造/销毁）
 * - 用于代币创建后、开盘前的保护期
 *
 * 【MODE_TRANSFER_CONTROLLED】交易中
 * - 允许与 MEMECore 的买卖交互
 * - 禁止直接转账到交易对（防止绕过曲线）
 * - 允许归属合约释放代币
 *
 * 【MODE_NORMAL】毕业后
 * - 完全开放转账
 * - 代币可在 DEX 自由交易
 *
 * ============ 生命周期 ============
 *
 * 1. 工厂部署 → RESTRICTED（全部代币在 MEMECore）
 * 2. 创建完成 → CONTROLLED（可通过曲线买卖）
 * 3. 待毕业   → RESTRICTED（暂停转账）
 * 4. 已毕业   → NORMAL（自由交易）
 */
contract MetaNodeToken is ERC20Burnable {  // 合约声明：继承 ERC20Burnable，获得标准 ERC20 功能 + 可销毁功能

    // ============ 枚举定义 ============

    /**
     * @notice 转账模式枚举
     */
    enum TransferMode {  // 枚举类型：定义代币的转账限制模式，控制代币在不同生命周期阶段的流通规则
        MODE_NORMAL,              // 0: 正常模式（毕业后，自由转账）；代币可在任何地址间自由转移，包括 DEX 交易
        MODE_TRANSFER_RESTRICTED, // 1: 限制模式（禁止所有转账）；除铸造/销毁外禁止一切转账，保护上线前代币不被非法流通
        MODE_TRANSFER_CONTROLLED  // 2: 受控模式（仅允许曲线交易）；允许与 MEMECore 的买卖交互，但禁止直接转入 DEX 交易对，防止绕过联合曲线
    }

    // ============ 状态变量 ============

    /**
     * @notice 当前转账模式
     * @dev 由 MEMECore 通过 setTransferMode 设置
     * 初始值：MODE_TRANSFER_RESTRICTED
     */
    TransferMode public transferMode;  // 当前转账模式状态变量；public 自动生成 getter 函数；默认值为枚举的第一个元素 MODE_NORMAL(0)，但在构造函数中被显式设为 MODE_TRANSFER_RESTRICTED

    /**
     * @notice 归属合约地址
     * @dev 归属合约的转出不受限制模式影响
     * 允许锁仓释放操作
     */
    address public vestingContract;  // 归属（Vesting）合约地址；默认为零地址；设置后，归属合约向外的代币转移不受 RESTRICTED 模式限制，支持锁仓代币的逐步释放

    /**
     * @notice DEX 交易对地址
     * @dev 用于判断是否允许转账到交易对
     * 非 NORMAL 模式下禁止直接转入 pair
     */
    address public pair;  // PancakeSwap 交易对合约地址；默认为零地址；设置后，在 CONTROLLED 和 RESTRICTED 模式下禁止直接将代币转入此地址，防止绕过联合曲线卖出

    /**
     * @notice MEMECore 核心合约地址
     * @dev 拥有设置转账模式等管理权限
     * 构造时设置，不可更改
     */
    address public metaNodeCore;  // MEMECore 核心合约地址；部署时设置，后续不可更改；拥有设置转账模式、归属合约、交易对等管理权限；类似 owner 但不是 Ownable 模式

    // ============ 错误定义 ============

    /// @notice 转账被限制（RESTRICTED 模式）
    error TransferRestricted();  // 自定义错误：当 RESTRICTED 模式下尝试非铸造/销毁的转账时抛出；使用 custom error 比 require 字符串节省 gas
    /// @notice 不允许转账到代币合约自身
    error TransferToTokenNotAllowed();  // 自定义错误：当尝试将代币转入代币合约自身时抛出；防止代币被意外锁定在合约中（转入后无法取出）
    /// @notice 非 NORMAL 模式下不允许转账到交易对
    error TransferNotAllowedToPair();  // 自定义错误：在 CONTROLLED 或 RESTRICTED 模式下尝试将代币转入 DEX 交易对时抛出；防止用户绕过联合曲线直接在 DEX 卖出
    /// @notice 转账不被允许
    error TransferNotAllowed();  // 自定义错误：通用转账不允许错误（当前代码中未直接使用，保留供未来扩展）
    /// @notice 仅限 MEMECore 调用
    error onlyMetaNodeCall();  // 自定义错误：当非 MEMECore 地址尝试调用 onlyMetaNode 修饰的函数时抛出
    /// @notice 零地址
    error ZeroAddress();  // 自定义错误：当传入零地址作为关键参数时抛出；零地址通常表示未设置或无效地址

    // ============ 事件定义 ============

    /// @notice 转账模式变更事件
    event TransferModeChanged(TransferMode oldMode, TransferMode newMode);  // 事件：转账模式变更时触发；记录旧模式和新模式，便于链下追踪代币生命周期状态变化
    /// @notice 归属合约地址变更事件
    event VestingContractChanged(address vestingContract);  // 事件：归属合约地址设置时触发；便于链下追踪归属合约变更
    /// @notice 交易对地址变更事件
    event PairChanged(address pair);  // 事件：交易对地址设置时触发；便于链下追踪 DEX 交易对变更

    // ============ 修饰器 ============

    /**
     * @notice 仅限 MEMECore 调用
     */
    modifier onlyMetaNode() {  // 修饰器：限制函数只能由 MEMECore 合约调用；类似 Ownable 的 onlyOwner，但针对特定合约地址
        if (msg.sender != metaNodeCore) revert onlyMetaNodeCall();  // 检查调用者是否为 MEMECore；如果不是则回滚交易并抛出 onlyMetaNodeCall 错误
        _;  // 占位符：代表被修饰函数的实际代码；只有通过上面的检查才会执行被修饰的函数体
    }

    // ============ 构造函数 ============

    /**
     * @notice 部署代币合约
     * @dev 由 MEMEFactory 通过 CREATE2 调用
     *
     * @param name 代币名称
     * @param symbol 代币符号
     * @param totalSupply 总供应量（含18位小数）
     * @param _metaNode MEMECore 合约地址
     *
     * ============ 初始化流程 ============
     * 1. 设置代币名称和符号（ERC20）
     * 2. 设置转账模式为 RESTRICTED
     * 3. 将全部代币铸造给 _metaNode
     * 4. 记录 metaNodeCore 地址
     */
    constructor(
        string memory name,  // 参数：代币名称，如 "PEPE COIN"；memory 表示存储在内存中，函数调用结束后释放
        string memory symbol,  // 参数：代币符号，如 "PEPE"；通常 3-5 个字符
        uint256 totalSupply,  // 参数：代币总供应量（含 18 位小数）；例如 1e27 表示 10 亿个代币（1e9 × 1e18）
        address _metaNode  // 参数：MEMECore 核心合约地址，将获得全部代币和管理权限
    ) ERC20(name, symbol)  {  // 调用父构造函数 ERC20(name, symbol)，初始化代币名称和符号；ERC20 构造函数设置 name_ 和 symbol_ 状态变量
        if (_metaNode == address(0)) revert ZeroAddress();  // 安全检查：MEMECore 地址不能为零地址；零地址意味着无人能管理此代币，合约将无法使用

        // 初始状态：禁止所有转账
        transferMode = TransferMode.MODE_TRANSFER_RESTRICTED;  // 设置初始转账模式为限制模式；部署后所有转账被禁止，防止代币在未就绪时被转移；只有铸造和销毁操作被允许

        // 铸造全部代币给 MEMECore
        if (totalSupply > 0) {  // 检查总供应量是否大于零；如果为零则不铸造（极端情况）
            _mint(_metaNode, totalSupply);  // 调用 ERC20 内部函数 _mint 铸造全部代币给 MEMECore；使用 _mint 而非 mint 是因为 _mint 不检查权限，适合构造函数中调用；MEMECore 将持有全部代币用于联合曲线交易
        }

        metaNodeCore = _metaNode;  // 记录 MEMECore 合约地址；后续 setTransferMode、setVestingContract、setPair 等管理函数都通过 onlyMetaNode 修饰器检查此地址
    }

    // ============ 管理函数 ============

    /**
     * @notice 设置转账模式
     * @dev 仅限 MEMECore 调用
     *
     * @param _mode 新的转账模式
     *
     * 调用时机：
     * - 创建完成 → CONTROLLED
     * - 待毕业   → RESTRICTED
     * - 毕业完成 → NORMAL
     */
    function setTransferMode(TransferMode _mode) external onlyMetaNode {  // 外部函数：设置转账模式；onlyMetaNode 确保只有 MEMECore 可以调用；_mode 为新的转账模式枚举值
        TransferMode oldMode = transferMode;  // 保存当前转账模式到局部变量，用于事件记录
        transferMode = _mode;  // 更新转账模式为新值；这会立即影响所有后续转账操作的检查结果
        emit TransferModeChanged(oldMode, _mode);  // 发出转账模式变更事件，记录旧模式和新模式；便于前端和索引服务追踪状态变化
    }

    /**
     * @notice 设置归属合约地址
     * @dev 仅限 MEMECore 调用
     *
     * @param _vestingContract 归属合约地址
     *
     * 设置后，归属合约的转出操作不受模式限制
     */
    function setVestingContract(address _vestingContract) external onlyMetaNode {  // 外部函数：设置归属合约地址；onlyMetaNode 确保只有 MEMECore 可以调用
        if (_vestingContract == address(0)) revert ZeroAddress();  // 安全检查：归属合约地址不能为零地址；零地址会导致 _beforeTokenTransfer 中 from == vestingContract 判断出错（任何人从零地址转出都会被放行）
        vestingContract = _vestingContract;  // 更新归属合约地址
        emit VestingContractChanged(_vestingContract);  // 发出归属合约变更事件
    }

    /**
     * @notice 设置 DEX 交易对地址
     * @dev 仅限 MEMECore 调用
     *
     * @param _pair 交易对合约地址
     *
     * 设置后，非 NORMAL 模式下禁止直接转入 pair
     * （必须通过曲线买卖）
     */
    function setPair(address _pair) external onlyMetaNode {  // 外部函数：设置 DEX 交易对地址；onlyMetaNode 确保只有 MEMECore 可以调用
        if (_pair == address(0)) revert ZeroAddress();  // 安全检查：交易对地址不能为零地址；零地址会导致 _beforeTokenTransfer 中 to == pair 判断出错
        pair = _pair;  // 更新交易对地址
        emit PairChanged(_pair);  // 发出交易对变更事件
    }

    // ============ 内部函数 ============

    /**
     * @notice 转账前钩子 - 实现转账限制逻辑
     * @dev 重写 ERC20 的 _beforeTokenTransfer
     *
     * @param from 发送方地址
     * @param to 接收方地址
     * @param amount 转账金额（未使用，但保留签名）
     *
     * ============ 检查规则 ============
     *
     * 1. 铸造（from=0）和销毁（to=0）始终允许
     *    - 铸造：from=零地址，表示代币从无到有；必须在任何模式下都允许，否则无法创建代币
     *    - 销毁：to=零地址，表示代币永久消失；ERC20Burnable 的 burn/burnFrom 需要此功能
     *
     * 2. 禁止转账到代币合约自身
     *    - 防止代币被永久锁定；代币合约自身没有提取代币的功能，转入后无法取出
     *
     * 3. 归属合约转出始终允许
     *    - 支持锁仓释放功能；归属合约按时间表释放锁仓代币，不应受转账模式限制
     *
     * 4. 非 NORMAL 模式下禁止转入 pair
     *    - 防止绕过曲线直接卖出；在 CONTROLLED 模式下，用户必须通过 MEMECore 的卖出函数，而非直接添加流动性到 DEX
     *
     * 5. RESTRICTED 模式下禁止所有转账
     *    - 完全锁定代币流通；用于代币创建前或待毕业时的保护期
     */
    function _beforeTokenTransfer(  // 内部虚函数：ERC20 转账前钩子；在每次代币转移（transfer/transferFrom/mint/burn）前自动调用
        address from,  // 参数：发送方地址；零地址表示铸造（mint），非零地址表示转账或销毁
        address to,  // 参数：接收方地址；零地址表示销毁（burn），非零地址表示转账或铸造
        uint256 amount  // 参数：转账金额；本函数中未使用但保留签名以匹配父合约的函数签名
    ) internal virtual override {  // internal：仅合约内部和子合约可调用；virtual：允许子合约进一步重写；override：重写父合约 ERC20 的 _beforeTokenTransfer
        super._beforeTokenTransfer(from, to, amount);  // 调用父合约（ERC20Burnable → ERC20）的 _beforeTokenTransfer；确保父合约的钩子逻辑也被执行；ERC20Burnable 的 _beforeTokenTransfer 调用 ERC20 的（空实现）

        // 规则1：允许铸造和销毁
        // 铸造：from == address(0)，代币从零地址产生，是增加总供应量的操作
        // 销毁：to == address(0)，代币发送到零地址永久消失，是减少总供应量的操作
        // 这两种操作在任何模式下都必须允许，否则代币的核心机制（创建和销毁）无法运作
        if (from == address(0) || to == address(0)) {  // 检查是否为铸造（from=0）或销毁（to=0）操作
            return;  // 直接返回，跳过后续所有转账限制检查；铸造和销毁不受任何模式限制
        }

        // 规则2：禁止转账到代币合约自身
        // 原因：代币合约自身没有提取/转出代币的函数，转入后代币将永久锁定
        // 这与 ERC20 的 approve-and-call 模式不同，是用户误操作导致的资金损失
        if (to == address(this)) {  // 检查接收方是否为代币合约自身（address(this) = 本合约地址）
            revert TransferToTokenNotAllowed();  // 回滚交易并抛出自定义错误；阻止代币被意外锁定在合约中
        }

        // 规则3：归属合约转出始终允许
        // 原因：归属（Vesting）合约按时间表释放锁仓代币给用户，这是正常的业务流程
        // 如果归属合约的转出也被限制，锁仓代币将无法按计划释放
        // 条件：from == vestingContract && vestingContract != address(0)
        // 第二个条件防止 vestingContract 未设置时 from == address(0) == vestingContract 的边界情况
        if (from == vestingContract && vestingContract != address(0)) {  // 检查发送方是否为归属合约，且归属合约地址已设置（非零）
            return;  // 直接返回，允许归属合约的转出操作；归属合约释放代币不受任何转账模式限制
        }

        // 规则4：非 NORMAL 模式禁止转入 pair
        // 原因：在 CONTROLLED 模式下，用户应该通过 MEMECore 的卖出函数卖出代币（经联合曲线计算价格）
        // 如果允许直接转入 pair，用户可以绕过联合曲线在 DEX 上以不同价格交易，破坏价格发现机制
        // 条件：transferMode != NORMAL && to == pair && pair != address(0)
        // 第三个条件防止 pair 未设置时的误判
        if (transferMode != TransferMode.MODE_NORMAL && to == pair && pair != address(0)) {  // 检查：当前不是正常模式 且 接收方是交易对 且 交易对地址已设置
            revert TransferNotAllowedToPair();  // 回滚交易并抛出错误；阻止在受控/限制模式下直接将代币转入 DEX 交易对
        }

        // 规则5：RESTRICTED 模式禁止所有转账
        // 这是最终的兜底检查：如果前面的规则都没有匹配（不是铸造/销毁、不是转入自身、不是归属合约转出、不是转入 pair），则检查是否为限制模式
        // RESTRICTED 模式下，除了上述已放行的操作外，所有其他转账都被禁止
        // 这确保代币在上线前的保护期内无法被任何人转移
        if (transferMode == TransferMode.MODE_TRANSFER_RESTRICTED) {  // 检查当前是否为限制模式
            revert TransferRestricted();  // 回滚交易并抛出错误；在限制模式下禁止所有普通转账
        }

        // 如果执行到这里，说明：
        // 1. 不是铸造/销毁操作
        // 2. 不是转入代币合约自身
        // 3. 不是归属合约转出
        // 4. 如果转入 pair，当前是 NORMAL 模式（允许）
        // 5. 当前不是 RESTRICTED 模式
        // 即：CONTROLLED 模式下的普通转账，或 NORMAL 模式下的任何转账
        // 这些都是允许的操作，函数正常结束
    }
}
