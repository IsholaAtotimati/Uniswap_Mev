// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface ISettlementCoordinator {
    function settlements(bytes32) external view returns (uint256 amount, uint32 destinationDomain, address token, bool settled);
    function settlementRecipients(bytes32) external view returns (bytes32 recipient);
    function recordCCTPMessage(bytes32 settlementId, bytes32 messageId, uint64 nonce) external;
    function markAwaitingAttestation(bytes32 settlementId) external;
    function markSettlementFailed(bytes32 settlementId, string calldata reason) external;
}

interface ITokenMessenger {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external returns (uint64 nonce);
}

/// @title ArcConnector
/// @notice Circle-facing settlement connector that routes settlement requests through
///         the native CCTP TokenMessenger burn flow and then finalizes settlement state
///         on the coordinator.
contract ArcConnector {
    address public owner;
    ISettlementCoordinator public coordinator;
    ITokenMessenger public tokenMessenger;
    address public immutable usdc;

    error Unauthorized();
    error TokenMessengerNotSet();
    error AlreadySettled();
    error InvalidSettlement();

    event CCTPDepositBuilt(bytes32 indexed settlementId, address token, uint256 amount, uint32 destinationDomain, bytes32 recipient);
    event CCTPDepositSent(bytes32 indexed settlementId, address indexed messenger, uint64 nonce, bytes32 messageId);
    event CCTPConfirmed(bytes32 indexed settlementId, bool success);
    event TokenMessengerUpdated(address indexed messenger);

    constructor(address _coordinator, address _tokenMessenger, address _usdc) {
        owner = msg.sender;
        coordinator = ISettlementCoordinator(_coordinator);
        if (_tokenMessenger != address(0)) tokenMessenger = ITokenMessenger(_tokenMessenger);
        if (_usdc != address(0)) usdc = _usdc;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    function setTokenMessenger(address _tokenMessenger) external onlyOwner {
        tokenMessenger = ITokenMessenger(_tokenMessenger);
        emit TokenMessengerUpdated(_tokenMessenger);
    }

    /// @notice Process a settlement through Circle's CCTP TokenMessenger burn path.
    /// @dev The settlement's recipient bytes32 is forwarded into the Circle mintRecipient
    ///      shape, while the coordinator remains the state-orchestration layer.
    function processSettlement(bytes32 settlementId) external returns (bool) {
        if (address(tokenMessenger) == address(0)) revert TokenMessengerNotSet();

        (uint256 amount, uint32 destinationDomain, address token, bool settled) = coordinator.settlements(settlementId);
        bytes32 recipient = coordinator.settlementRecipients(settlementId);

        if (amount == 0 || token == address(0) || recipient == bytes32(0)) revert InvalidSettlement();
        if (token != usdc) revert InvalidSettlement();
        if (settled) revert AlreadySettled();

        emit CCTPDepositBuilt(settlementId, token, amount, destinationDomain, recipient);

        try tokenMessenger.depositForBurn(amount, destinationDomain, recipient, token) returns (uint64 nonce) {
            bytes32 messageId = keccak256(abi.encodePacked(settlementId, nonce, destinationDomain, token, recipient));
            coordinator.recordCCTPMessage(settlementId, messageId, nonce);
            coordinator.markAwaitingAttestation(settlementId);
            emit CCTPDepositSent(settlementId, address(tokenMessenger), nonce, messageId);
            emit CCTPConfirmed(settlementId, true);
            return true;
        } catch {
            coordinator.markSettlementFailed(settlementId, "TokenMessenger deposit failed");
            emit CCTPConfirmed(settlementId, false);
            return false;
        }
    }
}
