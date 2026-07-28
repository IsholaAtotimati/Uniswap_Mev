// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract DecisionAggregator {
    enum DecisionStatus {
        APPROVED,
        REJECTED
    }

    enum SettlementMode {
        NONE,
        REQUIRED
    }

    enum Confidence {
        LOW,
        MEDIUM,
        HIGH
    }

    struct ExecutionDecision {
        DecisionStatus status;
        uint24 fee;
        SettlementMode settlement;
        string reason;
        Confidence confidence;
    }

    function aggregateDecision(
        bool signatureValid,
        bool riskOk,
        uint24 fee,
        bool settlementRequired
    ) external pure returns (ExecutionDecision memory decision) {
        if (!signatureValid) {
            return ExecutionDecision({
                status: DecisionStatus.REJECTED,
                fee: 0,
                settlement: SettlementMode.NONE,
                reason: "signature failed",
                confidence: Confidence.LOW
            });
        }

        if (!riskOk) {
            return ExecutionDecision({
                status: DecisionStatus.REJECTED,
                fee: 0,
                settlement: SettlementMode.NONE,
                reason: "risk policy failed",
                confidence: Confidence.MEDIUM
            });
        }

        return ExecutionDecision({
            status: DecisionStatus.APPROVED,
            fee: fee,
            settlement: settlementRequired ? SettlementMode.REQUIRED : SettlementMode.NONE,
            reason: "",
            confidence: Confidence.HIGH
        });
    }
}
