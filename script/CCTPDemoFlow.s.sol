// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ArcConnector} from "../src/ArcConnector.sol";
import {CCTPConnector} from "../src/CCTPConnector.sol";

contract DemoBurnMintToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function burnFrom(address from, uint256 amount) external {
        // Synthetic demo token: burn side is modeled as a no-op so the
        // orchestration proof focuses on the cross-chain settlement flow.
        balanceOf[from] += 0;
    }
}

contract DemoVerifier {
    address public token;
    uint256 public amount;
    address public recipient;

    constructor(address _token, uint256 _amount, address _recipient) {
        token = _token;
        amount = _amount;
        recipient = _recipient;
    }

    function verifyAttestation(bytes calldata) external returns (address, uint256, address) {
        return (token, amount, recipient);
    }
}

contract DemoSettlementCoordinator {
    enum SettlementStatus {
        Pending,
        BurnSubmitted,
        AwaitingAttestation,
        MintSubmitted,
        Completed,
        Failed,
        Cancelled
    }

    struct SettlementState {
        uint256 amount;
        uint32 destinationDomain;
        address token;
        bool settled;
    }

    mapping(bytes32 => SettlementState) public settlements;
    mapping(bytes32 => bytes32) public settlementRecipients;
    mapping(bytes32 => bytes32) public cctpMessageIds;
    mapping(bytes32 => uint64) public cctpNonces;
    mapping(bytes32 => SettlementStatus) public settlementStatus;
    mapping(address => bool) public authorizedSettlementAdapters;
    address public settlementRelayer;

    function setSettlement(bytes32 id, uint256 amount, uint32 domain, address token, bytes32 recipient) external {
        settlements[id] = SettlementState(amount, domain, token, false);
        settlementRecipients[id] = recipient;
        settlementStatus[id] = SettlementStatus.Pending;
    }

    function setSettlementRelayer(address relayer) external {
        settlementRelayer = relayer;
    }

    function setSettlementAdapter(address adapter, bool enabled) external {
        authorizedSettlementAdapters[adapter] = enabled;
    }

    function recordCCTPMessage(bytes32 id, bytes32 messageId, uint64 nonce) external {
        require(msg.sender == settlementRelayer || authorizedSettlementAdapters[msg.sender], "unauthorized");
        cctpMessageIds[id] = messageId;
        cctpNonces[id] = nonce;
        settlementStatus[id] = SettlementStatus.BurnSubmitted;
    }

    function markAwaitingAttestation(bytes32 id) external {
        require(msg.sender == settlementRelayer || authorizedSettlementAdapters[msg.sender], "unauthorized");
        settlementStatus[id] = SettlementStatus.AwaitingAttestation;
    }

    function markMintSubmitted(bytes32 id) external {
        require(msg.sender == settlementRelayer || authorizedSettlementAdapters[msg.sender], "unauthorized");
        settlementStatus[id] = SettlementStatus.MintSubmitted;
    }

    function markSettlementFailed(bytes32 id, string calldata) external {
        require(msg.sender == settlementRelayer || authorizedSettlementAdapters[msg.sender], "unauthorized");
        settlementStatus[id] = SettlementStatus.Failed;
    }

    function completeSettlement(bytes32 id) external {
        require(msg.sender == settlementRelayer || authorizedSettlementAdapters[msg.sender], "unauthorized");
        settlements[id].settled = true;
        settlementStatus[id] = SettlementStatus.Completed;
    }
}

contract DemoTokenMessenger {
    bool public ok;

    constructor(bool _ok) {
        ok = _ok;
    }

    function depositForBurn(uint256, uint32, bytes32, address) external view returns (uint64) {
        require(ok, "depositForBurn failed");
        return 1;
    }
}

contract CCTPDemoFlowScript is Script {
    DemoBurnMintToken public token;
    DemoVerifier public verifier;
    DemoSettlementCoordinator public coordinator;
    DemoTokenMessenger public messenger;
    ArcConnector public arcConnector;
    CCTPConnector public cctpConnector;

    bytes32 internal constant settlementId = bytes32(uint256(42));
    address internal constant destRecipient = address(0xBEEF);

    function run() external {
        vm.startBroadcast();

        token = new DemoBurnMintToken();
        verifier = new DemoVerifier(address(token), 100, destRecipient);
        coordinator = new DemoSettlementCoordinator();
        messenger = new DemoTokenMessenger(true);

        arcConnector = new ArcConnector(address(coordinator), address(messenger), address(token));
        cctpConnector = new CCTPConnector(address(verifier));

        coordinator.setSettlementRelayer(address(arcConnector));
        coordinator.setSettlementAdapter(address(arcConnector), true);
        coordinator.setSettlementAdapter(address(cctpConnector), true);
        cctpConnector.setSettlementCoordinator(address(coordinator));

        address demoOwner = msg.sender;
        token.mint(demoOwner, 1000);
        uint256 recipientBalanceBefore = token.balanceOf(destRecipient);

        coordinator.setSettlement(settlementId, 100, 3, address(token), bytes32(uint256(uint160(destRecipient))));

        bool burnOk = arcConnector.processSettlement(settlementId);
        require(burnOk, "source burn submission failed");
        require(uint8(coordinator.settlementStatus(settlementId)) == 2, "settlement should transition to AwaitingAttestation after burn");

        bytes32 messageId = coordinator.cctpMessageIds(settlementId);
        require(messageId != bytes32(0), "CCTP message id should be recorded");

        bool attestationOk = cctpConnector.processAttestation(abi.encodePacked("attestation"), settlementId);
        require(attestationOk, "destination attestation processing failed");

        (uint256 settlementAmount, , address settlementToken, bool settled) = coordinator.settlements(settlementId);
        require(settled, "settlement should be marked settled");
        require(settlementAmount == 100, "settlement amount should be preserved");
        require(settlementToken == address(token), "settlement token should remain the demo USDC token");
        require(uint8(coordinator.settlementStatus(settlementId)) == 4, "settlement should complete after destination mint");
        require(token.balanceOf(destRecipient) == recipientBalanceBefore + 100, "destination recipient should receive the expected minted amount");

        console2.log("CCTP demo flow completed");
        console2.logAddress(address(token));
        console2.logBytes32(messageId);
        console2.logUint(uint8(coordinator.settlementStatus(settlementId)));

        vm.stopBroadcast();
    }
}
