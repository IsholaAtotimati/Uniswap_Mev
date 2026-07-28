// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {StateEngine} from "./StateEngine.sol";
import {EventPublisher} from "./EventPublisher.sol";
import {IERC20Minimal} from "v4-core/interfaces/external/IERC20Minimal.sol";

abstract contract SettlementCoordinator is StateEngine, EventPublisher {

    address public immutable USDC;
    address public settlementRelayer;
    mapping(bytes32 => bytes32) public settlementRecipients;
    mapping(address => bool) public authorizedSettlementAdapters;

    error InvalidRecipient();
    error InvalidSettlementToken();
    error UnauthorizedSettlementExecutor();
    error UnauthorizedSettlementCoordinator();
    error TransferFailed();
    error AlreadySettled();
    error InvalidSettlementStatus();

    constructor(address usdc) {
        if (usdc == address(0)) revert InvalidSettlementToken();
        USDC = usdc;
    } 

    function _multisig() internal view virtual returns (address);
    function _executionCoordinator() internal view virtual returns (address);

    modifier onlySettlementMultisig() {
        if (msg.sender != _multisig()) revert UnauthorizedSettlementCoordinator();
        _;
    }

    modifier onlyExecutionCoordinator() {
        if (msg.sender != _executionCoordinator()) revert UnauthorizedSettlementExecutor();
        _;
    }

    function setSettlementRelayer(address relayer) external onlySettlementMultisig {
        if (relayer == address(0)) revert InvalidRecipient();
        settlementRelayer = relayer;
    }

    function setSettlementAdapter(address adapter, bool enabled) external onlySettlementMultisig {
        if (adapter == address(0)) revert InvalidRecipient();
        authorizedSettlementAdapters[adapter] = enabled;
    }

    function _authorizeSettlement(
        bytes32 poolId,
        address token,
        uint256 amount,
        uint32 destinationDomain,
        bytes32 recipient,
        uint256 nonce
    ) internal returns (bytes32 settlementId) {
        if (token != USDC) revert InvalidSettlementToken();

        settlementId = _hashBytesRaw(abi.encode(poolId, nonce));
        settlements[settlementId] = SettlementState({
            amount: amount,
            destinationDomain: destinationDomain,
            token: token,
            settled: false
        });
        settlementStatus[settlementId] = SettlementStatus.Pending;
        settlementRecipients[settlementId] = recipient;

        emit SettlementCreated(
            settlementId,
            token,
            amount,
            destinationDomain
        );

        address recipientAddress = address(uint160(uint256(recipient)));

        emit SettlementAuthorized(
            settlementId,
            recipientAddress,
            token,
            amount
        );
    }

    function authorizeSettlement(
        bytes32 poolId,
        address token,
        uint256 amount,
        uint32 destinationDomain,
        bytes32 recipient,
        uint256 nonce
    ) external onlyExecutionCoordinator returns (bytes32 settlementId) {
        settlementId = _authorizeSettlement(poolId, token, amount, destinationDomain, recipient, nonce);
    }

    function recordCCTPMessage(bytes32 settlementId, bytes32 messageId, uint64 nonce) external {
        if (msg.sender != settlementRelayer && !authorizedSettlementAdapters[msg.sender]) revert UnauthorizedSettlementExecutor();

        SettlementState storage settlement = settlements[settlementId];
        if (settlement.amount == 0) revert InvalidRecipient();
        if (settlement.settled) revert AlreadySettled();
        if (settlementStatus[settlementId] != SettlementStatus.Pending && settlementStatus[settlementId] != SettlementStatus.Failed) {
            revert InvalidSettlementStatus();
        }

        cctpMessageIds[settlementId] = messageId;
        cctpNonces[settlementId] = nonce;
        settlementStatus[settlementId] = SettlementStatus.BurnSubmitted;

        emit CCTPBurnInitiated(settlementId, messageId, nonce, settlement.destinationDomain, settlement.token, settlement.amount);
        emit CCTPMessageRecorded(settlementId, messageId);
    }

    function markAwaitingAttestation(bytes32 settlementId) external {
        if (msg.sender != settlementRelayer && !authorizedSettlementAdapters[msg.sender]) revert UnauthorizedSettlementExecutor();

        SettlementState storage settlement = settlements[settlementId];
        if (settlement.amount == 0) revert InvalidRecipient();
        if (settlementStatus[settlementId] != SettlementStatus.BurnSubmitted) revert InvalidSettlementStatus();

        settlementStatus[settlementId] = SettlementStatus.AwaitingAttestation;
    }

    function markMintSubmitted(bytes32 settlementId) external {
        if (msg.sender != settlementRelayer && !authorizedSettlementAdapters[msg.sender]) revert UnauthorizedSettlementExecutor();

        SettlementState storage settlement = settlements[settlementId];
        if (settlement.amount == 0) revert InvalidRecipient();
        if (settlementStatus[settlementId] != SettlementStatus.AwaitingAttestation) revert InvalidSettlementStatus();

        settlementStatus[settlementId] = SettlementStatus.MintSubmitted;
    }

    function markSettlementFailed(bytes32 settlementId, string calldata reason) external {
        if (msg.sender != settlementRelayer && !authorizedSettlementAdapters[msg.sender]) revert UnauthorizedSettlementExecutor();

        SettlementState storage settlement = settlements[settlementId];
        if (settlement.amount == 0) revert InvalidRecipient();
        if (settlement.settled) revert AlreadySettled();

        settlementStatus[settlementId] = SettlementStatus.Failed;
        emit SettlementFailed(settlementId, reason);
    }

    function retrySettlement(bytes32 settlementId) external {
        if (msg.sender != settlementRelayer && !authorizedSettlementAdapters[msg.sender]) revert UnauthorizedSettlementExecutor();

        SettlementState storage settlement = settlements[settlementId];
        if (settlement.amount == 0) revert InvalidRecipient();
        if (settlementStatus[settlementId] != SettlementStatus.Failed) revert InvalidSettlementStatus();

        settlementStatus[settlementId] = SettlementStatus.Pending;
        emit SettlementRetried(settlementId);
    }

    function completeSettlement(bytes32 settlementId) external {
        if (msg.sender != settlementRelayer && !authorizedSettlementAdapters[msg.sender]) revert UnauthorizedSettlementExecutor();

        SettlementState storage settlement = settlements[settlementId];
        if (settlement.amount == 0) revert InvalidRecipient();
        if (settlement.settled) revert AlreadySettled();
        if (settlement.token != USDC) revert InvalidSettlementToken();
        if (
            settlementStatus[settlementId] != SettlementStatus.Pending &&
            settlementStatus[settlementId] != SettlementStatus.BurnSubmitted &&
            settlementStatus[settlementId] != SettlementStatus.AwaitingAttestation &&
            settlementStatus[settlementId] != SettlementStatus.MintSubmitted
        ) {
            revert InvalidSettlementStatus();
        }

        bytes32 recipient = settlementRecipients[settlementId];
        if (recipient != bytes32(0) && settlement.amount > 0) {
            address recipientAddress = address(uint160(uint256(recipient)));
            try IERC20Minimal(settlement.token).transferFrom(msg.sender, recipientAddress, settlement.amount) returns (bool success) {
                if (!success) revert TransferFailed();
            } catch {
                revert TransferFailed();
            }
        }

        settlement.settled = true;
        settlementStatus[settlementId] = SettlementStatus.Completed;

        emit SettlementExecuted(settlementId, msg.sender);

        emit FundsTransferred(settlementId, settlement.token, settlement.amount, recipient);

        emit SettlementCompleted(settlementId, settlement.amount);
    }

    function cancelSettlement(bytes32 settlementId) external {
        if (msg.sender != settlementRelayer && !authorizedSettlementAdapters[msg.sender]) revert UnauthorizedSettlementExecutor();

        SettlementState storage settlement = settlements[settlementId];
        if (settlement.amount == 0) revert InvalidRecipient();

        settlementStatus[settlementId] = SettlementStatus.Cancelled;

        emit SettlementCancelled(settlementId);
    }

    function _hashBytesRaw(bytes memory data) internal pure returns (bytes32 hash) {
        assembly {
            hash := keccak256(add(data, 0x20), mload(data))
        }
    }
}
