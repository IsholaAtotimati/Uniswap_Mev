// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

abstract contract StateEngine {
    struct PoolLossState {
        uint256 expectedLpLoss;
        uint256 expectedLeakage;
        uint256 toxicityScore;
        uint24 spread;
        uint256 updatedAt;
    }

    struct SettlementState {
        uint256 amount;
        uint32 destinationDomain;
        address token;
        bool settled;
    }

    enum SettlementStatus {
        Pending,
        BurnSubmitted,
        AwaitingAttestation,
        MintSubmitted,
        Completed,
        Failed,
        Cancelled
    }

    mapping(bytes32 => PoolLossState) public poolLoss;
    mapping(bytes32 => SettlementState) public settlements;
    mapping(bytes32 => SettlementStatus) public settlementStatus;
    mapping(bytes32 => bytes32) public cctpMessageIds;
    mapping(bytes32 => uint64) public cctpNonces;
}
