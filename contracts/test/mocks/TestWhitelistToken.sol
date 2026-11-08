// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TestWhitelistToken is ERC20, Ownable {
    mapping(address => bool) public isWhitelist;
    bool public isWhitelistEnabled = true;

    constructor(
        string memory name,
        string memory symbol,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _mint(msg.sender, initialSupply * 10 ** decimals());
    }

    function setWhitelistEnabled(bool _isWhitelistEnabled) external onlyOwner {
        isWhitelistEnabled = _isWhitelistEnabled;
    }

    function setWhitelist(
        address[] calldata accounts,
        bool isWhitelisted
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            isWhitelist[accounts[i]] = isWhitelisted;
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (isWhitelistEnabled) {
            if (isWhitelist[from] || isWhitelist[to]) {
                super._transfer(from, to, amount);
            } else {
                revert("Forbidden");
            }
        } else {
            super._transfer(from, to, amount);
        }
    }
}
