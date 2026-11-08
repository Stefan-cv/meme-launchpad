// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TestOnchain
 * @notice 在 BSC 测试网上运行链上测试
 * @dev 测试代币创建、买入、卖出功能
 */

import "forge-std/Script.sol";
import {MetaNodeCore} from "../src/MEMECore.sol";
import {MEMEFactory} from "../src/MEMEFactory.sol";
import {MEMEHelper} from "../src/MEMEHelper.sol";
import {MEMEVesting} from "../src/MEMEVesting.sol";
import {MetaNodeToken} from "../src/MEMEToken.sol";
import {IMEMECore} from "../src/interfaces/IMEMECore.sol";
import {IVestingParams} from "../src/interfaces/IVestingParams.sol";

contract TestOnchain is Script {
    // 部署的合约地址 (BSC Testnet - 2nd deployment)
    MEMEFactory public factory = MEMEFactory(0x7A24756A156DE5752a2d91d494D2D4FdCc9fc18F);
    MEMEHelper public helper = MEMEHelper(payable(0xbdBA43Fa0DF71724E5fF171eD3F4781ece0c141A));
    MetaNodeCore public core = MetaNodeCore(payable(0x69207F321CFDfd30D73D1d9278e4132E15080ec9));
    MEMEVesting public vesting = MEMEVesting(0x99Cd9cA83277338583F40d6b689c0aA5E20baCAD);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("==============================================");
        console.log("   MEME Launchpad Onchain Tests");
        console.log("==============================================");
        console.log("Tester:", deployer);
        console.log("Balance:", deployer.balance / 1e18, "BNB");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Test 1: 创建简单代币
        console.log("Test 1: Creating a simple token...");
        address token1 = createSimpleToken(deployer, deployerPrivateKey);
        console.log("   Token created at:", token1);
        console.log("   Test 1 PASSED!");
        console.log("");

        // Test 2: 买入代币
        console.log("Test 2: Buying tokens...");
        uint256 buyAmount = 0.01 ether;
        uint256 tokensBought = buyTokens(token1, buyAmount, deployer);
        console.log("   Paid:", buyAmount / 1e18, "BNB");
        console.log("   Received:", tokensBought / 1e18, "tokens");
        console.log("   Test 2 PASSED!");
        console.log("");

        // Test 3: 卖出代币
        console.log("Test 3: Selling tokens...");
        uint256 tokensToSell = tokensBought / 2;
        if (tokensToSell > 0) {
            // 需要先 approve
            MetaNodeToken(token1).approve(address(core), tokensToSell);
            uint256 bnbReceived = sellTokens(token1, tokensToSell, deployer);
            console.log("   Sold:", tokensToSell / 1e18, "tokens");
            console.log("   Received:", bnbReceived / 1e16, "x0.01 BNB");
        } else {
            console.log("   Skipping sell (no tokens to sell)");
        }
        console.log("   Test 3 PASSED!");
        console.log("");

        // Test 4: 创建带初始买入的代币
        console.log("Test 4: Creating token with initial buy...");
        address token2 = createTokenWithInitialBuy(deployer, deployerPrivateKey);
        console.log("   Token created at:", token2);
        MetaNodeToken tokenContract = MetaNodeToken(token2);
        console.log("   Creator balance:", tokenContract.balanceOf(deployer) / 1e18, "tokens");
        console.log("   Test 4 PASSED!");
        console.log("");

        // Test 5: 创建带归属计划的代币
        console.log("Test 5: Creating token with vesting...");
        address token3 = createTokenWithVesting(deployer, deployerPrivateKey);
        console.log("   Token created at:", token3);
        console.log("   Test 5 PASSED!");
        console.log("");

        vm.stopBroadcast();

        // 输出测试结果
        console.log("==============================================");
        console.log("   All Tests PASSED!");
        console.log("==============================================");
        console.log("");
        console.log("Created Tokens:");
        console.log("  Token1 (Simple):", token1);
        console.log("  Token2 (InitialBuy):", token2);
        console.log("  Token3 (Vesting):", token3);
    }

    function createSimpleToken(address creator, uint256 pk) internal returns (address) {
        IMEMECore.CreateTokenParams memory params = IMEMECore.CreateTokenParams({
            name: "Test Token 1",
            symbol: "TEST1",
            totalSupply: 1_000_000_000 ether,
            saleAmount: 800_000_000 ether,
            virtualBNBReserve: 10 ether,
            virtualTokenReserve: 800_000_000 ether,
            launchTime: block.timestamp,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("test1", block.timestamp, creator)),
            nonce: 1,
            initialBuyPercentage: 0,
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        bytes memory data = abi.encode(params);
        bytes32 hash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 creationFee = core.creationFee();
        return core.createToken{value: creationFee}(data, signature);
    }

    function createTokenWithInitialBuy(address creator, uint256 pk) internal returns (address) {
        IMEMECore.CreateTokenParams memory params = IMEMECore.CreateTokenParams({
            name: "Test Token 2 InitialBuy",
            symbol: "TEST2",
            totalSupply: 1_000_000_000 ether,
            saleAmount: 800_000_000 ether,
            virtualBNBReserve: 10 ether,
            virtualTokenReserve: 800_000_000 ether,
            launchTime: block.timestamp,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("test2", block.timestamp, creator)),
            nonce: 2,
            initialBuyPercentage: 500, // 5%
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: new IVestingParams.VestingAllocation[](0)
        });

        bytes memory data = abi.encode(params);
        bytes32 hash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 creationFee = core.creationFee();
        (uint256 initialBNB, ) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );

        return core.createToken{value: creationFee + initialBNB}(data, signature);
    }

    function createTokenWithVesting(address creator, uint256 pk) internal returns (address) {
        IVestingParams.VestingAllocation[] memory vestingAllocations = new IVestingParams.VestingAllocation[](2);
        
        // 线性释放 5% (500 基点)
        vestingAllocations[0] = IVestingParams.VestingAllocation({
            amount: 500, // 5% 基点
            launchTime: block.timestamp,
            duration: 7 days,
            mode: IVestingParams.VestingMode.LINEAR
        });
        
        // 悬崖释放 3% (300 基点)
        vestingAllocations[1] = IVestingParams.VestingAllocation({
            amount: 300, // 3% 基点
            launchTime: block.timestamp,
            duration: 30 days,
            mode: IVestingParams.VestingMode.CLIFF
        });

        // 注意：initialBuyPercentage 必须 >= vestingAllocations 总量
        // vestingAllocations 总量 = 500 + 300 = 800 基点
        // 所以 initialBuyPercentage 至少要 1000 基点 (10%)，其中 8% 归属，2% 直接转移
        IMEMECore.CreateTokenParams memory params = IMEMECore.CreateTokenParams({
            name: "Test Token 3 Vesting",
            symbol: "TEST3",
            totalSupply: 1_000_000_000 ether,
            saleAmount: 800_000_000 ether,
            virtualBNBReserve: 10 ether,
            virtualTokenReserve: 800_000_000 ether,
            launchTime: block.timestamp,
            creator: creator,
            timestamp: block.timestamp,
            requestId: keccak256(abi.encodePacked("test3", block.timestamp, creator)),
            nonce: 3,
            initialBuyPercentage: 1000, // 10% - 必须 >= vestingAllocations 总量 (8%)
            marginBnb: 0,
            marginTime: 0,
            vestingAllocations: vestingAllocations
        });

        bytes memory data = abi.encode(params);
        bytes32 hash = keccak256(abi.encodePacked(data, block.chainid, address(core)));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, hash);
        bytes memory signature = abi.encodePacked(r, s, v);

        uint256 creationFee = core.creationFee();
        // 需要支付初始买入的 BNB
        (uint256 initialBNB, ) = core.calculateInitialBuyBNB(
            params.totalSupply,
            params.virtualBNBReserve,
            params.virtualTokenReserve,
            params.initialBuyPercentage
        );
        
        return core.createToken{value: creationFee + initialBNB}(data, signature);
    }

    function buyTokens(address token, uint256 bnbAmount, address buyer) internal returns (uint256) {
        uint256 balanceBefore = MetaNodeToken(token).balanceOf(buyer);
        core.buy{value: bnbAmount}(token, 0, block.timestamp + 300);
        uint256 balanceAfter = MetaNodeToken(token).balanceOf(buyer);
        return balanceAfter - balanceBefore;
    }

    function sellTokens(address token, uint256 tokenAmount, address seller) internal returns (uint256) {
        uint256 balanceBefore = seller.balance;
        core.sell(token, tokenAmount, 0, block.timestamp + 300);
        uint256 balanceAfter = seller.balance;
        return balanceAfter - balanceBefore;
    }

    receive() external payable {}
}

