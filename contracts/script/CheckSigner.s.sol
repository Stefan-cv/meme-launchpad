// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MetaNodeCore} from "../src/MEMECore.sol";

/**
 * @title CheckSigner
 * @notice 检查签名者权限和合约配置
 */
contract CheckSigner is Script {
    // 合约地址 (BSC Testnet)
    MetaNodeCore public core = MetaNodeCore(payable(0x69207F321CFDfd30D73D1d9278e4132E15080ec9));
    
    // 签名者地址
    address public signer = 0x5A7157d6Fd2aD4A9Edc4686758bE77aE480bfe6A;

    function run() external {
        console.log("==============================================");
        console.log("   Check Signer Configuration");
        console.log("==============================================");
        console.log("Core Contract:", address(core));
        console.log("Signer Address:", signer);
        console.log("");
        
        // 检查权限
        bool hasSignerRole = core.hasRole(core.SIGNER_ROLE(), signer);
        console.log("Has SIGNER_ROLE:", hasSignerRole);
        
        // 检查 CHAIN_ID
        uint256 chainId = core.CHAIN_ID();
        console.log("Contract CHAIN_ID:", chainId);
        console.log("Block chainid:", block.chainid);
        console.log("Match:", chainId == block.chainid);
        
        // 检查合约地址
        console.log("Contract address(this):", address(core));
        
        console.log("");
        console.log("==============================================");
    }
}

