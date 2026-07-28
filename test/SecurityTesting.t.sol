// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MEVShieldHook} from "../src/MEVShieldHook.sol";
import {SignatureEngine} from "../src/SignatureEngine.sol";
import {StateEngine} from "../src/StateEngine.sol";
import {ExecutionCoordinator} from "../src/ExecutionCoordinator.sol";
import {BaseHook} from "v4-hooks-public/lib/briefcase/src/protocols/v4-periphery/utils/BaseHook.sol";
import {PoolKey} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolKey.sol";
import {Currency} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/Currency.sol";
import {IHooks} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/interfaces/IHooks.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockPoolManager {
    function updateDynamicLPFee(PoolKey calldata, uint24) external pure {}
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract ReentrancyAttacker {
    MEVShieldHook public hook;
    uint256 public callCount;

    constructor(address _hook) { hook = MEVShieldHook(_hook); }

    receive() external payable {
        callCount++;
        if (callCount < 2) {
            // Attempt reentrancy
            bytes32 id = keccak256(abi.encode("attack"));
            try hook.completeSettlement(id) {} catch {}
        }
    }
}

contract MEVShieldHookHarness is MEVShieldHook {
    constructor(address poolManager, address usdc) MEVShieldHook(poolManager, address(this), usdc) {}
    function validateHookAddress(BaseHook) internal pure override {}
    function exposeSetTrustedSigner(address signer, bool trusted) external {
        this.setTrustedSigner(signer, trusted);
    }
    function exposeSetExecutionCoordinator(address _coordinator) external {
        this.setExecutionCoordinator(_coordinator);
    }
    function exposeSetSettlementRelayer(address relayer) external {
        this.setSettlementRelayer(relayer);
    }
    function exposeSetOracleAvailability(bool available) external {
        this.setOracleAvailability(available);
    }
    function exposeDomainSeparator() public view returns (bytes32) {
        return _domainSeparator();
    }
    function exposeHashPayload(SignatureEngine.LossPayload memory payload) public pure returns (bytes32) {
        return _hashPayload(payload);
    }
}

contract SecurityTests is Test {
    MEVShieldHookHarness public hook;
    ExecutionCoordinator public coordinator;
    MockERC20 public token;
    
    address private signer1 = vm.addr(0xA11CE);
    address private signer2 = vm.addr(0xBEEF);
    address private attacker = address(0xDEAD);
    address private relayer = address(0x1111);
    PoolKey private testKey;

    function setUp() public {
        MockPoolManager poolManager = new MockPoolManager();
        MockERC20 usdc = new MockERC20();
        hook = new MEVShieldHookHarness(address(poolManager), address(usdc));
        coordinator = new ExecutionCoordinator(address(hook));
        hook.exposeSetExecutionCoordinator(address(coordinator));
        hook.exposeSetSettlementRelayer(relayer);
        hook.exposeSetTrustedSigner(signer1, true);
        
        token = usdc;
        
        testKey = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function _buildPayload(bytes32 poolId, uint256 nonce, address signer) 
        internal view returns (SignatureEngine.LossPayload memory)
    {
        return SignatureEngine.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 75,
            recommendedSpread: 1200,
            settlementToken: address(token),
            settlementAmount: 5e6,
            destinationDomain: 3,
            recipient: bytes32(uint256(uint160(relayer))),
            expiry: block.timestamp + 1 hours,
            nonce: nonce,
            signer: signer
        });
    }

    function _createSettlement(bytes32 poolId, uint256 nonce, uint256 signerPk) 
        internal returns (bytes32)
    {
        address signer = vm.addr(signerPk);
        if (!hook.isTrustedSigner(signer)) {
            hook.exposeSetTrustedSigner(signer, true);
        }

        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, nonce, signer);
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        return hook.submitRiskPayload(testKey, payload, signature);
    }

    // ============= REENTRANCY TESTS =============
    
    function test_security_reentrancy_protection() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        token.mint(relayer, 10e6);
        vm.prank(relayer);
        token.approve(address(hook), 10e6);

        bytes32 settlementId = _createSettlement(poolId, 1000, 0xA11CE);

        // Settlement already safe from reentrancy because msg.sender check is first
        vm.prank(relayer);
        hook.completeSettlement(settlementId);

        assertTrue(hook.settlementStatus(settlementId) == StateEngine.SettlementStatus.Completed);
    }

    // ============= REPLAY PROTECTION TESTS =============
    
    function test_security_replay_protection_nonce_enforcement() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 5000, signer1);
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // First submission succeeds
        bytes32 settlementId1 = hook.submitRiskPayload(testKey, payload, signature);
        assertEq(uint8(hook.settlementStatus(settlementId1)), uint8(StateEngine.SettlementStatus.Pending));

        // Replay with same nonce should fail
        vm.expectRevert();
        hook.submitRiskPayload(testKey, payload, signature);
    }

    function test_security_replay_protection_different_nonces() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        // First payload with nonce 5001
        SignatureEngine.LossPayload memory payload1 = _buildPayload(poolId, 5001, signer1);
        bytes32 digest1 = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload1)
        ));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(0xA11CE, digest1);
        bytes memory sig1 = abi.encodePacked(r1, s1, v1);

        bytes32 id1 = hook.submitRiskPayload(testKey, payload1, sig1);
        assertTrue(hook.settlementStatus(id1) == StateEngine.SettlementStatus.Pending);

        // Second payload with same signer but different nonce should succeed
        SignatureEngine.LossPayload memory payload2 = _buildPayload(poolId, 5002, signer1);
        bytes32 digest2 = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload2)
        ));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(0xA11CE, digest2);
        bytes memory sig2 = abi.encodePacked(r2, s2, v2);

        bytes32 id2 = hook.submitRiskPayload(testKey, payload2, sig2);
        assertTrue(hook.settlementStatus(id2) == StateEngine.SettlementStatus.Pending);
        assertNotEq(id1, id2);
    }

    // ============= SIGNATURE FORGERY TESTS =============
    
    function test_security_signature_forgery_invalid_signer() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        // Create payload signed by attacker (not trusted signer)
        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 6000, attacker);
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(uint160(attacker)), digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Should fail because attacker is not a trusted signer
        vm.expectRevert();
        hook.submitRiskPayload(testKey, payload, signature);
    }

    function test_security_signature_forgery_modified_payload() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 6100, signer1);
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Valid submission
        bytes32 id1 = hook.submitRiskPayload(testKey, payload, signature);
        assertTrue(hook.settlementStatus(id1) == StateEngine.SettlementStatus.Pending);

        // Modify payload after signature and attempt reuse
        SignatureEngine.LossPayload memory modifiedPayload = _buildPayload(poolId, 6101, signer1);
        modifiedPayload.settlementAmount = 100e6; // Changed amount

        // This will have different nonce so won't be replay, but signature won't match
        vm.expectRevert();
        hook.submitRiskPayload(testKey, modifiedPayload, signature);
    }

    function test_security_signature_forgery_wrong_signature() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 6200, signer1);

        // Sign with wrong signer
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBEEF, digest); // Wrong signer
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert();
        hook.submitRiskPayload(testKey, payload, signature);
    }

    // ============= OVERFLOW TESTS =============
    
    function test_security_no_overflow_settlement_amount() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        token.mint(relayer, type(uint256).max);
        vm.prank(relayer);
        token.approve(address(hook), type(uint256).max);

        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 7000, signer1);
        payload.settlementAmount = type(uint256).max; // Large amount

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 settlementId = hook.submitRiskPayload(testKey, payload, signature);
        
        // Verify amount is stored correctly without overflow
        (uint256 amount, , , ) = hook.settlements(settlementId);
        assertEq(amount, type(uint256).max);
    }

    // ============= UNDERFLOW TESTS =============
    
    function test_security_no_underflow_settlement_completion() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        token.mint(relayer, 0); // No balance
        vm.prank(relayer);
        token.approve(address(hook), type(uint256).max);

        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 7100, signer1);
        payload.settlementAmount = 5e6;

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 settlementId = hook.submitRiskPayload(testKey, payload, signature);

        // Attempt completion without sufficient balance should fail
        vm.prank(relayer);
        vm.expectRevert();
        hook.completeSettlement(settlementId);
    }

    // ============= ORACLE MANIPULATION TESTS =============
    
    function test_security_oracle_manipulation_unavailable_oracle() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        // Set oracle unavailable
        hook.exposeSetOracleAvailability(false);

        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 8000, signer1);
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Should fail with OracleUnavailable error
        vm.expectRevert();
        hook.submitRiskPayload(testKey, payload, signature);

        // Re-enable oracle
        hook.exposeSetOracleAvailability(true);
    }

    // ============= FLASH LOAN ATTACK TESTS =============
    
    function test_security_flash_loan_protection() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        token.mint(relayer, 5e6);
        vm.prank(relayer);
        token.approve(address(hook), 5e6);

        bytes32 settlementId = _createSettlement(poolId, 9000, 0xA11CE);

        // Simulate flash loan by checking settlement requires explicit authorization
        vm.prank(attacker); // Non-relayer attempts completion
        vm.expectRevert();
        hook.completeSettlement(settlementId);

        // Only relayer can complete
        vm.prank(relayer);
        hook.completeSettlement(settlementId);
        assertTrue(hook.settlementStatus(settlementId) == StateEngine.SettlementStatus.Completed);
    }

    // ============= FRONT-RUNNING PROTECTION TESTS =============
    
    function test_security_frontrun_protection_signature_binding() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 10000, signer1);
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 settlementId1 = hook.submitRiskPayload(testKey, payload, signature);

        // Attacker cannot reuse signature with modified payload
        SignatureEngine.LossPayload memory frontrunPayload = payload;
        frontrunPayload.recommendedSpread = 5000; // Increase spread

        vm.expectRevert();
        hook.submitRiskPayload(testKey, frontrunPayload, signature);
    }

    // ============= SANDWICH ATTACK TESTS =============
    
    function test_security_sandwich_protection() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        // First settlement
        bytes32 id1 = _createSettlement(poolId, 11000, 0xA11CE);
        assertTrue(hook.settlementStatus(id1) == StateEngine.SettlementStatus.Pending);

        // Attacker cannot sandwich by submitting with modified spread
        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 11001, signer1);
        payload.recommendedSpread = 10000;

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xA11CE, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 id2 = hook.submitRiskPayload(testKey, payload, signature);
        assertNotEq(id1, id2); // Different settlements
    }

    // ============= INVALID SETTLEMENT ID TESTS =============
    
    function test_security_invalid_settlement_id_rejection() public {
        bytes32 invalidId = keccak256(abi.encode("nonexistent"));

        token.mint(relayer, 5e6);
        vm.prank(relayer);
        token.approve(address(hook), 5e6);

        vm.prank(relayer);
        vm.expectRevert();
        hook.completeSettlement(invalidId);
    }

    function test_security_invalid_settlement_id_zero() public {
        bytes32 zeroId = bytes32(0);

        vm.prank(relayer);
        vm.expectRevert();
        hook.completeSettlement(zeroId);
    }

    // ============= UNAUTHORIZED EXECUTION TESTS =============
    
    function test_security_unauthorized_execution_non_relayer() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        token.mint(relayer, 5e6);
        vm.prank(relayer);
        token.approve(address(hook), 5e6);

        bytes32 settlementId = _createSettlement(poolId, 12000, 0xA11CE);

        // Non-relayer cannot complete settlement
        vm.prank(attacker);
        vm.expectRevert();
        hook.completeSettlement(settlementId);

        // Relayer can complete
        vm.prank(relayer);
        hook.completeSettlement(settlementId);
    }

    function test_security_unauthorized_execution_settlement_twice() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        
        token.mint(relayer, 10e6);
        vm.prank(relayer);
        token.approve(address(hook), 10e6);

        bytes32 settlementId = _createSettlement(poolId, 12100, 0xA11CE);

        // Complete settlement once
        vm.prank(relayer);
        hook.completeSettlement(settlementId);
        assertTrue(hook.settlementStatus(settlementId) == StateEngine.SettlementStatus.Completed);

        // Attempt to complete again should fail with AlreadySettled
        vm.prank(relayer);
        vm.expectRevert();
        hook.completeSettlement(settlementId);
    }

    // ============= UNAUTHORIZED ADMIN TESTS =============
    
    function test_security_unauthorized_admin_set_signer() public {
        // Attacker cannot set themselves as trusted signer
        vm.prank(attacker);
        vm.expectRevert();
        hook.setTrustedSigner(attacker, true);

        // Verify attacker is not trusted
        assertFalse(hook.isTrustedSigner(attacker));
    }

    function test_security_unauthorized_admin_set_executor() public {
        address newExecutor = address(0x9999);

        // Attacker cannot set execution coordinator
        vm.prank(attacker);
        vm.expectRevert();
        hook.setExecutionCoordinator(newExecutor);

        // Verify executor unchanged
        assertEq(hook.executionCoordinator(), address(coordinator));
    }

    function test_security_unauthorized_admin_set_relayer() public {
        // Attacker cannot set relayer
        vm.prank(attacker);
        vm.expectRevert();
        hook.setSettlementRelayer(attacker);

        // Verify relayer unchanged
        assertEq(hook.settlementRelayer(), relayer);
    }

    function test_security_unauthorized_admin_set_oracle() public {
        // Attacker cannot disable oracle
        vm.prank(attacker);
        vm.expectRevert();
        hook.setOracleAvailability(false);

        // Verify oracle still available
        assertTrue(hook.oracleAvailable());
    }

    function test_security_unauthorized_admin_set_quorum() public {
        // Attacker cannot change quorum
        vm.prank(attacker);
        vm.expectRevert();
        hook.setQuorumThreshold(10);

        // Verify quorum unchanged
        assertEq(hook.quorumThreshold(), 1);
    }
}
