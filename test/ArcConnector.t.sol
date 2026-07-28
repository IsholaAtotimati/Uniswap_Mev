// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ArcConnector} from "../src/ArcConnector.sol";

contract MockSettlementCoordinator {
    enum SettlementStatus { Pending, BurnSubmitted, AwaitingAttestation, MintSubmitted, Completed, Failed, Cancelled }

    struct SettlementState { uint256 amount; uint32 destinationDomain; address token; bool settled; }
    mapping(bytes32 => SettlementState) public settlements;
    mapping(bytes32 => bytes32) public settlementRecipients;
    mapping(bytes32 => bytes32) public cctpMessageIds;
    mapping(bytes32 => uint64) public cctpNonces;
    mapping(bytes32 => SettlementStatus) public settlementStatus;
    address public settlementRelayer;

    function setSettlement(bytes32 id, uint256 amount, uint32 destinationDomain, address token, bytes32 recipient) external {
        settlements[id] = SettlementState(amount, destinationDomain, token, false);
        settlementRecipients[id] = recipient;
        settlementStatus[id] = SettlementStatus.Pending;
    }

    function setSettlementRelayer(address relayer) external {
        settlementRelayer = relayer;
    }

    function recordCCTPMessage(bytes32 id, bytes32 messageId, uint64 nonce) external {
        require(msg.sender == settlementRelayer, "Unauthorized");
        cctpMessageIds[id] = messageId;
        cctpNonces[id] = nonce;
        settlementStatus[id] = SettlementStatus.BurnSubmitted;
    }

    function markAwaitingAttestation(bytes32 id) external {
        require(msg.sender == settlementRelayer, "Unauthorized");
        settlementStatus[id] = SettlementStatus.AwaitingAttestation;
    }

    function markSettlementFailed(bytes32 id, string calldata _reason) external {
        require(msg.sender == settlementRelayer, "Unauthorized");
        settlementStatus[id] = SettlementStatus.Failed;
    }

    function completeSettlement(bytes32 id) external {
        require(msg.sender == settlementRelayer, "Unauthorized");
        settlements[id].settled = true;
        settlementStatus[id] = SettlementStatus.Completed;
    }
}

contract MockTokenMessenger {
    bool public ok;

    constructor(bool _ok) {
        ok = _ok;
    }

    function depositForBurn(uint256, uint32, bytes32, address) external view returns (uint64) {
        require(ok, "depositForBurn failed");
        return 1;
    }

    function setResult(bool _ok) external {
        ok = _ok;
    }
}

contract ArcConnectorTest is Test {
    MockSettlementCoordinator coord;
    MockTokenMessenger messenger;
    ArcConnector connector;
    address constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    function setUp() public {
        coord = new MockSettlementCoordinator();
        messenger = new MockTokenMessenger(true);
        connector = new ArcConnector(address(coord), address(messenger), USDC);
        coord.setSettlementRelayer(address(connector));
    }

    function test_successfulArcFlowRecordsCCTPMessageAndMarksSent() public {
        bytes32 id = bytes32(uint256(0x123));
        coord.setSettlement(id, 10, 3, USDC, bytes32(uint256(0xCAFE)));

        bool ok = connector.processSettlement(id);

        assertTrue(ok, "processSettlement should return true on success");
        (uint256 amount, uint32 destinationDomain, address token, bool settled) = coord.settlements(id);
        assertEq(amount, 10);
        assertEq(destinationDomain, 3);
        assertEq(token, USDC);
        assertTrue(!settled, "settlement should remain unsatisfied until attestation finalization");
        assertEq(uint8(coord.settlementStatus(id)), 2, "settlement should transition to AwaitingAttestation");
        assertTrue(coord.cctpMessageIds(id) != bytes32(0), "CCTP message ID should be recorded");
        assertEq(coord.cctpNonces(id), 1, "CCTP nonce should be recorded");
    }

    function test_failedArcDoesNotMarkSettlement() public {
        bytes32 id = bytes32(uint256(0x124));
        coord.setSettlement(id, 20, 1, USDC, bytes32(uint256(0xBABE)));
        messenger.setResult(false);

        bool ok = connector.processSettlement(id);

        assertTrue(!ok, "processSettlement should return false when TokenMessenger fails");
        (, , , bool settled) = coord.settlements(id);
        assertTrue(!settled, "settlement should remain not settled");
    }
}
