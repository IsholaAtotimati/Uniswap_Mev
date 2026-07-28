// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolKey.sol";
import {MEVShieldHook} from "./MEVShieldHook.sol";
import {SignatureEngine} from "./SignatureEngine.sol";
import {DecisionAggregator} from "./DecisionAggregator.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {EventPublisher} from "./EventPublisher.sol";

contract ExecutionCoordinator is EventPublisher {
    address public immutable hook;
    DecisionAggregator public immutable decisionAggregator;

    event ExecutionDecision(
        bytes32 indexed settlementId,
        bytes32 indexed poolId,
        address indexed signer,
        uint24 recommendedSpread,
        uint24 feeOverride,
        bool authorized
    );

    modifier onlyHook() {
        require(msg.sender == hook, "Unauthorized");
        _;
    }

    constructor(address _hook) {
        require(_hook != address(0), "ZeroAddress");
        hook = _hook;
        decisionAggregator = new DecisionAggregator();
    }

    function coordinateSubmission(
        PoolKey calldata key,
        SignatureEngine.LossPayload calldata payload,
        SignatureEngine.Attestation[] calldata attestations
    ) external onlyHook returns (bytes32 settlementId) {
        MEVShieldHook mevHook = MEVShieldHook(hook);

        mevHook.verifyPayload(key, payload, attestations);

        (bool riskOk, uint24 constrainedFee) = mevHook.assessRiskPolicy(payload);
        DecisionAggregator.ExecutionDecision memory decision = decisionAggregator.aggregateDecision(
            true,
            riskOk,
            constrainedFee,
            true
        );

        if (decision.status != DecisionAggregator.DecisionStatus.APPROVED) {
            emit ExecutionRejected(payload.poolId, payload.signer, decision.reason);
            revert RiskEngine.RiskThresholdExceeded();
        }

        mevHook.storeRiskSnapshot(
            payload.poolId,
            payload.expectedLpLoss,
            payload.expectedLeakage,
            payload.toxicityScore,
            payload.recommendedSpread
        );

        settlementId = mevHook.authorizeSettlement(
            payload.poolId,
            payload.settlementToken,
            payload.settlementAmount,
            payload.destinationDomain,
            payload.recipient,
            payload.nonce
        );

        uint24 feeOverride = mevHook.applyFee(key, decision.fee);

        emit ExecutionDecision(
            settlementId,
            payload.poolId,
            payload.signer,
            payload.recommendedSpread,
            feeOverride,
            true
        );
    }
}
