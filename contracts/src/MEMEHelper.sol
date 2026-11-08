// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;  // 编译器版本声明：使用 Solidity 0.8.20 及以上版本，0.8.x 内置溢出检查

import {IERC20} from"@openzeppelin/contracts/token/ERC20/IERC20.sol";  // 导入 ERC20 标准接口，定义了代币的基本函数（transfer、approve、balanceOf 等）
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";  // 导入访问控制合约，提供基于角色的权限管理（RBAC）
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";  // 导入安全 ERC20 操作库，处理不兼容 ERC20 标准的代币转账（检查返回值）
import {IMEMEHelper} from "./interfaces/IMEMEHelper.sol";  // 导入 MEMEHelper 接口，定义了本合约必须实现的函数签名
import {IMEMECore} from "./interfaces/IMEMECore.sol";  // 导入 MEMECore 接口，获取 BondingCurveParams 结构体定义
import {IPancakeFactory} from "./interfaces/IPancakeFactory.sol";  // 导入 PancakeSwap 工厂接口，用于获取/创建交易对
import {IPancakeRouter02} from "./interfaces/IPancakeRouter02.sol";  // 导入 PancakeSwap V2 路由接口，用于添加流动性和获取工厂地址
import {IPancakePair} from "./interfaces/IPancakePair.sol";  // 导入 PancakeSwap 交易对接口，用于查询储备量等（本合约中未直接使用但保留）

/**
 * @title MEMEHelper
 * @author MetaNode Team
 * @notice 联合曲线计算与 DEX 集成助手合约
 *
 * ============ 合约职责 ============
 * 1. 联合曲线的数学计算（买入/卖出/价格）
 * 2. PancakeSwap V2 流动性操作
 * 3. 交易对地址预测
 *
 * ============ 恒定乘积公式详解 ============
 *
 * 基本公式：k = x × y（始终不变）
 * - x = virtualBNBReserve（虚拟 BNB 储备）
 * - y = virtualTokenReserve（虚拟代币储备）
 * - k = 恒定乘积（创建时确定，不变）
 *
 * 【买入计算】
 * 用户支付 Δx BNB，获得 Δy 代币
 *
 * 交易前：x × y = k
 * 交易后：(x + Δx) × (y - Δy) = k
 * 推导：y - Δy = k / (x + Δx)
 * 结果：Δy = y - k / (x + Δx)
 *
 * 代码实现：
 * newBNBReserve = virtualBNBReserve + bnbIn
 * newTokenReserve = k / newBNBReserve
 * tokenOut = virtualTokenReserve - newTokenReserve
 *
 * 【卖出计算】
 * 用户支付 Δy 代币，获得 Δx BNB
 *
 * 交易前：x × y = k
 * 交易后：(x - Δx) × (y + Δy) = k
 * 推导：x - Δx = k / (y + Δy)
 * 结果：Δx = x - k / (y + Δy)
 *
 * 代码实现：
 * newTokenReserve = virtualTokenReserve + tokenIn
 * newBNBReserve = k / newTokenReserve
 * bnbOut = virtualBNBReserve - newBNBReserve
 *
 * 【价格计算】
 * 当前价格 = x / y（BNB/代币）
 * 买入越多价格越高（x↑, y↓）
 * 卖出越多价格越低（x↓, y↑）
 *
 * ============ DEX 集成说明 ============
 *
 * 毕业时调用 addLiquidityV2：
 * 1. 将剩余代币和 BNB 添加到 PancakeSwap
 * 2. 获得 LP 代币（流动性凭证）
 * 3. LP 代币发送到死地址（永久锁定流动性）
 *
 * 这确保：
 * - 流动性不会被撤走（Rug Pull 防护）
 * - 代币可以在 DEX 自由交易
 *
 * ============ 访问控制 ============
 * - DEFAULT_ADMIN_ROLE：管理员，可紧急提取、授权升级
 * - CORE_ROLE：核心合约（MEMECore），可调用 addLiquidityV2
 */
