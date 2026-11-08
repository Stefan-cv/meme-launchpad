// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IMEMEDistributor.sol
 * @notice Interface for the MEMEDistributor contract
 */
interface IMEMEDistributor {
    error InvalidMerkleProof();
    error InvalidTokenAddress();
    error InvalidAmount();
    error TransferAmountMismatch();
    error NoTokensToClaim();
    error MerkleRootNotSet();
    error InvalidReceipt();
    error TransferNativeTokenFailed();

    event Claimed(
        address indexed user,
        address indexed token,
        bytes32 indexed uid,
        address receiver,
        uint256 amount
    );

    event Verified(
        address indexed user,
        address indexed token,
        bytes32 indexed uid,
        uint256 amountClaimable
    );

    event SetMerkleRoot(
        address indexed token,
        bytes32 indexed uid,
        bytes32 indexed merkleRoot
    );

    event TokensDeposited(
        address indexed user,
        address indexed recipient,
        address indexed token,
        uint256 amount
    );

    function depositTokens(address tokenAddress, address recipient, uint256 amount) external payable;

    function claim(
        address tokenAddress,
        bytes32 uid,
        address receiver,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountOut);

    function claimVerified(address tokenAddress, bytes32 uid, address receiver) external returns (uint256 amountOut);

    function verify(
        address tokenAddress,
        bytes32 uid,
        address user,
        uint256 totalAccrued,
        bytes32[] calldata proof
    ) external returns (uint256 amountClaimable);

    function setMerkleRoot(address tokenAddress, bytes32 uid, bytes32 newMerkleRoot) external;

}