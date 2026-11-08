// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MetaNodeCore} from "../src/MEMECore.sol";
import {IMEMECore} from "../src/interfaces/IMEMECore.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title VerifySignature
 * @notice 验证后端返回的签名
 */
contract VerifySignature is Script {
    using ECDSA for bytes32;
    
    MetaNodeCore public core = MetaNodeCore(payable(0x69207F321CFDfd30D73D1d9278e4132E15080ec9));
    address public expectedSigner = 0x5A7157d6Fd2aD4A9Edc4686758bE77aE480bfe6A;

    function run() external {
        // 从用户提供的 API 响应中提取数据
        bytes memory createArg = hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000033b2e3c9fd0803ce800000000000000000000000000000000000000000000000295be96e640669720000000000000000000000000000000000000000000000000000000721062eb2eb7a8a0000000000000000000000000000000000000000003785e8b69f65dc0b9a8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005a7157d6fd2ad4a9edc4686758be77ae480bfe6a00000000000000000000000000000000000000000000000000000000695e37eb0fd25ee165689f952c391b506ddcb08aa3240fe2e3f479dade27bf6345c7bc6a000000000000000000000000000000000000000000000000000000000000004c00000000000000000000000000000000000000000000000000000000000003e800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000000045a4f4f440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000045a4f4f44000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory signature = hex"17099d8b2e2985e6af021297d1834258e4ecc2719ae0fe9251a6c9ba99e42b0f0b5bd22ad23bb7851c1836fe872279110fd5da644af02f9b52d0b285e30ca3e500";
        
        console.log("==============================================");
        console.log("   Verify Signature");
        console.log("==============================================");
        console.log("Core Contract:", address(core));
        console.log("Expected Signer:", expectedSigner);
        console.log("");
        
        // 计算消息哈希（与合约中一致）
        bytes32 messageHash = keccak256(abi.encodePacked(createArg, core.CHAIN_ID(), address(core)));
        console.log("Message Hash:", vm.toString(messageHash));
        console.log("CHAIN_ID:", core.CHAIN_ID());
        console.log("Contract Address:", address(core));
        console.log("");
        
        // 恢复签名者地址
        address recoveredSigner = messageHash.recover(signature);
        console.log("Recovered Signer:", recoveredSigner);
        console.log("Expected Signer:", expectedSigner);
        console.log("Match:", recoveredSigner == expectedSigner);
        console.log("");
        
        // 检查权限
        bool hasRole = core.hasRole(core.SIGNER_ROLE(), recoveredSigner);
        console.log("Recovered Signer has SIGNER_ROLE:", hasRole);
        
        // 检查签名格式
        console.log("Signature length:", signature.length);
        if (signature.length == 65) {
            uint8 v = uint8(signature[64]);
            console.log("Signature v value:", v);
            console.log("v is 27/28:", v == 27 || v == 28);
        }
        
        console.log("");
        console.log("==============================================");
    }
}

