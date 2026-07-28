// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolId} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolId.sol";

abstract contract EventPublisher {
    event FeeUpdated(PoolId indexed poolId, uint24 oldFee, uint24 newFee);

    event LossProtectionApplied(
        bytes32 indexed poolId,
        uint256 expectedLpLoss,
        uint256 expectedLeakage,
        uint256 toxicityScore,
        uint24 spread
    );

    event SettlementAuthorized(
        bytes32 indexed settlementId,
        address indexed recipient,
        address indexed token,
        uint256 amount
    );

    event PriceVerified(
        bytes32 indexed poolId,
        address indexed signer,
        uint256 nonce
    );

    event RiskChecked(
        bytes32 indexed poolId,
        address indexed signer,
        bool approved,
        uint24 fee,
        string reason
    );

    event ExecutionRejected(
        bytes32 indexed poolId,
        address indexed signer,
        string reason
    );

    event SettlementCreated(
        bytes32 indexed settlementId,
        address token,
        uint256 amount,
        uint32 destinationDomain
    );

    event SettlementExecuted(
        bytes32 indexed settlementId,
        address indexed caller
    );

    event CCTPBurnInitiated(
        bytes32 indexed settlementId,
        bytes32 indexed cctpMessageId,
        uint64 nonce,
        uint32 destinationDomain,
        address token,
        uint256 amount
    );

    event AttestationReceived(
        bytes32 indexed settlementId,
        bytes32 indexed cctpMessageId,
        bytes32 indexed attestationHash,
        address token,
        uint256 amount,
        address recipient
    );

    event USDCMintCompleted(
        bytes32 indexed settlementId,
        address token,
        uint256 amount,
        address recipient
    );

    event CrossChainSettlementCompleted(
        bytes32 indexed settlementId,
        bytes32 indexed cctpMessageId
    );

    event SettlementFailed(
        bytes32 indexed settlementId,
        string reason
    );

    event CCTPMessageRecorded(
        bytes32 indexed settlementId,
        bytes32 indexed messageId
    );

    event SettlementRetried(
        bytes32 indexed settlementId
    );

    event FundsTransferred(
        bytes32 indexed settlementId,
        address indexed token,
        uint256 amount,
        bytes32 recipient
    );

    event SettlementCompleted(
        bytes32 indexed settlementId,
        uint256 amount
    );

    event SettlementCancelled(
        bytes32 indexed settlementId
    );

    event TrustedSignerUpdated(address indexed signer, bool trusted);
}
