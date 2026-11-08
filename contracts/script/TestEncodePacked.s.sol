// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MetaNodeCore} from "../src/MEMECore.sol";

/**
 * @title TestEncodePacked
 * @notice 测试 abi.encodePacked 对 uint256 的编码方式
 */
contract TestEncodePacked is Script {
    MetaNodeCore public core = MetaNodeCore(payable(0x69207F321CFDfd30D73D1d9278e4132E15080ec9));

    function run() external {
        bytes memory data = hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000033b2e3c9fd0803ce800000000000000000000000000000000000000000000000295be96e640669720000000000000000000000000000000000000000000000000000000721062eb2eb7a8a0000000000000000000000000000000000000000003785e8b69f65dc0b9a8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005a7157d6fd2ad4a9edc4686758be77ae480bfe6a00000000000000000000000000000000000000000000000000000000695e39b97d9d84abb69009d0921c9f2d98e391878e57103aeec46e175a4c365cfd5f4a36000000000000000000000000000000000000000000000000000000000000004e00000000000000000000000000000000000000000000000000000000000003e800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000000045a4f4f440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000045a4f4f44000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        
        uint256 chainId = core.CHAIN_ID();
        address contractAddr = address(core);
        
        console.log("==============================================");
        console.log("   Test abi.encodePacked Encoding");
        console.log("==============================================");
        console.log("CHAIN_ID:", chainId);
        console.log("Contract Address:", contractAddr);
        console.log("");
        
        // 测试 1: 使用存储的 CHAIN_ID
        bytes memory packed1 = abi.encodePacked(data, chainId, contractAddr);
        bytes32 hash1 = keccak256(packed1);
        console.log("Hash with stored CHAIN_ID:", vm.toString(hash1));
        console.log("Packed length:", packed1.length);
        console.log("");
        
        // 测试 2: 使用 block.chainid
        bytes memory packed2 = abi.encodePacked(data, block.chainid, contractAddr);
        bytes32 hash2 = keccak256(packed2);
        console.log("Hash with block.chainid:", vm.toString(hash2));
        console.log("Packed length:", packed2.length);
        console.log("Match:", hash1 == hash2);
        console.log("");
        
        // 测试 3: 检查 chainId 的编码
        bytes memory chainIdEncoded = abi.encodePacked(chainId);
        console.log("chainId encoded length:", chainIdEncoded.length);
        console.log("chainId encoded hex:", vm.toString(chainIdEncoded));
        console.log("");
        
        // 测试 4: 检查 block.chainid 的编码
        bytes memory blockChainIdEncoded = abi.encodePacked(block.chainid);
        console.log("block.chainid encoded length:", blockChainIdEncoded.length);
        console.log("block.chainid encoded hex:", vm.toString(blockChainIdEncoded));
        console.log("Match:", keccak256(chainIdEncoded) == keccak256(blockChainIdEncoded));
        console.log("");
        
        // 测试 5: 手动构建（模拟后端）
        bytes memory manualPacked = new bytes(data.length + 1 + 20);
        uint256 offset = 0;
        for (uint256 i = 0; i < data.length; i++) {
            manualPacked[offset++] = data[i];
        }
        // chainId = 97，按最小字节编码应该是 0x61 (1 字节)
        manualPacked[offset++] = 0x61;
        // address (20 bytes)
        bytes20 addr = bytes20(contractAddr);
        for (uint256 i = 0; i < 20; i++) {
            manualPacked[offset++] = addr[i];
        }
        bytes32 hash3 = keccak256(manualPacked);
        console.log("Hash with manual packing (1 byte chainId):", vm.toString(hash3));
        console.log("Match with stored CHAIN_ID:", hash1 == hash3);
        console.log("Match with block.chainid:", hash2 == hash3);
        console.log("");
        
        console.log("==============================================");
    }
}

