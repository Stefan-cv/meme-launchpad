// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMEMEFactory
 * @notice 代币工厂接口
 * 
 * ============ 工厂模式说明 ============
 * 工厂合约负责部署新的 ERC20 代币合约。
 * 使用 CREATE2 确保：
 * 1. 相同参数 → 相同地址（可预测）
 * 2. 防止地址冲突（参数组合唯一）
 * 
 * ============ 调用链路 ============
 * 用户 → MEMECore.createToken() → MEMEFactory.deployToken() → new MetaNodeToken()
 * 
 * 只有 MEMECore（DEPLOYER_ROLE）可以调用 deployToken
 */
interface IMEMEFactory {
    /// @notice 未授权的部署者
    error UnauthorizedDeployer();

    /// @notice 代币部署事件
    event TokenDeployed(
        address indexed token,      // 新代币合约地址
        string name,                // 代币名称
        string symbol,              // 代币符号
        uint256 totalSupply,        // 总供应量
        address indexed deployer    // 部署者（MEMECore）
    );

    /**
     * @notice 部署新代币合约
     * @dev 仅限 DEPLOYER_ROLE 调用
     * @param name 代币名称
     * @param symbol 代币符号
     * @param totalSupply 总供应量（含18位小数）
     * @param timestamp 时间戳（用于盐值计算）
     * @param nonce 随机数（用于盐值计算）
     * @return 新部署的代币地址
     * 
     * 盐值计算：keccak256(name, symbol, totalSupply, metaNode, timestamp, nonce)
     * 代币接收方：metaNode（MEMECore 合约地址）
     */
    function deployToken(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        uint256 timestamp,  
        uint256 nonce
    ) external returns (address);

    /**
     * @notice 预测代币部署地址
     * @dev 不消耗 gas，可在前端使用
     * @param name 代币名称
     * @param symbol 代币符号
     * @param totalSupply 总供应量
     * @param owner 代币接收者
     * @param timestamp 时间戳
     * @param nonce 随机数
     * @return 预测的合约地址
     * 
     * 使用 CREATE2 公式：
     * address = keccak256(0xff, factory, salt, keccak256(bytecode))
     */
    function predictTokenAddress(
        string memory name,
        string memory symbol,
        uint256 totalSupply,
        address owner,
        uint256 timestamp,
        uint256 nonce
    ) external view returns (address);
}
