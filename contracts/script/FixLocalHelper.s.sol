// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FixLocalHelper
 * @notice 本地 anvil 环境修复脚本：
 *         MEMEHelper 在构造时写死 PancakeSwap Router 地址（BSC 测试网），
 *         anvil 上没有该合约导致 createToken 在 getPairAddress 处 revert。
 *         本脚本部署最小 Mock Pancake Router/Factory（getPair 返回 0 地址），
 *         再部署新 Helper 并让 Core 切换到它。
 */

import "forge-std/Script.sol";
import {MetaNodeCore} from "../src/MEMECore.sol";
import {MEMEHelper} from "../src/MEMEHelper.sol";

/// @dev 最小 PancakeFactory mock：getPair 永远返回 0 地址（本地不毕业、不加池）
contract MockPancakeFactory {
    function getPair(address, address) external pure returns (address) {
        return address(0);
    }
}

/// @dev 最小 PancakeRouter02 mock：仅实现 factory()
contract MockPancakeRouter {
    address public immutable factory;

    constructor(address _factory) {
        factory = _factory;
    }
}

contract FixLocalHelper is Script {
    address constant CORE = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
    address constant WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.addr(pk);

        vm.startBroadcast(pk);

        MockPancakeFactory mockFactory = new MockPancakeFactory();
        MockPancakeRouter mockRouter = new MockPancakeRouter(address(mockFactory));
        MEMEHelper helper = new MEMEHelper(admin, address(mockRouter), WBNB);
        MetaNodeCore core = MetaNodeCore(payable(CORE));

        helper.grantRole(helper.CORE_ROLE(), CORE);
        core.setHelper(address(helper));

        vm.stopBroadcast();

        console.log("MockFactory:", address(mockFactory));
        console.log("MockRouter:", address(mockRouter));
        console.log("NewHelper: ", address(helper));
    }
}
