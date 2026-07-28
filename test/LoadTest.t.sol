// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, stdJson} from "forge-std/Test.sol";
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

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
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

    function exposeDomainSeparator() public view returns (bytes32) {
        return _domainSeparator();
    }

    function exposeHashPayload(SignatureEngine.LossPayload memory payload) public pure returns (bytes32) {
        return _hashPayload(payload);
    }

}

contract MEVShieldLoadTest is Test {
    MEVShieldHookHarness public hook;
    ExecutionCoordinator public coordinator;
    MockERC20 public token;
    
    address private settlementRelayer = address(0xBEEF);
    PoolKey private testKey;

    function setUp() public {
        MockPoolManager poolManager = new MockPoolManager();
        MockERC20 usdc = new MockERC20();
        hook = new MEVShieldHookHarness(address(poolManager), address(usdc));
        coordinator = new ExecutionCoordinator(address(hook));
        hook.exposeSetExecutionCoordinator(address(coordinator));
        hook.exposeSetSettlementRelayer(settlementRelayer);
        
        token = usdc;
        
        testKey = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function _buildPayload(
        bytes32 poolId,
        uint256 nonce,
        address signer
    ) internal view returns (SignatureEngine.LossPayload memory) {
        return SignatureEngine.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 75,
            recommendedSpread: 1200,
            settlementToken: address(token),
            settlementAmount: 5e6,
            destinationDomain: 3,
            recipient: bytes32(uint256(uint160(settlementRelayer))),
            expiry: block.timestamp + 1 hours,
            nonce: nonce,
            signer: signer
        });
    }

    function _createSettlement(bytes32 poolId, uint256 nonce, uint256 signerPk) 
        internal 
        returns (bytes32) 
    {
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

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

    function test_load_100_settlements() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        token.mint(settlementRelayer, 100 * 5e6);
        
        vm.prank(settlementRelayer);
        token.approve(address(hook), type(uint256).max);

        bytes32[] memory settlementIds = new bytes32[](100);

        uint256 startGas = gasleft();
        for (uint256 i = 0; i < 100; i++) {
            settlementIds[i] = _createSettlement(poolId, 1000 + i, 0xA11CE + i);
        }
        uint256 creationGas = startGas - gasleft();

        // Verify all settlements created
        for (uint256 i = 0; i < 100; i++) {
            bytes32 id = settlementIds[i];
            assertEq(uint8(hook.settlementStatus(id)), uint8(StateEngine.SettlementStatus.Pending));
        }

        // Complete settlements
        startGas = gasleft();
        for (uint256 i = 0; i < 100; i++) {
            vm.prank(settlementRelayer);
            hook.completeSettlement(settlementIds[i]);
        }
        uint256 completionGas = startGas - gasleft();

        // Verify all completed
        for (uint256 i = 0; i < 100; i++) {
            assertEq(uint8(hook.settlementStatus(settlementIds[i])), uint8(StateEngine.SettlementStatus.Completed));
        }

        emit log_named_uint("100 settlements - creation gas total", creationGas);
        emit log_named_uint("100 settlements - creation gas per settlement", creationGas / 100);
        emit log_named_uint("100 settlements - completion gas total", completionGas);
        emit log_named_uint("100 settlements - completion gas per settlement", completionGas / 100);

        assertLt(creationGas, 100_000_000, "Creation gas too high");
    }

    function test_load_500_settlements() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        token.mint(settlementRelayer, 500 * 5e6);
        
        vm.prank(settlementRelayer);
        token.approve(address(hook), type(uint256).max);

        uint256 startGas = gasleft();
        
        for (uint256 i = 0; i < 500; i++) {
            uint256 signerPk = 0xA11CE + (i % 50);
            bytes32 settlementId = _createSettlement(poolId, 2000 + i, signerPk);
            
            // Verify creation
            assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
            
            // Periodic completion
            if (i % 100 == 99) {
                vm.prank(settlementRelayer);
                hook.completeSettlement(settlementId);
            }
        }

        uint256 gasUsed = startGas - gasleft();
        emit log_named_uint("500 settlements - total gas", gasUsed);
        emit log_named_uint("500 settlements - avg gas per settlement", gasUsed / 500);

        assertLt(gasUsed, 500_000_000, "Gas too high for 500 settlements");
    }

    function test_load_1000_settlements() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        token.mint(settlementRelayer, 1000 * 5e6);
        
        vm.prank(settlementRelayer);
        token.approve(address(hook), type(uint256).max);

        uint256 createdCount = 0;
        uint256 startGas = gasleft();

        for (uint256 i = 0; i < 1000; i++) {
            uint256 signerPk = 0xA11CE + (i % 100);
            
            try this._createSettlementExternal(poolId, 3000 + i, signerPk) returns (bytes32 settlementId) {
                createdCount++;
                assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
            } catch {
                // Settlement creation failed, track but continue
            }
        }

        uint256 gasUsed = startGas - gasleft();
        emit log_named_uint("1000 settlements - created count", createdCount);
        emit log_named_uint("1000 settlements - total gas", gasUsed);
        if (createdCount > 0) {
            emit log_named_uint("1000 settlements - avg gas per settlement", gasUsed / createdCount);
        }

        assertGe(createdCount, 950, "Less than 95% of settlements created");
        assertLt(gasUsed, 1_000_000_000, "Gas too high for 1000 settlements");
    }

    function test_load_5000_settlements() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        token.mint(settlementRelayer, 5000 * 5e6);
        
        vm.prank(settlementRelayer);
        token.approve(address(hook), type(uint256).max);

        uint256 createdCount = 0;
        uint256 startGas = gasleft();

        for (uint256 i = 0; i < 5000; i++) {
            uint256 signerPk = 0xA11CE + (i % 200);
            
            try this._createSettlementExternal(poolId, 4000 + i, signerPk) returns (bytes32 settlementId) {
                createdCount++;
                
                // Verify settlement is pending
                if (i % 1000 == 999) {
                    assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
                }
            } catch {
                // Continue on failure
            }
        }

        uint256 gasUsed = startGas - gasleft();
        emit log_named_uint("5000 settlements - created count", createdCount);
        emit log_named_uint("5000 settlements - total gas", gasUsed);
        if (createdCount > 0) {
            emit log_named_uint("5000 settlements - avg gas per settlement", gasUsed / createdCount);
        }

        assertGe(createdCount, 4000, "Less than 80% of settlements created");
    }

    function test_duplicate_settlement_detection() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        uint256 signerPk = 0xA11CE;
        
        // Create first settlement
        bytes32 id1 = _createSettlement(poolId, 5000, signerPk);
        assertEq(uint8(hook.settlementStatus(id1)), uint8(StateEngine.SettlementStatus.Pending));
        
        // Attempt to create with same nonce/signer (should fail)
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);
        SignatureEngine.LossPayload memory payload = _buildPayload(poolId, 5000, signer);
        
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            hook.exposeDomainSeparator(),
            hook.exposeHashPayload(payload)
        ));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        
        // This should revert because nonce already used
        vm.expectRevert();
        hook.submitRiskPayload(testKey, payload, signature);
    }

    function test_settlement_state_integrity() public {
        bytes32 poolId = keccak256(abi.encode(testKey.toId()));
        uint256 signerPk = 0xA11CE;
        
        bytes32 settlementId = _createSettlement(poolId, 6000, signerPk);
        
        // Verify state before completion
        (uint256 amount, uint32 domain, address token_, ) = hook.settlements(settlementId);
        assertEq(amount, 5e6);
        assertEq(domain, 3);
        assertEq(token_, address(token));
        
        // Complete settlement
        token.mint(settlementRelayer, 5e6);
        vm.prank(settlementRelayer);
        token.approve(address(hook), 5e6);
        
        vm.prank(settlementRelayer);
        hook.completeSettlement(settlementId);
        
        // Verify state after completion
        (, , , bool settled) = hook.settlements(settlementId);
        assertTrue(settled);
        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Completed));
    }

    function _createSettlementExternal(bytes32 poolId, uint256 nonce, uint256 signerPk) external returns (bytes32) {
        return _createSettlement(poolId, nonce, signerPk);
    }
}

