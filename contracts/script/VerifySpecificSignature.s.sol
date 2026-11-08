// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import {MetaNodeCore} from "../src/MEMECore.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title VerifySpecificSignature
 * @notice 验证前端提供的具体签名
 */
contract VerifySpecificSignature is Script {
    using ECDSA for bytes32;
    
    MetaNodeCore public core = MetaNodeCore(payable(0x69207F321CFDfd30D73D1d9278e4132E15080ec9));
    address public expectedSigner = 0x5A7157d6Fd2aD4A9Edc4686758bE77aE480bfe6A;

    function run() external {
        // 前端提供的实际数据
        bytes memory createArg = hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000033b2e3c9fd0803ce800000000000000000000000000000000000000000000000295be96e640669720000000000000000000000000000000000000000000000000000000721062eb2eb7a8a0000000000000000000000000000000000000000003785e8b69f65dc0b9a8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005a7157d6fd2ad4a9edc4686758be77ae480bfe6a00000000000000000000000000000000000000000000000000000000695e39b97d9d84abb69009d0921c9f2d98e391878e57103aeec46e175a4c365cfd5f4a36000000000000000000000000000000000000000000000000000000000000004e00000000000000000000000000000000000000000000000000000000000003e800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000000045a4f4f440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000045a4f4f44000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        bytes memory signature = hex"733be12b8f7185ba14a5923d339ccd701028e1592870139a167e0cac8a7961bb4ac9baa7eeb5fba6d5a4acd4c031fcd49a05676263b3d0d50629620f0201e1fd1c";
        
        console.log("==============================================");
        console.log("   Verify Specific Signature");
        console.log("==============================================");
        console.log("Core Contract:", address(core));
        console.log("Expected Signer:", expectedSigner);
        console.log("");
        
        // 检查签名格式
        console.log("Signature length:", signature.length);
        if (signature.length == 65) {
            uint8 v = uint8(signature[64]);
            console.log("Signature v value:", v);
            console.log("v is 27/28:", v == 27 || v == 28);
            
            bytes32 r;
            bytes32 s;
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
            }
            console.log("R:", vm.toString(r));
            console.log("S:", vm.toString(s));
        }
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
        
        bool expectedHasRole = core.hasRole(core.SIGNER_ROLE(), expectedSigner);
        console.log("Expected Signer has SIGNER_ROLE:", expectedHasRole);
        
        console.log("");
        console.log("==============================================");
        
        // 尝试手动计算消息哈希，看看后端是如何计算的
        console.log("");
        console.log("Debug: Manual hash calculation");
        bytes memory packed = abi.encodePacked(createArg, core.CHAIN_ID(), address(core));
        bytes32 manualHash = keccak256(packed);
        console.log("Manual Hash:", vm.toString(manualHash));
        console.log("Match with contract:", manualHash == messageHash);
    }
}

