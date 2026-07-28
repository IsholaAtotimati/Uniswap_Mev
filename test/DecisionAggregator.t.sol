// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DecisionAggregator} from "../src/DecisionAggregator.sol";

contract DecisionAggregatorTest is Test {
    DecisionAggregator internal aggregator;

    function setUp() public {
        aggregator = new DecisionAggregator();
    }

    function test_aggregatesApprovedDecision() public view {
        DecisionAggregator.ExecutionDecision memory decision = aggregator.aggregateDecision(true, true, 1200, true);

        assertEq(uint8(decision.status), uint8(DecisionAggregator.DecisionStatus.APPROVED));
        assertEq(decision.fee, 1200);
        assertEq(uint8(decision.settlement), uint8(DecisionAggregator.SettlementMode.REQUIRED));
        assertEq(bytes(decision.reason).length, 0);
        assertEq(uint8(decision.confidence), uint8(DecisionAggregator.Confidence.HIGH));
    }

    function test_rejectsWhenSignatureVerificationFails() public view {
        DecisionAggregator.ExecutionDecision memory decision = aggregator.aggregateDecision(false, true, 1200, false);

        assertEq(uint8(decision.status), uint8(DecisionAggregator.DecisionStatus.REJECTED));
        assertEq(decision.fee, 0);
        assertEq(uint8(decision.settlement), uint8(DecisionAggregator.SettlementMode.NONE));
        assertEq(decision.reason, "signature failed");
        assertEq(uint8(decision.confidence), uint8(DecisionAggregator.Confidence.LOW));
    }

    function test_rejectsWhenRiskPolicyFails() public view {
        DecisionAggregator.ExecutionDecision memory decision = aggregator.aggregateDecision(true, false, 1200, false);

        assertEq(uint8(decision.status), uint8(DecisionAggregator.DecisionStatus.REJECTED));
        assertEq(decision.fee, 0);
        assertEq(uint8(decision.settlement), uint8(DecisionAggregator.SettlementMode.NONE));
        assertEq(decision.reason, "risk policy failed");
        assertEq(uint8(decision.confidence), uint8(DecisionAggregator.Confidence.MEDIUM));
    }
}
