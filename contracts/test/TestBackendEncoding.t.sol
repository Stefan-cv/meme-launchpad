// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IMEMECore} from "../src/interfaces/IMEMECore.sol";
import {IVestingParams} from "../src/interfaces/IVestingParams.sol";

contract TestBackendEncoding is Test {
    function testDecodeBackendEncoding() public {
        // 从后端日志中提取的编码数据（第 33 行的完整 hex）
        bytes memory encodedData = hex"000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000033b2e3c9fd0803ce800000000000000000000000000000000000000000000000295be96e640669720000000000000000000000000000000000000000000000000000000721062eb2eb7a8a0000000000000000000000000000000000000000003785e8b69f65dc0b9a8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000005a7157d6fd2ad4a9edc4686758be77ae480bfe6a00000000000000000000000000000000000000000000000000000000695d4abd6384731b56c949788ed29cd08984611706ef70e1fa9f229ee77568eee31e90ac000000000000000000000000000000000000000000000000000000000000003f00000000000000000000000000000000000000000000000000000000000003e800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000026000000000000000000000000000000000000000000000000000000000000000045a4f4f440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000045a4f4f44000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        console.log("=== Testing Backend Encoding Decode ===");
        console.log("Encoded data length:", encodedData.length, "bytes");

        // 尝试解码
        try this.decodeParams(encodedData) returns (IMEMECore.CreateTokenParams memory params) {
            console.log("\n[SUCCESS] Decode successful!");
            console.log("Name:", params.name);
            console.log("Symbol:", params.symbol);
            console.log("TotalSupply:", params.totalSupply);
            console.log("SaleAmount:", params.saleAmount);
            console.log("Creator:", params.creator);
            console.log("Nonce:", params.nonce);
            console.log("InitialBuyPercentage:", params.initialBuyPercentage);
            console.log("VestingAllocations length:", params.vestingAllocations.length);
        } catch Error(string memory reason) {
            console.log("\n[ERROR] Decode failed (Error):", reason);
            fail(reason);
        } catch (bytes memory lowLevelData) {
            console.log("\n[ERROR] Decode failed (Low-level error)");
            console.log("Error data length:", lowLevelData.length);
            
            // 尝试解析错误选择器
            if (lowLevelData.length >= 4) {
                bytes4 errorSelector = bytes4(lowLevelData);
                console.log("Error selector:");
                console.logBytes4(errorSelector);
            }
            
            // 打印前 32 字节
            if (lowLevelData.length >= 32) {
                bytes32 firstBytes = bytes32(lowLevelData);
                console.log("First 32 bytes:");
                console.logBytes32(firstBytes);
            }
            
            fail("Decode failed with low-level error");
        }
    }

    function decodeParams(bytes memory data) external pure returns (IMEMECore.CreateTokenParams memory) {
        return abi.decode(data, (IMEMECore.CreateTokenParams));
    }
}

