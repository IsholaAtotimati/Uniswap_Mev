// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SignatureEngine} from "./SignatureEngine.sol";

abstract contract RiskEngine {
    uint256 public maxExpectedLpLoss;
    uint256 public maxExpectedLeakage;
    uint256 public maxToxicityScore;
    uint24 public maxRecommendedSpread;
    bool public rejectOnThreshold;

    error RiskThresholdExceeded();
    error UnauthorizedRiskPolicy();

    function _initializeRiskPolicy() internal {
        maxExpectedLpLoss = type(uint256).max;
        maxExpectedLeakage = type(uint256).max;
        maxToxicityScore = type(uint256).max;
        maxRecommendedSpread = 20000;
        rejectOnThreshold = true;
    }

    function _multisig() internal view virtual returns (address);

    function setRiskPolicy(
        uint256 _maxExpectedLpLoss,
        uint256 _maxExpectedLeakage,
        uint256 _maxToxicityScore,
        uint24 _maxRecommendedSpread,
        bool _rejectOnThreshold
    ) external {
        if (msg.sender != _multisig()) revert UnauthorizedRiskPolicy();
        maxExpectedLpLoss = _maxExpectedLpLoss;
        maxExpectedLeakage = _maxExpectedLeakage;
        maxToxicityScore = _maxToxicityScore;
        maxRecommendedSpread = _maxRecommendedSpread;
        rejectOnThreshold = _rejectOnThreshold;
    }

    function evaluateRiskPolicy(SignatureEngine.LossPayload memory payload) internal view returns (uint24) {
        bool exceeds =
            payload.expectedLpLoss > maxExpectedLpLoss ||
            payload.expectedLeakage > maxExpectedLeakage ||
            payload.toxicityScore > maxToxicityScore ||
            payload.recommendedSpread > maxRecommendedSpread;

        if (exceeds && rejectOnThreshold) revert RiskThresholdExceeded();

        return payload.recommendedSpread > maxRecommendedSpread
            ? maxRecommendedSpread
            : payload.recommendedSpread;
    }
}
