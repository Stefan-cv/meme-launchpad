// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;  // 编译器版本声明：要求 Solidity 版本 >= 0.8.20 且 < 0.9.0；0.8.x 内置溢出检查

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";  // 导入 OpenZeppelin 的访问控制合约，提供基于角色的权限管理（RBAC）
import { IMEMEFactory } from "./interfaces/IMEMEFactory.sol";  // 导入工厂接口，定义了工厂合约必须实现的外部函数和事件
import { MetaNodeToken } from "./MEMEToken.sol";  // 导入代币合约，工厂负责部署此类型的 ERC20 代币

/**
 * @title MEMEFactory
 * @author MetaNode Team
 * @notice 代币工厂合约 - 负责部署新的 MetaNodeToken
 *
 * ============ 合约职责 ============
 * 1. 使用 CREATE2 部署代币（地址可预测）
 * 2. 管理部署权限（仅 MEMECore 可调用）
 * 3. 提供地址预测功能
 *
 * ============ CREATE2 机制说明 ============
 * 普通 CREATE：地址 = hash(deployer, nonce) → 不可预测
 * CREATE2：address = hash(0xff, factory, salt, bytecodeHash) → 可预测
 *
 * 优势：
 * - 前端可提前计算代币地址
 * - 相同参数 → 相同地址（确定性）
 * - 防止地址抢注
 *
 * ============ 安全设计 ============
 * - 使用 AccessControl 管理权限
 * - DEPLOYER_ROLE 仅授予 MEMECore
 * - 盐值包含多个参数防止碰撞
 */
