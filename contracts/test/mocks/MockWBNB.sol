// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockWBNB
 * @dev A mock implementation of Wrapped BNB (WETH9) for testing purposes.
 *      This contract implements the standard ERC-20 interface and the deposit/withdraw functions.
 */
contract MockWBNB is ERC20 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    /**
     * @dev Constructor that initializes the token with the name "Wrapped BNB" and symbol "WBNB".
     */
    constructor() ERC20("Wrapped BNB", "WBNB") {
        // Optionally mint some initial tokens to the deployer for testing
        // _mint(msg.sender, 1000000 * 10**18);
    }

    /**
     * @dev Deposit ETH to mint WBNB. Msg.value is the amount of ETH to deposit.
     *      Mints an equivalent amount of WBNB to the sender.
     */
    function deposit() external payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Withdraw ETH by burning WBNB.
     * @param wad The amount of WBNB to burn and ETH to withdraw.
     */
    function withdraw(uint256 wad) external {
        require(balanceOf(msg.sender) >= wad, "MockWBNB: insufficient balance");
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    /**
     * @dev Get the contract's ETH balance.
     */
    function getEthBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Allow the contract to receive ETH without calling deposit().
     *      This is useful for testing scenarios where ETH is sent directly.
     */
    receive() external payable {
        // Optionally auto-wrap if sent directly?
        // _mint(msg.sender, msg.value);
        // emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Fallback function to receive ETH.
     */
    fallback() external payable {
        // Optionally auto-wrap if sent directly?
        // _mint(msg.sender, msg.value);
        // emit Deposit(msg.sender, msg.value);
    }

    /**
     * @dev Mint tokens arbitrarily for testing setups (e.g., giving users initial WBNB balance).
     *      This function is NOT part of the standard WETH9 interface and is for testing only.
     * @param to The address to mint tokens to.
     * @param amount The amount of tokens to mint.
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens arbitrarily for testing.
     *      This function is NOT part of the standard WETH9 interface and is for testing only.
     * @param from The address to burn tokens from.
     * @param amount The amount of tokens to burn.
     */
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}