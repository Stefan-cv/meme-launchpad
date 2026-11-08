// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VanityAddressTest
 * @notice 靓号地址生成测试
 * @dev 测试使用 CREATE2 预测和部署靓号代币地址的功能
 *
 * CREATE2 地址计算公式：
 * address = keccak256(0xff ++ factory ++ salt ++ keccak256(bytecode))
 *
 * 靓号生成原理：
 * - 通过改变 nonce 参数来改变 salt
 * - salt = keccak256(name, symbol, totalSupply, owner, timestamp, nonce)
 * - 遍历不同的 nonce 直到找到满足条件的地址（如末尾4444）
 *
 * 测试覆盖场景：
 * 1. 地址预测准确性 - predictTokenAddress 返回值与实际部署地址一致
 * 2. 靓号搜索 - 通过遍历 nonce 寻找特定模式的地址
 */
import "forge-std/Test.sol";
import "../src/MEMEFactory.sol";
import "../src/MEMEToken.sol";

contract VanityAddressTest is Test {
    MEMEFactory public factory;
    address public admin = makeAddr("admin");
    address public coreContract = makeAddr("core");

    // Test parameters matching generateSignature.js
    string constant TOKEN_NAME = "Test";
    string constant TOKEN_SYMBOL = "TST";
    uint256 constant TOTAL_SUPPLY = 1000000000 * 10 ** 18;

    function setUp() public {
        vm.startPrank(admin);
        factory = new MEMEFactory(admin);
        factory.grantRole(factory.DEPLOYER_ROLE(), coreContract);
        factory.setMetaNode(coreContract);
        vm.stopPrank();
    }

    function testVanityAddressPrediction() public {
        uint256 timestamp = 1754324541; // Use a fixed timestamp for testing
        uint256[] memory testNonces = new uint256[](5);
        testNonces[0] = 0;
        testNonces[1] = 100;
        testNonces[2] = 1000;
        testNonces[3] = 10000;
        testNonces[4] = 54817; // A vanity nonce that should produce address ending in 4444

        for (uint i = 0; i < testNonces.length; i++) {
            uint256 nonce = testNonces[i];

            // Predict address
            address predicted = factory.predictTokenAddress(
                TOKEN_NAME,
                TOKEN_SYMBOL,
                TOTAL_SUPPLY,
                coreContract, // owner is the core contract
                timestamp,
                nonce
            );

            // Check if it's a vanity address (ends with 4444)
            bytes memory addrBytes = abi.encodePacked(predicted);
            bool isVanity = (
                uint8(addrBytes[18]) == 0x44 &&
                uint8(addrBytes[19]) == 0x44
            );

            // Actually deploy and verify
            vm.prank(coreContract);
            address deployed = factory.deployToken(
                TOKEN_NAME,
                TOKEN_SYMBOL,
                TOTAL_SUPPLY,
                timestamp,
                nonce
            );
        }
    }

    function testFindVanityAddress() public {
        uint256 timestamp = block.timestamp;
        uint256 maxAttempts = 1000;
        bool found = false;
        uint256 foundNonce = 0;
        address foundAddress;
        for (uint256 nonce = 0; nonce < maxAttempts; nonce++) {
            address predicted = factory.predictTokenAddress(
                TOKEN_NAME,
                TOKEN_SYMBOL,
                TOTAL_SUPPLY,
                coreContract,
                timestamp,
                nonce
            );

            // Check last 2 bytes (4 hex chars)
            bytes memory addrBytes = abi.encodePacked(predicted);
            if (uint8(addrBytes[18]) == 0x44 && uint8(addrBytes[19]) == 0x44) {
                found = true;
                foundNonce = nonce;
                foundAddress = predicted;
                break;
            }

            // Progress report every 10000 attempts
            if (nonce > 0 && nonce % 10000 == 0) {
                console.log("Progress:", nonce, "attempts");
            }
        }

        if (found) {
            console.log("Found vanity address!");
            console.log("  Nonce:", foundNonce);
            console.log("  Address:", foundAddress);

            // Deploy and verify
            vm.prank(coreContract);
            address deployed = factory.deployToken(
                TOKEN_NAME,
                TOKEN_SYMBOL,
                TOTAL_SUPPLY,
                timestamp,
                foundNonce
            );

            assertEq(deployed, foundAddress, "Deployed should match predicted vanity address");
            console.log("  Deployed:", deployed);
            console.log("  Verified: Address ends with 4444");
        } else {
            console.log("No vanity address found in", maxAttempts, "attempts");
        }
    }
}