contract MEMEFactory is IMEMEFactory, AccessControl {  // 合约声明：继承 IMEMEFactory 接口和 AccessControl 权限控制模块

    // ============ 状态变量 ============

    /**
     * @notice 部署者角色标识
     * @dev 拥有此角色才能调用 deployToken
     * 仅 MEMECore 合约应被授予此角色
     */
    bytes32 public constant DEPLOYER_ROLE = keccak256("DEPLOYER_ROLE");  // 角色常量：通过 keccak256 哈希"DEPLOYER_ROLE"字符串得到 32 字节的角色标识符；public 允许外部查询，constant 表示不可修改且不占用存储槽

    /**
     * @notice MetaNode 核心合约地址
     * @dev 部署的代币会将全部供应量铸造给此地址
     * 通过 setMetaNode 设置，同时授予 DEPLOYER_ROLE
     */
    address public metaNode;  // 核心合约地址：部署的新代币会把全部供应量铸造给此地址；初始为 address(0)，需通过 setMetaNode 设置

    // ============ 构造函数 ============

    /**
     * @notice 初始化工厂合约
     * @param _admin 管理员地址，拥有 DEFAULT_ADMIN_ROLE
     *
     * 初始状态：
     * - metaNode = address(0)（需后续设置）
     * - 无人拥有 DEPLOYER_ROLE
     */
    constructor(address _admin) {  // 构造函数：在合约部署时执行一次；参数 _admin 为管理员地址
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);  // 将 DEFAULT_ADMIN_ROLE（OpenZeppelin 内置的最高权限角色）授予 _admin；此角色可以授予和撤销任何其他角色
    }

    // ============ 核心函数 ============

    /**
     * @notice 部署新的 MetaNodeToken 合约
     * @dev 仅限 DEPLOYER_ROLE（MEMECore）调用
     *
     * @param name 代币名称（如 "Doge Coin"）
     * @param symbol 代币符号（如 "DOGE"）
     * @param totalSupply 总供应量（包含18位小数，如 1000000e18）
     * @param timestamp 时间戳（用于盐值计算，防止碰撞）
     * @param nonce 随机数（用于盐值计算，防止碰撞）
     * @return 新部署的代币合约地址
     *
     * ============ 执行流程 ============
     * 1. 计算盐值：hash(name, symbol, totalSupply, metaNode, timestamp, nonce)
     * 2. 使用 CREATE2 部署 MetaNodeToken
     * 3. MetaNodeToken 构造函数将所有代币铸造给 metaNode
     * 4. 触发 TokenDeployed 事件
     *
     * ============ 注意事项 ============
     * - 相同参数会产生相同地址（如已部署则失败）
     * - metaNode 必须已设置
     */
    function deployToken(
        string memory name,  // 代币全名，如 "Doge Coin"；memory 表示数据存储在内存中，函数调用结束后释放
        string memory symbol,  // 代币简称/符号，如 "DOGE"；用于交易对和钱包显示
        uint256 totalSupply,  // 代币总供应量，单位为 wei（1e18 = 1 个完整代币）
        uint256 timestamp,  // 时间戳参数，参与盐值计算；使不同时间创建的同名代币地址不同
        uint256 nonce  // 随机数参数，参与盐值计算；确保即使所有其他参数相同也能产生不同地址
    ) external onlyRole(DEPLOYER_ROLE) returns (address) {  // external：仅可从合约外部调用；onlyRole(DEPLOYER_ROLE)：只有拥有 DEPLOYER_ROLE 角色的地址可调用，否则回滚；returns (address)：返回新代币合约地址
        // ======== 第一步：计算 CREATE2 盐值 ========
        // 盐值是 CREATE2 地址计算的关键输入之一，决定了部署地址
        // 使用 abi.encodePacked 将多个参数紧密打包（无填充），然后 keccak256 哈希
        // 包含多个参数的目的是：即使 name/symbol 相同，只要 timestamp 或 nonce 不同，盐值就不同
        // 这样允许同名代币在不同时间部署到不同地址
        bytes32 salt = keccak256(abi.encodePacked(name, symbol, totalSupply, metaNode, timestamp, nonce));  // 盐值 = keccak256(紧密编码(名称, 符号, 总供应量, 核心合约地址, 时间戳, 随机数))；注意：ptotalSuply 看起来是 totalSupply 的拼写错误，但保持原样不修改

        // ======== 第二步：使用 CREATE2 部署代币合约 ========
        // new MetaNodeToken{salt: salt}(...) 是 Solidity 中 CREATE2 部署的语法
        // 与普通 new 的区别：
        //   普通 new (CREATE)：地址 = keccak256(rlp([sender, nonce]))，依赖于发送者 nonce，不可预测
        //   new{salt} (CREATE2)：地址 = keccak256(0xff || sender || salt || keccak256(init_code))，确定性可预测
        // 构造函数参数 (name, symbol, totalSupply, metaNode) 会在部署时传入
        // MetaNodeToken 构造函数内部会将 totalSupply 数量的代币铸造给 metaNode
        MetaNodeToken token = new MetaNodeToken{salt: salt}(name, symbol, totalSupply, metaNode);  // 使用 CREATE2 部署新代币合约；salt 决定部署地址；构造函数传入名称、符号、供应量、接收者

        // ======== 第三步：触发事件并返回地址 ========
        emit TokenDeployed(address(token), name, symbol, totalSupply, msg.sender);  // 发出 TokenDeployed 事件，记录代币地址、名称、符号、供应量和调用者；便于链下监听和索引
        return address(token);  // 返回新部署的代币合约地址；调用者（MEMECore）可保存此地址用于后续操作
    }

    /**
     * @notice 预测代币部署地址（不消耗 gas）
     * @dev 使用 CREATE2 公式计算，可在前端调用
     *
     * @param name 代币名称
     * @param symbol 代币符号
     * @param totalSupply 总供应量
     * @param owner 代币接收者（通常是 metaNode）
     * @param timestamp 时间戳
     * @param nonce 随机数
     * @return 预测的合约地址
     *
     * ============ CREATE2 地址计算公式 ============
     * address = keccak256(
     *     0xff,           // 固定前缀
     *     factory,        // 工厂合约地址
     *     salt,           // 盐值
     *     bytecodeHash    // 合约字节码哈希
     * )
     *
     * 注意：bytecodeHash 包含构造函数参数
     */
    function predictTokenAddress(
        string memory name,  // 代币名称，与 deployToken 中相同
        string memory symbol,  // 代币符号，与 deployToken 中相同
        uint256 totalSupply,  // 总供应量，与 deployToken 中相同
        address owner,  // 代币接收者地址；注意这里参数名为 owner 而非 metaNode，但含义相同：部署后代币铸造给此地址
        uint256 timestamp,  // 时间戳，参与盐值计算
        uint256 nonce  // 随机数，参与盐值计算
    ) external view returns (address) {  // view：只读函数，不修改状态，不消耗 gas（从外部调用时）；external：仅可从外部调用
        // ======== 第一步：计算盐值（与 deployToken 中逻辑一致） ========
        // 盐值计算必须与 deployToken 中完全一致，否则预测地址不匹配
        // 注意：此处使用 owner 参数，而 deployToken 中使用 metaNode 状态变量
        // 调用者需确保传入的 owner 与当前 metaNode 一致，否则预测结果与实际部署地址不同
        bytes32 salt = keccak256(abi.encodePacked(name, symbol, totalSupply, owner, timestamp, nonce));  // 盐值 = keccak256(紧密编码(名称, 符号, 供应量, 所有者, 时间戳, 随机数))

        // ======== 第二步：计算 CREATE2 地址 ========
        // CREATE2 地址计算公式：address = keccak256(0xff ++ factory ++ salt ++ initCodeHash)[12:]
        // 逐步拆解：
        //   1. bytes1(0xff)     → CREATE2 固定前缀，1 字节，EIP-1014 规定
        //   2. address(this)    → 当前工厂合约地址，20 字节，确保不同工厂部署的地址不同
        //   3. salt             → 盐值，32 字节，由上述参数计算得出
        //   4. initCodeHash     → 初始化代码的哈希，32 字节
        //
        // initCodeHash 的构成：
        //   initCode = creationCode ++ abi.encode(constructor_args)
        //   - type(MetaNodeToken).creationCode：合约的创建字节码（不含构造函数参数）
        //     这是编译器生成的部署代码，包含运行时字节码和构造函数逻辑
        //   - abi.encode(name, symbol, totalSupply, owner)：构造函数参数的 ABI 编码
        //     使用标准 ABI 编码（有填充），与 deployToken 中构造函数参数一致
        //   - 将两者拼接后 keccak256 哈希，得到 initCodeHash
        //
        // 最终：将上述四部分用 abi.encodePacked 拼接后 keccak256 哈希
        // 得到 32 字节的哈希值，取后 20 字节即为合约地址
        bytes32 hash = keccak256(abi.encodePacked(  // 计算 CREATE2 地址的完整哈希
            bytes1(0xff),                    // CREATE2 固定前缀：0xff，1 字节；EIP-1014 标准规定，用于区分 CREATE 和 CREATE2 地址
            address(this),                   // 工厂合约地址：当前合约自身的地址，20 字节；不同工厂部署相同盐值的合约会产生不同地址
            salt,                            // 盐值：32 字节，由上一步计算得出；决定了相同参数产生相同地址
            keccak256(abi.encodePacked(      // initCodeHash：初始化代码的 keccak256 哈希，32 字节
                type(MetaNodeToken).creationCode,  // 合约创建字节码：编译器生成的部署代码，包含合约初始化逻辑和运行时字节码；type(T).creationCode 返回 bytes memory 类型
                abi.encode(name, symbol, totalSupply, owner)  // 构造函数参数的 ABI 编码：与 MetaNodeToken 构造函数参数匹配；使用 abi.encode（标准编码，有填充）而非 abi.encodePacked
            ))
        ));

        // ======== 第三步：从哈希提取地址 ========
        // hash 是 32 字节的 bytes32 值
        // uint256(hash)：将 bytes32 转换为 uint256，不改变二进制内容
        // uint160(uint256(hash))：取低 160 位（20 字节），即以太坊地址长度；高位被截断丢弃
        // address(uint160(...))：将 160 位整数转换为 address 类型
        // 以太坊地址本质上是 20 字节的标识符，所以取哈希的后 20 字节
        return address(uint160(uint256(hash)));  // 将 32 字节哈希转换为 20 字节地址：bytes32 → uint256 → 取低 160 位 → address
    }

    // ============ 管理函数 ============

    /**
     * @notice 设置 MetaNode 核心合约地址
     * @dev 仅限 DEFAULT_ADMIN_ROLE 调用
     *
     * @param _metaNode 新的核心合约地址
     *
     * ============ 执行流程 ============
     * 1. 校验非零地址
     * 2. 授予 _metaNode DEPLOYER_ROLE
     * 3. 更新 metaNode 状态变量
     *
     * 注意：
     * - 旧地址的 DEPLOYER_ROLE 不会自动撤销
     * - 建议在初始化时调用一次
     */
    function setMetaNode(address _metaNode) external onlyRole(DEFAULT_ADMIN_ROLE) {  // external：仅外部调用；onlyRole(DEFAULT_ADMIN_ROLE)：只有默认管理员可调用
        require(_metaNode != address(0), "ZeroAddress");  // 校验：新地址不能为零地址；零地址 0x0000...0000 通常表示无效或未设置，若设为零地址则代币会铸造给零地址（永久锁定）
        _grantRole(DEPLOYER_ROLE, _metaNode);  // 授予新 metaNode 地址 DEPLOYER_ROLE 角色；使其能够调用 deployToken 部署代币；注意：旧的 metaNode 如果之前被授予了 DEPLOYER_ROLE，其角色不会被自动撤销
        metaNode = _metaNode;  // 更新 metaNode 状态变量；后续部署的代币将铸造给新地址
    }
}