contract MEMEHelper is IMEMEHelper, AccessControl {  // 合约声明：继承 IMEMEHelper 接口和 AccessControl 访问控制
    using SafeERC20 for IERC20;  // 将 SafeERC20 库函数绑定到 IERC20 类型，使 IERC20(token).safeTransfer 等调用可用

    // ============ 角色常量 ============

    /**
     * @notice 核心合约角色
     * @dev 拥有此角色才能调用 addLiquidityV2
     * 授予 MEMECore 合约
     */
    bytes32 public constant CORE_ROLE = keccak256("CORE_ROLE");  // 角色标识：对字符串 "CORE_ROLE" 进行 keccak256 哈希，生成唯一的 32 字节角色 ID

    // ============ 系统常量 ============

    /**
     * @notice 最小流动性（LP 代币）
     * @dev PancakeSwap 要求首次添加流动性时锁定最小数量
     * 防止操纵攻击（参考 Uniswap V2 设计）
     * 首次添加流动性时，MINIMUM_LIQUIDITY（1000 wei）被永久锁定
     */
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;  // 最小流动性常量 = 10^3 = 1000 wei；首次添加流动性时此数量被永久锁死在交易对合约中，防止极小储备量下的价格操纵攻击

    // ============ 不可变变量 ============

    /**
     * @notice PancakeSwap V2 路由合约地址
     * @dev 用于添加流动性操作
     * BSC 主网：0x10ED43C718714eb63d5aA57B78B54704E256024E
     * 路由合约是用户与 PancakeSwap 交互的入口
     */
    address public immutable PANCAKE_V2_ROUTER;  // 不可变变量：PancakeSwap V2 路由器地址，构造函数中赋值后不可修改；immutable 变量在部署时写入字节码，比 storage 变量节省 gas

    /**
     * @notice WBNB 合约地址
     * @dev 用于获取交易对地址
     * BSC 主网：0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c
     * WBNB 是 BNB 的 ERC20 包装代币，DEX 交易使用 WBNB 而非原生 BNB
     */
    address public immutable WBNB;  // 不可变变量：WBNB（Wrapped BNB）合约地址，DEX 中原生 BNB 需要包装成 WBNB 才能与 ERC20 代币配对交易

    // ============ 构造函数 ============

    /**
     * @notice 初始化助手合约
     * @dev 部署时一次性设置关键参数，后续不可更改
     * @param _admin 管理员地址，获得 DEFAULT_ADMIN_ROLE 和 CORE_ROLE
     * @param _router PancakeSwap V2 路由地址
     * @param _wbnb WBNB 合约地址
     *
     * ============ 安全检查 ============
     * - _router 和 _wbnb 不能为零地址
     * - 管理员获得所有基础权限
     */
    constructor(address _admin, address _router, address _wbnb) {  // 构造函数：部署时调用，初始化合约状态；参数 _admin 为管理员地址，_router 为 PancakeSwap 路由地址，_wbnb 为 WBNB 地址
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);  // 授予管理员默认管理员角色（DEFAULT_ADMIN_ROLE），此角色拥有最高权限，可授予/撤销其他角色
        _grantRole(CORE_ROLE, _admin);  // 同时授予管理员核心合约角色（CORE_ROLE），使管理员在初始阶段也能执行 addLiquidityV2
        if (_router == address(0)) revert ZeroAddress();  // 安全检查：路由地址不能为零地址，零地址意味着合约无法与 PancakeSwap 交互
        if (_wbnb == address(0)) revert ZeroAddress();  // 安全检查：WBNB 地址不能为零地址，零地址意味着无法正确计算交易对地址
        PANCAKE_V2_ROUTER = _router;  // 设置不可变变量：PancakeSwap V2 路由器地址，后续无法修改
        WBNB = _wbnb;  // 设置不可变变量：WBNB 合约地址，后续无法修改
    }

    // ============ DEX 操作函数 ============

    /**
     * @notice 添加 PancakeSwap V2 流动性
     * @dev 仅限 CORE_ROLE（MEMECore）调用
     *
     * @param token 代币地址
     * @param bnbAmount 添加的 BNB 数量（wei）
     * @param tokenAmount 添加的代币数量（wei）
     * @return liquidity 获得的 LP 代币数量
     *
     * ============ 执行流程 ============
     *
     * 1. 【校验参数】
     *    - bnbAmount > 0
     *    - tokenAmount > 0
     *
     * 2. 【转入代币】
     *    - 从调用者（MEMECore）转入代币到本合约
     *    - 使用 SafeERC20 防止转账失败（兼容非标准 ERC20）
     *
     * 3. 【授权路由】
     *    - 授权 PancakeSwap 路由操作代币
     *    - 授权数量为 tokenAmount（精确授权，非无限授权）
     *
     * 4. 【添加流动性】
     *    - 调用 addLiquidityETH
     *    - 设置 5% 滑点保护（minAmount = desired × 95%）
     *    - LP 接收者设为死地址（永久锁定，防 Rug Pull）
     *    - 5 分钟超时保护（deadline = block.timestamp + 300）
     *
     * ============ 安全设计 ============
     * - LP 代币发送到死地址，流动性永久锁定
     * - 5% 滑点保护，可能部分代币/BNB 退回
     * - 5 分钟超时保护，防止交易长时间挂起
     */
    function addLiquidityV2(  // 函数：添加 PancakeSwap V2 流动性，在代币"毕业"时由 MEMECore 调用
        address token,  // 参数：代币合约地址，指定要添加流动性的代币
        uint256 bnbAmount,  // 参数：要添加的 BNB 数量（单位 wei，1 BNB = 1e18 wei）
        uint256 tokenAmount  // 参数：要添加的代币数量（单位 wei，取决于代币的 decimals）
    ) external payable onlyRole(CORE_ROLE) returns (uint256 liquidity) {  // external：仅外部调用；payable：可接收 BNB；onlyRole(CORE_ROLE)：仅核心合约角色可调用；returns liquidity：返回获得的 LP 代币数量
        // 1. 校验参数：确保两种资产数量都大于零
        if (bnbAmount == 0 || tokenAmount == 0) revert ZeroAmount();  // 检查 BNB 和代币数量都不为零；任一为零则无法构成有意义的流动性池，回滚交易

        // 2. 转入代币：从调用者（MEMECore）转入代币到本合约
        // SafeERC20.safeTransferFrom 会检查返回值，兼容非标准 ERC20
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);  // 从调用者（msg.sender，即 MEMECore）转移 tokenAmount 数量的代币到本合约（address(this)）；使用 safeTransferFrom 而非 transferFrom 是因为某些代币（如 USDT）不返回 bool 值

        // 3. 授权路由：授权 PancakeSwap 路由合约转移代币
        // 使用精确授权而非无限授权，减少风险敞口
        IERC20(token).approve(PANCAKE_V2_ROUTER, tokenAmount);  // 授权 PancakeSwap 路由合约可以转移最多 tokenAmount 数量的代币；精确授权而非 type(uint256).max 无限授权，降低安全风险

        // 4. 添加流动性（LP 发送到死地址）
        // addLiquidityETH 参数说明：
        // - token: 代币地址
        // - amountTokenDesired: 期望添加的代币数量
        // - amountTokenMin: 最小代币数量（5% 滑点保护）
        // - amountETHMin: 最小 BNB 数量（5% 滑点保护）
        // - deadline: 交易截止时间（5 分钟超时）
        // - optOutUserShare: true 表示 LP 发送到死地址（永久锁定）
        (,, liquidity) = IPancakeRouter02(PANCAKE_V2_ROUTER).addLiquidityETH{value: bnbAmount}(  // 调用 PancakeSwap 路由的 addLiquidityETH 函数；{value: bnbAmount} 附带 BNB；返回三个值：实际使用的代币量、实际使用的 BNB 量、获得的 LP 数量；我们只关心 liquidity
            token,  // 代币地址：指定要添加流动性的代币合约
            tokenAmount,  // 期望添加的代币数量：这是期望值，实际可能因滑点而不同
            tokenAmount * 95 / 100,  // 最小代币数量 = tokenAmount × 95 / 100，即允许 5% 的滑点；例如期望添加 1000 代币，最少接受 950 代币；如果低于此值交易回滚
            bnbAmount * 95 / 100,    // 最小 BNB 数量 = bnbAmount × 95 / 100，即允许 5% 的滑点；同理，如果实际使用的 BNB 少于期望的 95%，交易回滚
            block.timestamp + 300,   // 交易截止时间 = 当前区块时间戳 + 300 秒（5 分钟）；超过此时间交易自动回滚，防止交易在内存池中长期挂起后被执行
            true                     // LP 发送到死地址（optOutUserShare=true）；PancakeSwap 将 LP 代币发送到 0x...dead 地址，永久锁定流动性，防止项目方撤走流动性（Rug Pull 防护）
        );
    }

    /**
     * @notice 获取/预测交易对地址
     * @dev 如果交易对已存在则直接返回，否则使用 CREATE2 预测
     *
     * @param token 代币地址
     * @return pair 交易对合约地址
     *
     * ============ 地址计算说明 ============
     *
     * PancakeSwap 使用 CREATE2 部署交易对：
     * pair = keccak256(0xff, factory, salt, INIT_CODE_HASH)[12:]
     *
     * 其中：
     * - factory = PancakeSwap 工厂地址（从路由合约获取）
     * - salt = keccak256(token0, token1)，token0 < token1（按地址排序）
     * - INIT_CODE_HASH = 交易对合约的字节码哈希（PancakeSwap V2 固定值）
     *
     * CREATE2 保证：相同的 factory、salt、INIT_CODE_HASH 总是产生相同的地址
     * 这使得我们可以在交易对创建前预测其地址
     *
     * ============ 执行流程 ============
     * 1. 从路由合约获取工厂地址
     * 2. 尝试获取已存在的交易对
     * 3. 如果不存在，使用 CREATE2 公式预测地址
     * 4. 尝试从工厂获取 INIT_CODE_HASH（某些版本支持）
     */
    function getPairAddress(address token) external view override returns (address pair) {  // 函数：获取代币与 WBNB 的交易对地址；view：只读函数不修改状态；override：实现接口中的函数
        // 从路由合约获取工厂地址
        address factory = IPancakeRouter02(PANCAKE_V2_ROUTER).factory();  // 调用路由合约的 factory() 函数获取 PancakeSwap 工厂合约地址；工厂合约负责创建和管理所有交易对

        // 尝试获取已存在的交易对
        pair = IPancakeFactory(factory).getPair(token, WBNB);  // 查询工厂合约中是否已存在 token-WBNB 交易对；如果存在直接返回交易对地址，避免重复计算

        // 如果不存在，预测地址
        if (pair == address(0)) {  // 如果工厂返回零地址，说明交易对尚未创建，需要通过 CREATE2 公式预测地址
            // 排序代币地址（token0 < token1）
            // PancakeSwap 要求交易对中 token0 地址小于 token1
            (address token0, address token1) = token < WBNB  // 比较代币地址和 WBNB 地址的数值大小
                ? (token, WBNB)  // 如果 token 地址较小，则 token0 = token，token1 = WBNB
                : (WBNB, token);  // 如果 WBNB 地址较小，则 token0 = WBNB，token1 = token；排序是必须的，因为 CREATE2 的 salt 依赖顺序

            // PancakeSwap V2 INIT_CODE_HASH (BSC Mainnet & Testnet)
            // 此值为 PancakePair 合约字节码的 keccak256 哈希
            // 用于 CREATE2 地址计算
            bytes32 initCodeHash = 0xd0d4c4cd0848c93cb4fd1f498d7013ee6bfb25783ea21593d5834f5d250ece66;  // PancakeSwap V2 默认的 INIT_CODE_HASH；这是 PancakePair 合约编译后字节码的 keccak256 哈希值，BSC 主网和测试网通用

            // 尝试从工厂合约获取 INIT_CODE_HASH（某些版本可能支持）
            // 如果工厂合约有 INIT_CODE_HASH() 函数，使用其实际值
            try IPancakeFactory(factory).INIT_CODE_HASH() returns (bytes32 hash) {  // 尝试调用工厂合约的 INIT_CODE_HASH() 函数；某些修改版的 PancakeSwap 可能有不同的哈希值
                initCodeHash = hash;  // 如果调用成功，使用工厂合约返回的实际哈希值，确保地址预测准确
            } catch {  // 如果工厂合约没有此函数或调用失败
                // 使用默认值（大多数 PancakeSwap V2 工厂使用上述固定值）
                // 什么都不做，保持 initCodeHash 为默认值
            }

            // 使用 CREATE2 公式计算地址
            // 公式：address = uint160(uint256(keccak256(abi.encodePacked(
            //   hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), initCodeHash
            // ))))
            pair = address(  // 将计算出的 20 字节地址转换为 address 类型
                uint160(  // 取 256 位哈希的低 160 位作为地址；EVM 地址为 20 字节 = 160 位
                    uint256(  // 将 bytes32 转为 uint256 以便截取低 160 位
                        keccak256(  // 对拼接后的数据进行 keccak256 哈希运算，生成 32 字节结果
                            abi.encodePacked(  // 紧凑编码（无填充），将以下四个元素拼接成字节序列
                                hex"ff",                           // CREATE2 前缀：0xff，这是 EVM CREATE2 操作码的固定前缀，区分 CREATE 和 CREATE2
                                factory,                           // 部署者（工厂合约）：CREATE2 地址计算需要知道部署者地址
                                keccak256(abi.encodePacked(token0, token1)), // salt：由两个代币地址的哈希构成；相同代币顺序总是产生相同的 salt
                                initCodeHash                       // 初始化代码哈希：被部署合约的字节码哈希，确保只有相同代码的合约才能产生相同地址
                            )
                        )
                    )
                )
            );  // 最终结果：预测的 PancakeSwap 交易对地址；CREATE2 保证在交易对实际创建后地址与预测一致
        }
    }

    /**
     * @notice 估算添加流动性获得的 LP 数量
     * @dev 仅用于首次添加流动性的估算
     *
     * @param token 代币地址
     * @param bnbAmount BNB 数量（wei）
     * @param tokenAmount 代币数量（wei）
     * @return 估算的 LP 代币数量
     *
     * ============ 计算公式 ============
     *
     * 首次添加流动性：
     * LP = sqrt(bnbAmount × tokenAmount) - MINIMUM_LIQUIDITY
     *
     * 其中 MINIMUM_LIQUIDITY = 1000（永久锁定，防止价格操纵）
     *
     * 已有流动性：需要更复杂计算（此处返回 0）
     * 实际 LP = min(
     *   bnbAmount × totalSupply / reserveBNB,
     *   tokenAmount × totalSupply / reserveToken
     * )
     */
    function estimateLPTokens(  // 函数：估算添加流动性可获得的 LP 代币数量；用于前端展示预期 LP 收益
        address token,  // 参数：代币地址，用于查询交易对是否存在
        uint256 bnbAmount,  // 参数：要添加的 BNB 数量
        uint256 tokenAmount  // 参数：要添加的代币数量
    ) external view returns (uint256) {  // external view：外部只读函数，不修改链上状态
        // 获取交易对地址
        address pair = IPancakeFactory(IPancakeRouter02(PANCAKE_V2_ROUTER).factory()).getPair(token, WBNB);  // 通过路由合约获取工厂地址，再查询交易对是否存在；链式调用：router → factory → getPair

        if (pair == address(0)) {  // 如果交易对不存在，说明是首次添加流动性
            // 首次添加流动性：使用几何平均数计算 LP
            uint256 product = bnbAmount * tokenAmount;  // 计算 BNB 和代币数量的乘积；例如 10 BNB × 1000000 代币 = 10,000,000
            uint256 liquidity = sqrt(product);  // 对乘积开平方根；几何平均数 sqrt(x × y) 是 Uniswap/PancakeSwap 首次添加流动性时的 LP 计算方式；例如 sqrt(10,000,000) ≈ 3162

            // 扣除最小流动性（永久锁定）
            if (liquidity > MINIMUM_LIQUIDITY) {  // 如果计算出的 LP 数量大于最小流动性（1000）
                return liquidity - MINIMUM_LIQUIDITY;  // 返回扣除最小流动性后的 LP 数量；最小流动性被永久锁死在交易对合约中，不属于任何人
            } else {  // 如果计算出的 LP 数量不足最小流动性
                return 0;  // 返回 0，表示添加流动性无意义（流动性太少）
            }
        } else {  // 如果交易对已存在
            // 已有流动性，需要更复杂计算
            // 实际计算需要知道当前储备量和总供应量
            return 0;  // 返回 0 表示无法简单估算；已有流动性时 LP = min(增量BNB/储备BNB, 增量Token/储备Token) × 总供应量，需要查询链上储备数据
        }
    }

    // ============ 曲线计算函数 ============

    /**
     * @notice 计算买入可获得的代币数量（不含手续费）
     * @dev 核心买入计算函数，使用恒定乘积公式
     *
     * @param bnbIn 输入的 BNB 数量（wei）
     * @param curve 当前曲线参数（virtualBNBReserve, virtualTokenReserve, k）
     * @return tokenOut 可获得的代币数量（wei）
     *
     * ============ 数学推导 ============
     *
     * 恒定乘积：k = x × y
     * - x = virtualBNBReserve（当前虚拟 BNB 储备）
     * - y = virtualTokenReserve（当前虚拟代币储备）
     *
     * 用户支付 Δx BNB，获得 Δy 代币：
     * 交易后储备：(x + Δx) × (y - Δy) = k
     *
     * 推导过程：
     * 1. y - Δy = k / (x + Δx)
     * 2. Δy = y - k / (x + Δx)
     *
     * 代码实现：
     * newBNBReserve = virtualBNBReserve + bnbIn
     * newTokenReserve = k / newBNBReserve
     * tokenOut = virtualTokenReserve - newTokenReserve
     *
     * ============ 价格影响 ============
     * - bnbIn 越大，tokenOut 相对越少（价格滑点）
     * - 当 bnbIn 接近 virtualBNBReserve 时，价格急剧上升
     */
    function calculateTokenAmountOut(  // 函数：计算买入可获得的代币数量（不含手续费版本）；核心买入计算逻辑
        uint256 bnbIn,  // 参数：用户输入的 BNB 数量（wei 单位）
        IMEMECore.BondingCurveParams memory curve  // 参数：联合曲线参数结构体，包含 virtualBNBReserve（虚拟 BNB 储备）、virtualTokenReserve（虚拟代币储备）、k（恒定乘积）
    ) external pure override returns (uint256 tokenOut) {  // pure：纯函数，不读写状态；override：实现接口定义；返回 tokenOut：可获得的代币数量
        // 输入校验
        if (bnbIn == 0) return 0;  // 如果输入 BNB 为零，返回 0 代币；避免除零错误和无意义的计算
        // 曲线参数校验：k 和 virtualBNBReserve 必须大于零
        if (curve.k == 0 || curve.virtualBNBReserve == 0) revert InvalidCurve();  // 检查曲线参数有效性；k=0 或 virtualBNBReserve=0 会导致除零错误或无意义结果

        // 计算新的 BNB 储备 = 当前储备 + 输入 BNB
        uint256 newBNBReserve = curve.virtualBNBReserve + bnbIn;  // 新 BNB 储备 = 原 BNB 储备 + 用户投入的 BNB；这是恒定乘积公式中 x 变量的新值

        // 使用恒定乘积计算新的代币储备
        // k = newBNBReserve × newTokenReserve
        // newTokenReserve = k / newBNBReserve
        uint256 newTokenReserve = curve.k / newBNBReserve;  // 根据恒定乘积公式 k = x × y 推导：新代币储备 = k / 新BNB储备；Solidity 整数除法向下取整，确保不会多发给用户代币

        // 计算代币输出量 = 当前代币储备 - 新代币储备
        // 如果新储备大于等于当前储备，说明计算有误或曲线已耗尽
        if (curve.virtualTokenReserve <= newTokenReserve) {return 0;}  // 安全检查：如果当前代币储备 <= 新代币储备，意味着无法取出代币；这种情况理论上不应发生，但整数除法可能导致边界情况
        tokenOut = curve.virtualTokenReserve - newTokenReserve;  // 代币输出 = 当前代币储备 - 新代币储备；即 Δy = y - k/(x+Δx)；用户获得的代币数量等于储备减少量
    }

    /**
     * @notice 计算买入（含手续费明细）
     * @dev 在 calculateTokenAmountOut 基础上增加手续费计算
     *
     * @param bnbIn 输入的 BNB 数量（wei）
     * @param curve 当前曲线参数
     * @param feeRate 手续费率（基点，如 100 = 1%，10000 = 100%）
     * @return tokenOut 可获得的代币数量（wei）
     * @return netBNB 扣除手续费后实际进入曲线的 BNB
     * @return feeBNB 手续费金额
     *
     * ============ 手续费计算 ============
     * feeBNB = bnbIn × feeRate / 10000
     * netBNB = bnbIn - feeBNB
     *
     * 代币计算使用 netBNB（手续费不进入曲线）
     */
    function calculateTokenAmountOutWithFee(  // 函数：计算买入可获得代币数量（含手续费明细）；在基础版本上增加手续费分离逻辑
        uint256 bnbIn,  // 参数：用户输入的 BNB 数量
        IMEMECore.BondingCurveParams memory curve,  // 参数：联合曲线参数
        uint256 feeRate  // 参数：手续费率，以基点（basis points）表示；100 = 1%，500 = 5%，10000 = 100%
    ) external pure override returns (uint256 tokenOut, uint256 netBNB, uint256 feeBNB) {  // 返回三个值：可获得代币数、净BNB、手续费BNB
        if (bnbIn == 0) return (0, 0, 0);  // 输入为零时全部返回零，避免无意义计算
        if (curve.k == 0 || curve.virtualBNBReserve == 0) revert InvalidCurve();  // 曲线参数有效性检查

        // 计算手续费：bnbIn × feeRate / 10000
        // 例如：feeRate = 100（1%），bnbIn = 1 BNB
        // feeBNB = 1 × 100 / 10000 = 0.01 BNB
        feeBNB = (bnbIn * feeRate) / 10000;  // 手续费 = 输入BNB × 费率 / 10000；基点转百分比的通用公式：1 基点 = 0.01%；例如 100 基点 = 1%；先乘后除避免精度损失
        netBNB = bnbIn - feeBNB;  // 净BNB = 输入BNB - 手续费；这是实际参与联合曲线计算的 BNB 数量；手续费部分不进入曲线，不影响价格曲线

        // 用净额计算代币（手续费不进入曲线）
        uint256 newBNBReserve = curve.virtualBNBReserve + netBNB;  // 新 BNB 储备 = 原储备 + 净BNB（不含手续费）；手续费已被分离，不进入恒定乘积计算
        uint256 newTokenReserve = curve.k / newBNBReserve;  // 新代币储备 = k / 新BNB储备；恒定乘积公式的直接应用

        if (curve.virtualTokenReserve <= newTokenReserve) {  // 安全检查：确保代币储备充足
            return (0, netBNB, feeBNB);  // 返回零代币输出，但仍返回净BNB和手续费信息
        }
        tokenOut = curve.virtualTokenReserve - newTokenReserve;  // 代币输出 = 当前代币储备 - 新代币储备；与不含手续费版本公式相同，只是输入 BNB 被替换为净 BNB
    }

    /**
     * @notice 计算卖出可获得的 BNB（不含手续费）
     * @dev 核心卖出计算函数，使用恒定乘积公式
     *
     * @param tokenIn 输入的代币数量（wei）
     * @param curve 当前曲线参数
     * @return bnbOut 可获得的 BNB 数量（wei）
     *
     * ============ 数学推导 ============
     *
     * 恒定乘积：k = x × y
     *
     * 用户支付 Δy 代币，获得 Δx BNB：
     * 交易后储备：(x - Δx) × (y + Δy) = k
     *
     * 推导过程：
     * 1. x - Δx = k / (y + Δy)
     * 2. Δx = x - k / (y + Δy)
     *
     * 代码实现：
     * newTokenReserve = virtualTokenReserve + tokenIn
     * newBNBReserve = k / newTokenReserve
     * bnbOut = virtualBNBReserve - newBNBReserve
     *
     * ============ 价格影响 ============
     * - tokenIn 越大，bnbOut 相对越少（价格滑点）
     * - 卖出增加代币储备，降低价格
     */
    function calculateBNBAmountOut(  // 函数：计算卖出代币可获得的 BNB 数量（不含手续费版本）；卖出是买入的逆向操作
        uint256 tokenIn,  // 参数：用户卖出的代币数量
        IMEMECore.BondingCurveParams memory curve  // 参数：联合曲线参数
    ) external pure override returns (uint256) {  // 返回可获得的 BNB 数量
        if (tokenIn == 0) return 0;  // 输入为零时返回零，避免无意义计算
        if (curve.k == 0 || curve.virtualTokenReserve == 0) revert InvalidCurve();  // 曲线参数有效性检查；k=0 会导致除零，virtualTokenReserve=0 会导致无效的卖出操作

        // 计算新的代币储备 = 当前储备 + 输入代币
        uint256 newTokenReserve = curve.virtualTokenReserve + tokenIn;  // 新代币储备 = 原代币储备 + 用户卖出的代币；卖出时代币进入储备，储备量增加

        // 使用恒定乘积计算新的 BNB 储备
        // k = newBNBReserve × newTokenReserve
        // newBNBReserve = k / newTokenReserve
        uint256 newBNBReserve = curve.k / newTokenReserve;  // 根据恒定乘积公式：新 BNB 储备 = k / 新代币储备；代币储备增加，BNB 储备必然减少

        // 计算 BNB 输出量 = 当前 BNB 储备 - 新 BNB 储备
        if (curve.virtualBNBReserve <= newBNBReserve) return 0;  // 安全检查：如果当前 BNB 储备 <= 新 BNB 储备，说明卖出后 BNB 储备反而增加了，这不应发生；返回 0 防止异常
        return curve.virtualBNBReserve - newBNBReserve;  // BNB 输出 = 当前 BNB 储备 - 新 BNB 储备；即 Δx = x - k/(y+Δy)；用户获得的 BNB 数量等于 BNB 储备减少量
    }

    /**
     * @notice 计算卖出（含手续费明细）
     * @dev 在 calculateBNBAmountOut 基础上增加手续费计算
     *
     * @param tokenIn 输入的代币数量（wei）
     * @param curve 当前曲线参数
     * @param feeRate 手续费率（基点，如 100 = 1%）
     * @return netBNB 扣除手续费后可获得的 BNB
     * @return feeBNB 手续费金额
     *
     * ============ 手续费计算 ============
     * 与买入不同，卖出手续费从 BNB 输出中扣除：
     * grossBNB = 曲线计算出的原始 BNB 输出
     * feeBNB = grossBNB × feeRate / 10000
     * netBNB = grossBNB - feeBNB
     */
    function calculateBNBAmountOutWithFee(  // 函数：计算卖出代币可获得的 BNB（含手续费明细）；卖出手续费从 BNB 输出中扣除
        uint256 tokenIn,  // 参数：用户卖出的代币数量
        IMEMECore.BondingCurveParams memory curve,  // 参数：联合曲线参数
        uint256 feeRate  // 参数：手续费率（基点）
    ) external pure override returns (uint256 netBNB, uint256 feeBNB) {  // 返回净BNB和手续费BNB；注意：与买入不同，卖出手续费从输出中扣除，而非从输入中扣除
        if (tokenIn == 0) return (0, 0);  // 输入为零时全部返回零
        if (curve.k == 0 || curve.virtualTokenReserve == 0) revert InvalidCurve();  // 曲线参数有效性检查

        // 计算原始 BNB 输出（不含手续费）
        uint256 newTokenReserve = curve.virtualTokenReserve + tokenIn;  // 新代币储备 = 原代币储备 + 卖出代币量
        uint256 newBNBReserve = curve.k / newTokenReserve;  // 新 BNB 储备 = k / 新代币储备；恒定乘积公式

        if (curve.virtualBNBReserve <= newBNBReserve) return (0, 0);  // 安全检查：BNB 储备不足时返回零
        uint256 grossBNB = curve.virtualBNBReserve - newBNBReserve;  // 毛BNB输出 = 当前 BNB 储备 - 新 BNB 储备；这是曲线计算出的原始 BNB 数量，手续费尚未扣除

        // 计算手续费：从 BNB 输出中扣除
        feeBNB = (grossBNB * feeRate) / 10000;  // 手续费 = 毛BNB输出 × 费率 / 10000；注意：卖出时手续费基于输出金额计算，而买入时手续费基于输入金额计算
        netBNB = grossBNB - feeBNB;  // 净BNB = 毛BNB - 手续费；用户实际收到的 BNB 数量
    }

    /**
     * @notice 计算购买指定数量代币需要的 BNB
     * @dev 反向计算，用于精确购买（如"我要买 1000 个代币，需要多少 BNB"）
     *
     * @param tokenOut 期望获得的代币数量（wei）
     * @param curve 当前曲线参数
     * @return bnbIn 需要支付的 BNB 数量（wei）
     *
     * ============ 数学推导 ============
     *
     * 已知：期望获得 Δy 代币
     * 求：需要支付 Δx BNB
     *
     * 交易后储备：(x + Δx) × (y - Δy) = k
     *
     * 推导过程：
     * 1. x + Δx = k / (y - Δy)
     * 2. Δx = k / (y - Δy) - x
     *
     * 代码实现：
     * newTokenReserve = virtualTokenReserve - tokenOut
     * newBNBReserve = k / newTokenReserve
     * bnbIn = newBNBReserve - virtualBNBReserve
     *
     * ============ 使用场景 ============
 * - 前端显示"购买 X 代币需要 Y BNB"
     * - 用户指定购买数量时的价格估算
     */
    function calculateRequiredBNB(  // 函数：反向计算购买指定数量代币所需的 BNB；用于前端展示"买 X 个代币需要多少 BNB"
        uint256 tokenOut,  // 参数：期望获得的代币数量
        IMEMECore.BondingCurveParams memory curve  // 参数：联合曲线参数
    ) external pure override returns (uint256 bnbIn) {  // 返回需要的 BNB 数量
        if (tokenOut == 0) return 0;  // 如果期望代币为零，返回零 BNB
        if (curve.k == 0 || curve.virtualTokenReserve == 0) revert InvalidCurve();  // 曲线参数有效性检查

        // 计算购买后的代币储备 = 当前储备 - 购买量
        uint256 newTokenReserve = curve.virtualTokenReserve - tokenOut;  // 新代币储备 = 当前代币储备 - 用户要获得的代币量；这是买入后储备的代币量

        // 使用恒定乘积计算需要的 BNB 储备
        // k = newBNBReserve × newTokenReserve
        // newBNBReserve = k / newTokenReserve
        uint256 newBNBReserve = curve.k / newTokenReserve;  // 新 BNB 储备 = k / 新代币储备；代入恒定乘积公式，计算对应的 BNB 储备量

        // 计算需要输入的 BNB = 新 BNB 储备 - 当前 BNB 储备
        if (newBNBReserve <= curve.virtualBNBReserve) {  // 安全检查：如果新 BNB 储备 <= 当前 BNB 储备，说明计算异常
            return 0;  // 返回零，避免返回负值（Solidity 无负数，下溢会 panic）
        }
        bnbIn = newBNBReserve - curve.virtualBNBReserve;  // 所需 BNB = 新 BNB 储备 - 当前 BNB 储备；即 Δx = k/(y-Δy) - x；用户需要支付的 BNB 数量
    }

    /**
     * @notice 获取当前代币价格
     * @dev 价格 = BNB 储备 / 代币储备（单位：BNB/Token）
     *
     * @param curve 曲线参数
     * @return price 价格（BNB/Token × 1e18，用于保留精度）
     *
     * ============ 计算公式 ============
     * price = virtualBNBReserve × 1e18 / virtualTokenReserve
     *
     * 乘以 1e18 是为了在整数运算中保留精度
     * 例如：virtualBNBReserve = 10 BNB, virtualTokenReserve = 1,000,000 代币
     * price = 10 × 1e18 / 1,000,000 = 0.00001 × 1e18 = 1e13
     *
     * 实际价格（BNB/Token）= price / 1e18
     */
    function getPrice(  // 函数：获取当前联合曲线上的代币价格
        IMEMECore.BondingCurveParams memory curve  // 参数：联合曲线参数
    ) external pure override returns (uint256) {  // 返回价格（乘以 1e18 的放大价格，用于保留精度）
        if (curve.virtualTokenReserve == 0) return 0;  // 防止除零；代币储备为零时价格未定义，返回零
        return (curve.virtualBNBReserve * 1e18) / curve.virtualTokenReserve;  // 价格 = BNB 储备 × 1e18 / 代币储备；先乘 1e18 再除，避免整数除法丢失精度；结果单位为 BNB/Token × 1e18
    }

    // ============ 内部函数 ============

    /**
     * @notice 平方根计算（巴比伦法 / 牛顿迭代法）
     * @dev 用于估算首次添加流动性时的 LP 代币数量
     *
     * @param x 输入值
     * @return 平方根（向下取整）
     *
     * ============ 算法说明 ============
     * 巴比伦法（牛顿迭代法求平方根）：
     * 1. 初始猜测：z = (x + 1) / 2
     * 2. 迭代：z = (x / z + z) / 2
     * 3. 直到 z >= y（收敛）
     *
     * 时间复杂度：O(log x)，通常 10-20 次迭代即可收敛
     */
    function sqrt(uint256 x) internal pure returns (uint256) {  // 内部纯函数：计算平方根；使用巴比伦法（牛顿迭代法的特例）
        if (x == 0) return 0;  // 零的平方根为零，特殊处理避免除零
        uint256 z = (x + 1) / 2;  // 初始猜测值 z = (x + 1) / 2；加 1 确保对奇数也能正确向下取整；例如 x=4，z=2；x=9，z=5
        uint256 y = x;  // y 记录上一次迭代的值，初始为 x（一个肯定大于等于 sqrt(x) 的值）
        while (z < y) {  // 当 z < y 时继续迭代；迭代收敛条件：z 不再减小（z >= y）
            y = z;  // 更新 y 为当前 z 的值，保存本轮迭代结果
            z = (x / z + z) / 2;  // 牛顿迭代公式：z_new = (x / z_old + z_old) / 2；这是求解 z^2 = x 的牛顿法的迭代步骤；每次迭代 z 更接近 sqrt(x)
        }
        return y;  // 返回 y（而非 z），因为循环结束时 y 是最后一个满足 z < y 的值，即收敛后的正确结果
    }

    /**
     * @notice 排序代币地址
     * @dev PancakeSwap 要求 token0 < token1（按地址数值排序）
     * @param tokenA 代币 A 地址
     * @param tokenB 代币 B 地址
     * @return token0 地址较小的代币
     * @return token1 地址较大的代币
     */
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {  // 内部函数：对两个代币地址排序，确保 token0 < token1
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);  // 三元运算符：如果 tokenA 地址值小于 tokenB，则 token0=A, token1=B；否则交换顺序
        require(token0 != address(0), "Zero address");  // 确保排序后的 token0 不是零地址；如果任一输入为零地址，排序后零地址必然是 token0（零地址是最小地址）
    }

    // ============ 管理函数 ============

    /**
     * @notice 紧急提取资产
     * @dev 仅限 DEFAULT_ADMIN_ROLE，用于紧急情况（如合约漏洞、资金卡住）
     *
     * @param token 代币地址（address(0) 表示提取 BNB）
     * @param amount 提取数量（wei）
     *
     * ============ 安全考虑 ============
     * - 仅限管理员调用（AccessControl 保护）
     * - 应谨慎使用，避免滥用
     * - 提取 BNB 使用 transfer（2300 gas 限制，防止重入）
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {  // 紧急提取函数；onlyRole 确保只有管理员可调用
        if (token == address(0)) {  // 如果 token 参数为零地址，表示提取原生 BNB
            // 提取 BNB：使用 transfer 限制 gas，防止重入攻击
            payable(msg.sender).transfer(amount);  // 使用 address.transfer() 发送 BNB；transfer 限制转发 gas 为 2300，不足以执行重入攻击；但注意：某些合约钱包可能无法接收 transfer
        } else {  // 如果 token 参数为非零地址，表示提取 ERC20 代币
            // 提取 ERC20 代币：使用 SafeERC20 确保转账安全
            IERC20(token).safeTransfer(msg.sender, amount);  // 使用 safeTransfer 发送代币；安全处理不返回 bool 值的非标准 ERC20 代币
        }
    }

    /**
     * @notice 接收 BNB
     * @dev 用于接收添加流动性时的退款（PancakeSwap 可能退回多余 BNB）
     * 必须存在 receive/fallback 函数才能接收原生币
     */
    receive() external payable {}  // 接收 BNB 的回退函数；当合约收到纯 BNB 转账时触发；必须声明为 payable 才能接收 BNB；PancakeSwap 添加流动性后可能退回多余的 BNB
}
