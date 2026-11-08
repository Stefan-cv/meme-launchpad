// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title DeployConfig
 * @notice 部署配置管理合约
 * @dev 从 JSON 配置文件读取部署参数
 *
 * 配置文件结构示例（deploy-config/{chain}/{env}.json）：
 * {
 *   "Admin": "0x...",              // 管理员地址
 *   "Signer": "0x...",             // 签名者地址
 *   "PlatformFeeReceiver": "0x...",// 平台费用接收地址
 *   "MarginReceiver": "0x...",     // 保证金接收地址
 *   "GraduateFeeReceiver": "0x...",// 毕业费用接收地址
 *   "Router": "0x...",             // PancakeSwap Router 地址
 *   "WBNB": "0x...",               // WBNB 合约地址
 *   "MinLockTime": 86400,          // 最小锁仓时间（秒）
 *   "MEMEHelper": "0x...",         // 已部署的 Helper 地址（可选）
 *   "MEMEFactory": "0x...",        // 已部署的 Factory 地址（可选）
 *   "MEMECore": "0x...",           // 已部署的 Core 地址（可选）
 *   "MEMEVesting": "0x..."         // 已部署的 Vesting 地址（可选）
 * }
 */

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {Chains} from "./Chains.sol";

contract DeployConfig is Script {
    // ============ 内部状态 ============
    string internal _json;  // 原始 JSON 配置字符串

    // ============ 合约地址（已部署的合约地址，为 0 表示未部署）============
    address public MEMEHelper;      // 辅助合约地址
    address public MEMEFactory;     // 工厂合约地址
    address public MEMECore;        // 核心合约代理地址
    address public MEMEVesting;     // 归属合约代理地址

    // ============ 角色地址（必须在配置文件中提供）============
    address public Admin;                   // 管理员地址（拥有最高权限）
    address public Signer;                  // 签名者地址（用于验证创建请求）
    address public PlatformFeeReceiver;     // 平台费用接收地址
    address public MarginReceiver;          // 保证金接收地址
    address public GraduateFeeReceiver;     // 毕业费用接收地址

    // ============ 外部依赖地址 ============
    address public Router;  // PancakeSwap V2 Router 地址
    address public WBNB;    // WBNB（Wrapped BNB）合约地址

    // ============ 配置参数 ============
    uint256 public MinLockTime;  // 最小锁仓时间（秒）

    // ============ 错误定义 ============
    error AddressDoesNotExist(string);  // 必需地址不存在时抛出

    /**
     * @notice 构造函数
     * @param _path 配置文件路径
     * @dev 读取 JSON 配置文件并初始化所有配置项
     */
    constructor(string memory _path) {
        console.log("DeployConfig: reading file %s", _path);
        try vm.readFile(_path) returns (string memory data) {
            _json = data;
        } catch {
            console.log(
                "Warning: unable to read config. Do not deploy unless you are not using config."
            );
            return;
        }

        _initConfig();
    }

    /**
     * @notice 初始化所有配置项
     * @dev 从 JSON 读取各项配置，必需项使用 mustGetAddress，可选项使用 getAddress
     */
    function _initConfig() internal {
        // 必需地址（缺失会导致 revert）
        Admin = mustGetAddress("Admin");
        Signer = mustGetAddress("Signer");
        PlatformFeeReceiver = mustGetAddress("PlatformFeeReceiver");
        MarginReceiver = mustGetAddress("MarginReceiver");
        GraduateFeeReceiver = mustGetAddress("GraduateFeeReceiver");

        // 外部依赖地址
        Router = getAddress("Router");
        WBNB = getAddress("WBNB");

        // 配置参数
        MinLockTime = stdJson.readUint(_json, "$.MinLockTime");

        // 可选地址（已部署合约地址，为 0 表示需要新部署）
        MEMEHelper = getAddress("MEMEHelper");
        MEMEFactory = getAddress("MEMEFactory");
        MEMECore = getAddress("MEMECore");
        MEMEVesting = getAddress("MEMEVesting");
    }

    /**
     * @notice 获取必需地址
     * @param name_ 配置项名称
     * @return 地址值
     * @dev 如果地址不存在或为零地址，会 revert
     */
    function mustGetAddress(string memory name_) public view returns (address) {
        address addr = getAddress(name_);
        if (addr == address(0)) {
            revert AddressDoesNotExist(name_);
        }
        return addr;
    }

    /**
     * @notice 获取可选地址
     * @param name_ 配置项名称
     * @return 地址值，不存在时返回 address(0)
     * @dev 用于读取可选配置，不存在时不会 revert
     */
    function getAddress(string memory name_) public view returns (address) {
        bytes memory addr = stdJson.parseRaw(_json, string.concat("$.", name_));
        address newAddr;
        if (addr.length == 0) {
            newAddr = address(0);
        } else {
            newAddr = abi.decode(addr, (address));
            if (isZeroAddress(newAddr)) {
                newAddr = address(0);
            }
        }
        return newAddr;
    }

    /**
     * @notice 检查是否为零地址
     * @param addr_ 待检查的地址
     * @return 是否为零地址
     * @dev 兼容 JSON 解析可能产生的特殊零地址值
     */
    function isZeroAddress(address addr_) public pure returns (bool) {
        return
            addr_ == address(32) || addr_ == address(0) || addr_ == address(64);
    }
}
