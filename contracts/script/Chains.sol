// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title Chains
 * @notice 链信息管理合约
 * @dev 维护支持的区块链网络信息，提供链 ID 与别名的映射
 *
 * 支持的网络：
 * 主网：
 * - Ethereum (1), BNB Chain (56), Polygon (137), Avalanche (43114)
 * - Arbitrum (42161), Optimism (10), Base (8453), XLayer (196) 等
 *
 * 测试网：
 * - BSC Testnet (97), Sepolia (11155111), Arbitrum Sepolia (421614)
 * - XLayer Testnet (1952) 等
 *
 * 使用场景：
 * - 部署脚本中根据 chainId 获取网络别名
 * - 生成部署记录文件路径
 */

contract Chains {
    // ============ 状态变量 ============
    
    /// @notice 链信息是否已初始化
    bool private chainsInitialized;

    /// @notice 链信息结构体
    /// @param chainId 链 ID
    /// @param name 链名称（别名）
    struct Chain {
        uint256 chainId;
        string name;
    }

    /// @notice 链名称到链信息的映射
    mapping(string => Chain) public chains;
    
    /// @notice 链 ID 到链名称的映射
    mapping(uint256 => string) private idToAlias;

    /**
     * @notice 构造函数
     * @dev 初始化所有支持的链信息
     */
    constructor() {
        initializeChains();
    }

    /**
     * @notice 初始化链信息
     * @dev 注册所有支持的主网和测试网
     */
    function initializeChains() private {
        if (chainsInitialized) return;

        chainsInitialized = true;
        
        // ===== 主网 =====
        setChain("ethereum", 1);           // 以太坊主网
        setChain("goerli", 5);             // Goerli 测试网（已弃用）
        setChain("bnb", 56);               // BNB Chain 主网
        setChain("opbnb", 204);            // opBNB 主网
        setChain("polygon", 137);          // Polygon 主网
        setChain("polygon_zkevm", 1101);   // Polygon zkEVM 主网
        setChain("avalanche", 43114);      // Avalanche C-Chain
        setChain("fantom", 250);           // Fantom Opera
        setChain("optimism", 10);          // Optimism 主网
        setChain("arb_one", 42161);        // Arbitrum One
        setChain("moonbeam", 1284);        // Moonbeam
        setChain("gnosis", 100);           // Gnosis Chain
        setChain("metis", 1088);           // Metis Andromeda
        setChain("arbitrum_nova", 42170);  // Arbitrum Nova
        setChain("coredao", 1116);         // Core DAO
        setChain("celo", 42220);           // Celo
        setChain("linea", 59144);          // Linea
        setChain("mantle", 5000);          // Mantle
        setChain("base", 8453);            // Base
        setChain("manta", 169);            // Manta Pacific
        setChain("scroll", 534352);        // Scroll
        setChain("combo", 9980);           // Combo
        setChain("dogechain", 2000);       // Dogechain
        setChain("hyper", 999);            // Hyper
        setChain("xlayer", 196);           // XLayer 主网

        // ===== 测试网 =====
        setChain("base_sepolia", 84532);       // Base Sepolia
        setChain("eth_sepolia", 11155111);     // 以太坊 Sepolia
        setChain("eth_holesky", 17000);        // 以太坊 Holesky
        setChain("arb_sepolia", 421614);       // Arbitrum Sepolia
        setChain("mantle_test", 5001);         // Mantle 测试网
        setChain("celo_test", 44787);          // Celo Alfajores
        setChain("coredao_test", 1115);        // Core DAO 测试网
        setChain("scroll_sepolia", 534351);    // Scroll Sepolia
        setChain("optimism_sepolia", 11155420);// Optimism Sepolia
        setChain("polygon_zkevm_test", 1442);  // Polygon zkEVM Cardona
        setChain("polygon_test", 80001);       // Polygon Mumbai
        setChain("opbnb_test", 5611);          // opBNB 测试网
        setChain("bnb_test", 97);              // BSC 测试网
        setChain("bitmap_test", 686868);       // Bitmap 测试网
        setChain("bsquared_test", 1002);       // B² Network 测试网
        setChain("xlayer_test", 1952);         // XLayer 测试网
    }

    /**
     * @notice 注册链信息
     * @param chainName_ 链名称（别名）
     * @param chainId_ 链 ID
     * @dev 内部函数，用于初始化时注册链信息
     */
    function setChain(
        string memory chainName_,
        uint256 chainId_
    ) internal virtual {
        require(
            bytes(chainName_).length != 0,
            "Chains setChain(string,uint256): Chain name cannot be the empty string."
        );
        require(
            chainId_ != 0,
            "StdChains setChain(string,uint256): Chain ID cannot be 0."
        );

        chains[chainName_] = Chain({name: chainName_, chainId: chainId_});
        idToAlias[chainId_] = chainName_;
    }

    /**
     * @notice 根据链 ID 获取链名称
     * @param chainId_ 链 ID
     * @return 链名称（别名）
     */
    function getChainAlice(
        uint256 chainId_
    ) external view returns (string memory) {
        return idToAlias[chainId_];
    }
}
