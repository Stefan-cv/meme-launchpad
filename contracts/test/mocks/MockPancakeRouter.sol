// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPancakePair} from "./IPancakePair.sol";
import {MockWBNB} from "./MockWBNB.sol";

/**
 * @title MockPancakeRouter
 * @dev A mock implementation of the PancakeSwap Router for testing purposes.
 *      Allows setting desired return values and tracking function calls.
 */
contract MockPancakeRouter {
    // Public state variables to track the last call arguments
    address public lastToken;
    uint256 public lastAmountTokenDesired;
    uint256 public lastAmountTokenMin;
    uint256 public lastAmountETHMin;
    address public lastTo;
    uint256 public lastDeadline;

    // Public state variables to set the return values for addLiquidityETH
    uint256 public mockAmountToken;
    uint256 public mockAmountETH;
    uint256 public mockLiquidity;

    // Public variable to simulate a failed call (optional)
    bool public shouldRevert;

    // The WETH address this router expects
    address public immutable WETH;
    address public  factory;

    event LiquidityAdded(
        address indexed token,
        uint256 amountTokenDesired,
        uint256 amountETHDesired,
        address to
    );

    constructor(address _weth) {
        factory = address(new MockPancakeFactory());
        WETH = _weth;
        // Set some sensible default return values
        mockAmountToken = 1000e18;
        mockAmountETH = 1e18;
        mockLiquidity = 500e18;
        shouldRevert = false;
    }

    /**
     * @dev Set the desired return values for the next addLiquidityETH call.
     */
    function setAddLiquidityETHReturnValues(
        uint256 _amountToken,
        uint256 _amountETH,
        uint256 _liquidity
    ) external {
        mockAmountToken = _amountToken;
        mockAmountETH = _amountETH;
        mockLiquidity = _liquidity;
    }

    /**
     * @dev Toggle whether the next call should revert.
     */
    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    /**
     * @dev Mock implementation of addLiquidityETH.
     *      Transfers the tokens from the caller, records the parameters,
     *      and returns the preset values.
     */
    /**
     * @dev Mock implementation of addLiquidityETH.
     *      Matches IPancakeRouter02 interface (no `to` param, uses optOutUserShare).
     */
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        uint256 deadline,
        bool optOutUserShare
    )
    external
    payable
    returns (
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    )
    {
        // Check if we should revert this call
        require(!shouldRevert, "MockPancakeRouter: Forced revert");
        require(deadline >= block.timestamp, "MockPancakeRouter: Expired");
        require(msg.value > 0, "MockPancakeRouter: No ETH sent");

        // Record the call parameters
        lastToken = token;
        lastAmountTokenDesired = amountTokenDesired;
        lastAmountTokenMin = amountTokenMin;
        lastAmountETHMin = amountETHMin;
        lastTo = msg.sender;
        lastDeadline = deadline;

        // Emit an event for off-chain testing to see the call
        emit LiquidityAdded(token, amountTokenDesired, msg.value, msg.sender);

        // Return the preset values
        return (mockAmountToken, mockAmountETH, mockLiquidity);
    }

    /**
     * @dev Getter function to check all last call parameters at once.
     */
    function getLastAddLiquidityETHCall()
    external
    view
    returns (
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
    {
        return (
            lastToken,
            lastAmountTokenDesired,
            lastAmountTokenMin,
            lastAmountETHMin,
            lastTo,
            lastDeadline
        );
    }

    /**
     * @dev Allow the contract to receive ETH.
     */
    receive() external payable {}
}

