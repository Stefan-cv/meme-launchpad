// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Deployer
 * @author tynes（原作者）
 * @notice 部署器基础合约
 * @dev 提供部署和部署记录管理功能
 *
 * 功能特性：
 * - 自动将部署地址保存到 JSON 文件
 * - 支持按环境（dev/test/pre/prod）管理部署记录
 * - 支持按网络（chainId）隔离部署
 * - 防止重复部署同名合约
 *
 * 使用方法：
 * 1. 继承 Deployer 合约
 * 2. 在 setUp() 中设置 projectName 和 environment
 * 3. 部署后调用 save(name, address) 保存部署记录
 * 4. 使用 getAddress(name) 获取已部署合约地址
 *
 * 部署记录存储路径：
 * deployments/{chainAlias}/{environment}.json
 *
 * Fork from `forge-deploy`
 */

import {Script} from "forge-std/Script.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Chains} from "./Chains.sol";

/// @notice 部署记录结构体
/// @param name 合约名称
/// @param addr 合约地址
struct Deployment {
    string name;
    address payable addr;
}

abstract contract Deployer is Script {
    // ============ 部署记录存储 ============
    
    /// @notice 按名称索引的部署记录映射
    mapping(string => Deployment) internal _namedDeployments;
    
    /// @notice 本次执行的所有新部署记录数组
    Deployment[] internal _newDeployments;
    
    // ============ 路径配置 ============
    
    /// @notice 部署上下文（网络别名），可通过 DEPLOYMENT_CONTEXT 环境变量设置
    string internal deploymentContext;
    
    /// @notice 项目名称前缀（如 "bnb/"、"xlayer_test/"）
    string internal projectName;
    
    /// @notice 环境名称（dev/test/pre/prod）
    string internal environment;
    
    /// @notice forge 生成的部署产物路径
    string internal deployPath;
    
    /// @notice 部署记录目录路径
    string internal deploymentsDir;
    
    /// @notice 部署脚本名称，可通过 DEPLOY_SCRIPT 环境变量设置
    string internal deployScript;
    
    /// @notice 临时部署记录文件路径
    string internal tempDeploymentsPath;

    /// @notice 链信息管理合约
    Chains chainContract;

    // ============ 错误定义 ============
    
    /// @notice 请求的部署记录不存在
    error DeploymentDoesNotExist(string);
    
    /// @notice 无效的部署（名称为空或已存在）
    error InvalidDeployment(string);

    // ============ EIP-1967 存储槽 ============
    
    /// @notice 实现合约地址存储槽
    /// @dev bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
    bytes32 internal constant IMPLEMENTATION_KEY =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    /// @notice 代理管理员地址存储槽
    /// @dev bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1)
    bytes32 internal constant OWNER_KEY =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @notice 初始化部署器
     * @dev 设置部署路径、创建目录、初始化部署记录文件
     */
    function setUp() public virtual {
        chainContract = new Chains();
        string memory root = vm.projectRoot();

        // 获取部署上下文（网络别名）
        deploymentContext = _getDeploymentContext(block.chainid);
        uint256 chainId = vm.envOr("CHAIN_ID", block.chainid);

        // 设置部署记录目录
        deploymentsDir = string.concat(
            root,
            "/deployments/",
            deploymentContext
        );

        // 创建部署目录（如果不存在）
        try vm.createDir(deploymentsDir, true) {} catch (bytes memory) {}

        // 验证或创建 chainId 文件（防止网络配置错误）
        string memory chainIdPath = string.concat(deploymentsDir, "/.chainId");
        try vm.readFile(chainIdPath) returns (string memory localChainId) {
            if (vm.envOr("STRICT_DEPLOYMENT", true)) {
                require(
                    vm.parseUint(localChainId) == chainId,
                    "Misconfigured networks"
                );
            }
        } catch {
            vm.writeFile(chainIdPath, vm.toString(chainId));
        }
        console.log("Connected to network with chainid %s", chainId);

        // 设置临时部署记录文件路径
        tempDeploymentsPath = string.concat(
            deploymentsDir,"/",
            environment,
            ".json"
        );
        
        // 初始化部署记录文件（如果不存在）
        try vm.readFile(tempDeploymentsPath) returns (string memory) {} catch {
            vm.writeJson("{}", tempDeploymentsPath);
        }
        console.log("Storing temp deployment data in %s", tempDeploymentsPath);
    }

    // ============ 查询函数 ============

    /**
     * @notice 获取本次执行的所有新部署记录
     * @return 部署记录数组
     */
    function newDeployments() external view returns (Deployment[] memory) {
        return _newDeployments;
    }

    /**
     * @notice 检查指定名称的部署是否存在
     * @param _name 合约名称
     * @return 是否存在
     */
    function has(string memory _name) public view returns (bool) {
        Deployment memory existing = _namedDeployments[_name];
        if (existing.addr != address(0)) {
            return bytes(existing.name).length > 0;
        }
        return _getExistingDeploymentAddress(_name) != address(0);
    }

    /**
     * @notice 获取已部署合约地址
     * @param _name 合约名称
     * @return 合约地址（不存在时返回 address(0)）
     */
    function getAddress(
        string memory _name
    ) public view returns (address payable) {
        Deployment memory existing = _namedDeployments[_name];
        if (existing.addr != address(0)) {
            if (bytes(existing.name).length == 0) {
                return payable(address(0));
            }
            return existing.addr;
        }
        return _getExistingDeploymentAddress(_name);
    }

    /**
     * @notice 获取已部署合约地址（不存在时 revert）
     * @param _name 合约名称
     * @return 合约地址
     */
    function mustGetAddress(
        string memory _name
    ) public view returns (address payable) {
        address addr = getAddress(_name);
        if (addr == address(0)) {
            revert DeploymentDoesNotExist(_name);
        }
        return payable(addr);
    }

    /**
     * @notice 获取部署记录
     * @param _name 合约名称
     * @return 部署记录结构体
     */
    function get(string memory _name) public view returns (Deployment memory) {
        Deployment memory deployment = _namedDeployments[_name];
        if (deployment.addr != address(0)) {
            return deployment;
        } else {
            return _getExistingDeployment(_name);
        }
    }

    // ============ 保存函数 ============

    /**
     * @notice 保存部署记录
     * @param _name 合约名称
     * @param _deployed 合约地址
     * @dev 将部署记录保存到内存和 JSON 文件
     */
    function save(string memory _name, address _deployed) public {
        if (bytes(_name).length == 0) {
            revert InvalidDeployment("EmptyName");
        }
        if (bytes(_namedDeployments[_name].name).length > 0) {
            revert InvalidDeployment("AlreadyExists");
        }

        Deployment memory deployment = Deployment({
            name: _name,
            addr: payable(_deployed)
        });
        _namedDeployments[_name] = deployment;
        _newDeployments.push(deployment);
        _writeTemp(_name, _deployed);
    }

    // ============ 内部函数 ============

    /**
     * @notice 从部署交易中提取合约名称
     * @param _deployTx 部署交易 JSON 字符串
     * @return 合约名称
     */
    function _getContractNameFromDeployTransaction(
        string memory _deployTx
    ) internal pure returns (string memory) {
        return stdJson.readString(_deployTx, ".contractName");
    }

    /**
     * @notice 将部署记录写入 JSON 文件
     * @param _name 合约名称
     * @param _deployed 合约地址
     */
    function _writeTemp(string memory _name, address _deployed) internal {
        if (_getExistingDeploymentAddress(_name) != address(0)) {
            // 更新已存在的记录
            vm.writeJson({
                json: vm.toString(_deployed),
                path: tempDeploymentsPath,
                valueKey: string.concat("$.", _name)
            });
        } else {
            // 添加新记录
            vm.writeJson({
                json: stdJson.serialize("", _name, _deployed),
                path: tempDeploymentsPath
            });
        }
    }

    /**
     * @notice 获取部署上下文（网络别名）
     * @param chainid 链 ID
     * @return 网络别名（如 "bnb"、"bnb_test"）
     */
    function _getDeploymentContext (
        uint256 chainid
    ) internal view returns (string memory) {
        // 优先使用环境变量
        string memory context = vm.envOr("DEPLOYMENT_CONTEXT", string(""));
        if (bytes(context).length > 0) {
            return context;
        }
        // 否则使用链 ID 查找别名
        return chainContract.getChainAlice(chainid);
    }

    /**
     * @notice 从文件读取已部署合约地址
     * @param _name 合约名称
     * @return 合约地址
     */
    function _getExistingDeploymentAddress(
        string memory _name
    ) internal view returns (address payable) {
        return _getExistingDeployment(_name).addr;
    }

    /**
     * @notice 从文件读取部署记录
     * @param _name 合约名称
     * @return 部署记录结构体
     */
    function _getExistingDeployment(
        string memory _name
    ) internal view returns (Deployment memory) {
        string memory path = tempDeploymentsPath;
        try vm.readFile(path) returns (string memory json) {
            bytes memory addr = stdJson.parseRaw(
                json,
                string.concat("$.", _name)
            );
            address payable newAddr;
            if (addr.length == 0) {
                newAddr = payable(address(0));
            } else {
                newAddr = abi.decode(addr, (address));
                if (isZeroAddress(newAddr)) {
                    newAddr = payable(address(0));
                }
            }

            return Deployment({addr: newAddr, name: _name});
        } catch {
            return Deployment({addr: payable(address(0)), name: ""});
        }
    }

    /**
     * @notice 检查是否为零地址
     * @param addr_ 待检查的地址
     * @return 是否为零地址
     */
    function isZeroAddress(address addr_) public pure returns (bool) {
        return
            addr_ == address(32) || addr_ == address(0) || addr_ == address(64);
    }
}
