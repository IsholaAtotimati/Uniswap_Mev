// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ArcConnector} from "../src/ArcConnector.sol";
import {CCTPConnector} from "../src/CCTPConnector.sol";

contract DemoBurnMintToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function burnFrom(address from, uint256 amount) external {
        uint256 allowed = allowance[from][msg.sender];
        if (msg.sender != from) {
            require(allowed >= amount, "insufficient allowance");
            allowance[from][msg.sender] = allowed - amount;
        }
        require(balanceOf[from] >= amount, "insufficient balance");
        balanceOf[from] -= amount;
    }

    function approveTo(address owner, address spender, uint256 amount) external {
        allowance[owner][spender] = amount;
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

contract CCTPDemoFlowTest is Test {
    DemoSettlementCoordinator coordinator;
    DemoBurnMintToken token;
    DemoVerifier verifier;
    DemoTokenMessenger messenger;
    ArcConnector arcConnector;
    CCTPConnector cctpConnector;

    bytes32 constant settlementId = bytes32(uint256(42));
    address constant destRecipient = address(0xBEEF);
    address usdc;

    function setUp() public {
        token = new DemoBurnMintToken();
        usdc = address(token);
        verifier = new DemoVerifier(address(token), 100, destRecipient);
        coordinator = new DemoSettlementCoordinator();
        messenger = new DemoTokenMessenger(true);

        arcConnector = new ArcConnector(address(coordinator), address(messenger), usdc);
        cctpConnector = new CCTPConnector(address(verifier));

        coordinator.setSettlementRelayer(address(arcConnector));
        coordinator.setSettlementAdapter(address(arcConnector), true);
        coordinator.setSettlementAdapter(address(cctpConnector), true);
        cctpConnector.setSettlementCoordinator(address(coordinator));

        token.mint(address(this), 1000);
        token.approveTo(address(this), address(cctpConnector), type(uint256).max);
        token.approveTo(address(this), address(arcConnector), type(uint256).max);

        coordinator.setSettlement(settlementId, 100, 3, usdc, bytes32(uint256(uint160(destRecipient))));
    }

    function test_crossChainDemoFlowShowsSourceBurnAndDestinationMintLifecycle() public {
        bool burnSubmitted = arcConnector.processSettlement(settlementId);
        assertTrue(burnSubmitted, "arc burn submission should succeed");
        assertEq(uint8(coordinator.settlementStatus(settlementId)), 2, "settlement should move to awaiting attestation after burn");
        assertTrue(coordinator.cctpMessageIds(settlementId) != bytes32(0), "CCTP message id should be persisted");

        bool attested = cctpConnector.processAttestation(abi.encodePacked("attestation"), settlementId);
        assertTrue(attested, "attestation processing should succeed");
        assertEq(uint8(coordinator.settlementStatus(settlementId)), 4, "settlement should be completed after destination mint");
        assertEq(token.balanceOf(destRecipient), 100, "destination recipient should receive minted USDC");
    }
}
