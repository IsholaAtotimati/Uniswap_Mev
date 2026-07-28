// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {CCTPConnector} from "../src/CCTPConnector.sol";

contract MockBurnMintToken {
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

contract MockVerifier {
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

contract MockSettlementCoordinator {
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
    mapping(bytes32 => bytes32) public cctpMessageIds;
    mapping(bytes32 => SettlementStatus) public settlementStatus;

    function setSettlement(bytes32 settlementId, uint256 amount, uint32 destinationDomain, address token) external {
        settlements[settlementId] = SettlementState(amount, destinationDomain, token, false);
        settlementStatus[settlementId] = SettlementStatus.Pending;
    }

    function markAwaitingAttestation(bytes32 settlementId) external {
        settlementStatus[settlementId] = SettlementStatus.AwaitingAttestation;
    }

    function markMintSubmitted(bytes32 settlementId) external {
        settlementStatus[settlementId] = SettlementStatus.MintSubmitted;
    }

    function completeSettlement(bytes32 settlementId) external {
        settlements[settlementId].settled = true;
        settlementStatus[settlementId] = SettlementStatus.Completed;
    }
}

contract CCTPConnectorTest is Test{
    CCTPConnector connector;
    MockBurnMintToken token;
    MockVerifier verifier;
    MockSettlementCoordinator coordinator;

    function setUp() public {
        token = new MockBurnMintToken();
        verifier = new MockVerifier(address(token), 100, address(0xBEEF));
        coordinator = new MockSettlementCoordinator();
        connector = new CCTPConnector(address(verifier));
        connector.setSettlementCoordinator(address(coordinator));

        // give caller some balance and approve the connector
        token.mint(address(this), 1000);
        token.approveTo(address(this), address(connector), type(uint256).max);
        // Note: mock burnFrom checks allowance[msg.sender][msg.sender] for simplicity; set it
        token.approveTo(address(this), address(connector), type(uint256).max);
    }

    function test_processAttestationBurnsAndMints() public {
        bytes memory att = abi.encodePacked("att");
        // Approve connector to burn tokens from this contract
        token.approveTo(address(this), address(connector), 1000);

        bool ok = connector.processAttestation(att);
        assertTrue(ok, "processAttestation should succeed");
        // Check minted balance
        assertEq(token.balanceOf(address(0xBEEF)), 100);
    }

    function test_processAttestationFinalizesMatchingSettlement() public {
        bytes memory att = abi.encodePacked("att");
        bytes32 settlementId = bytes32(uint256(7));
        coordinator.setSettlement(settlementId, 100, 3, address(token));
        token.approveTo(address(this), address(connector), 1000);

        bool ok = connector.processAttestation(att, settlementId);
        assertTrue(ok, "processAttestation should finalize the settlement");

        assertEq(token.balanceOf(address(0xBEEF)), 100);
        (uint256 amount, uint32 destinationDomain, address tokenAddress, bool settled) = coordinator.settlements(settlementId);
        assertEq(amount, 100);
        assertEq(destinationDomain, 3);
        assertEq(tokenAddress, address(token));
        assertTrue(settled);
    }

}