contract MockPancakeFactory {
    // Public state variables to track calls
    address public lastTokenA;
    address public lastTokenB;

    // Mapping to simulate pair existence
    // key: keccak256(abi.encodePacked(token0, token1)) -> pair address
    mapping(bytes32 => address) public pairs;

    // Mapping to store created pairs in order
    address[] public allPairs;

    // Control whether createPair should succeed or revert
    bool public shouldRevertOnCreate;

    // Control what getPair returns (can be set arbitrarily)
    address public pairToReturn;

    // Events to match the real factory
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(MockPair).creationCode));

    constructor() {
        shouldRevertOnCreate = false;
        pairToReturn = address(0);
    }
    bytes32 public constant INIT_CODE_HASH = 0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5;

    function calculatePairAddress(address tokenA, address tokenB) public view returns (address) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        bytes32 hash = keccak256(abi.encodePacked(
            hex"ff",
            address(this),
            salt,
            INIT_CODE_PAIR_HASH
        ));

        return address(uint160(uint256(hash)));
    }
/**
     * @dev Mock implementation of getPair.
     *      Now returns the CREATE2 address if pair was "created" or calculated.
     */
    function getPair(address tokenA, address tokenB) external view returns (address pair) {
        // If pairToReturn is explicitly set, return it (overrides everything)
        if (pairToReturn != address(0)) {
            return pairToReturn;
        }

        // Otherwise check if we have a manually set pair
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        bytes32 pairKey = keccak256(abi.encodePacked(token0, token1));

        if (pairs[pairKey] != address(0)) {
            return pairs[pairKey];
        }

        // If no pair is set, return the CREATE2 calculated address
        // This simulates the behavior where getPair returns address(0)
        // for non-existent pairs, but we can choose to return the calculated address
        // to match the off-chain calculation in getPairAddress
        return address(0);

        // Alternatively, to always return the calculated address:
        // return calculatePairAddress(tokenA, tokenB);
    }

    /**
     * @dev Mock implementation of createPair.
     *      Now creates pair using CREATE2 address calculation.
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(!shouldRevertOnCreate, "MockPancakeFactory: Forced revert on createPair");

        // Record call parameters
        lastTokenA = tokenA;
        lastTokenB = tokenB;

        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        bytes32 pairKey = keccak256(abi.encodePacked(token0, token1));

        // Check if pair already exists
        if (pairs[pairKey] != address(0)) {
            return pairs[pairKey];
        }

        // Calculate CREATE2 address
        address calculatedPair = calculatePairAddress(tokenA, tokenB);

        // Store the pair
        pairs[pairKey] = calculatedPair;
        allPairs.push(calculatedPair);

        emit PairCreated(token0, token1, calculatedPair, allPairs.length);

        return calculatedPair;
    }

    /**
     * @dev Get the number of all pairs created.
     */
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }

    /**
     * @dev Manually set a pair address for two tokens (bypasses createPair).
     */
    function setPair(address tokenA, address tokenB, address pairAddress) external {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        bytes32 pairKey = keccak256(abi.encodePacked(token0, token1));

        pairs[pairKey] = pairAddress;

        // Also add to allPairs if it's a new pair
        bool exists = false;
        for (uint256 i = 0; i < allPairs.length; i++) {
            if (allPairs[i] == pairAddress) {
                exists = true;
                break;
            }
        }
        if (!exists && pairAddress != address(0)) {
            allPairs.push(pairAddress);
        }
    }

    /**
     * @dev Set what address getPair should return (overrides mapping).
     */
    function setPairToReturn(address _pairToReturn) external {
        pairToReturn = _pairToReturn;
    }

    /**
     * @dev Toggle whether createPair should revert.
     */
    function setShouldRevertOnCreate(bool _shouldRevert) external {
        shouldRevertOnCreate = _shouldRevert;
    }

    /**
     * @dev Get the last tokens used in createPair call.
     */
    function getLastCreatePairCall() external view returns (address tokenA, address tokenB) {
        return (lastTokenA, lastTokenB);
    }

    /**
     * @dev Helper function to sort tokens in canonical order.
     */
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "MockPancakeFactory: ZERO_ADDRESS");
        require(token0 != token1, "MockPancakeFactory: IDENTICAL_ADDRESSES");
    }

    /**
     * @dev Get all created pairs (for testing verification).
     */
    function getAllPairs() external view returns (address[] memory) {
        return allPairs;
    }
}

contract MockPair {
    constructor() {}
}