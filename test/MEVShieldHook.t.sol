// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, stdJson} from "forge-std/Test.sol";
import {MEVShieldHook} from "../src/MEVShieldHook.sol";
import {SignatureEngine} from "../src/SignatureEngine.sol";
import {RiskEngine} from "../src/RiskEngine.sol";
import {StateEngine} from "../src/StateEngine.sol";
import {ExecutionCoordinator} from "../src/ExecutionCoordinator.sol";
import {SettlementCoordinator} from "../src/SettlementCoordinator.sol";
import {EventPublisher} from "../src/EventPublisher.sol";
import {BaseHook} from "v4-hooks-public/lib/briefcase/src/protocols/v4-periphery/utils/BaseHook.sol";
import {PoolKey} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolKey.sol";
import {Currency} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/Currency.sol";
import {SwapParams} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolOperation.sol";
import {BeforeSwapDelta} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/libraries/LPFeeLibrary.sol";
import {IHooks} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/interfaces/IHooks.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockPoolManager {
    // forge-lint: disable-next-line(mixed-case-function)
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

    function exposeClassifyLoss(uint256 expectedLoss) public pure returns (uint24) {
        return classifyLoss(expectedLoss);
    }

    function exposeResolveFeeOverride(uint24 recommendedSpread) public pure returns (uint24) {
        return resolveFeeOverride(recommendedSpread);
    }

    function exposeSetTrustedSigner(address signer, bool trusted) external {
        this.setTrustedSigner(signer, trusted);
    }

    function exposeSetQuorumThreshold(uint256 threshold) external {
        this.setQuorumThreshold(threshold);
    }

    function exposeSetRiskPolicy(
        uint256 maxExpectedLpLoss,
        uint256 maxExpectedLeakage,
        uint256 maxToxicityScore,
        uint24 maxRecommendedSpread,
        bool rejectOnThreshold
    ) external {
        this.setRiskPolicy(maxExpectedLpLoss, maxExpectedLeakage, maxToxicityScore, maxRecommendedSpread, rejectOnThreshold);
    }

    function exposeSetSettlementRelayer(address relayer) external {
        this.setSettlementRelayer(relayer);
    }

    function exposeSetExecutionCoordinator(address _coordinator) external {
        this.setExecutionCoordinator(_coordinator);
    }

    function exposeSetOracleAvailability(bool available) external {
        this.setOracleAvailability(available);
    }

    function exposeCompleteSettlement(bytes32 settlementId) external {
        this.completeSettlement(settlementId);
    }

    function exposeDomainSeparator() public view returns (bytes32) {
        return _domainSeparator();
    }

    function exposeHashPayload(SignatureEngine.LossPayload memory payload) public pure returns (bytes32) {
        return _hashPayload(payload);
    }

    function exposeProcessPayload(PoolKey calldata key, SignatureEngine.LossPayload calldata payload, bytes calldata signature) external {
        Attestation[] memory attestations = new Attestation[](1);
        attestations[0] = Attestation({operator: payload.signer, signature: signature});
        _verifyPayload(key, payload, attestations);
        poolLoss[payload.poolId] = PoolLossState({
            expectedLpLoss: payload.expectedLpLoss,
            expectedLeakage: payload.expectedLeakage,
            toxicityScore: payload.toxicityScore,
            spread: payload.recommendedSpread,
            updatedAt: block.timestamp
        });
    }

    function exposeProcessPayload(PoolKey calldata key, SignatureEngine.LossPayload calldata payload, SignatureEngine.Attestation[] calldata attestations) external {
        _verifyPayload(key, payload, attestations);
        poolLoss[payload.poolId] = PoolLossState({
            expectedLpLoss: payload.expectedLpLoss,
            expectedLeakage: payload.expectedLeakage,
            toxicityScore: payload.toxicityScore,
            spread: payload.recommendedSpread,
            updatedAt: block.timestamp
        });
    }

    function exposeBeforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return _beforeSwap(sender, key, params, hookData);
    }

    function exposeCoordinateSubmission(
        PoolKey calldata key,
        SignatureEngine.LossPayload calldata payload,
        SignatureEngine.Attestation[] calldata attestations
    ) external returns (bytes32) {
        return ExecutionCoordinator(executionCoordinator).coordinateSubmission(key, payload, attestations);
    }
}

contract MEVShieldHookTest is Test {
    using stdJson for string;

    MEVShieldHookHarness public hook;
    ExecutionCoordinator public coordinator;
    MockERC20 public usdc;

    function setUp() public {
        MockPoolManager poolManager = new MockPoolManager();
        usdc = new MockERC20();
        hook = new MEVShieldHookHarness(address(poolManager), address(usdc));
        coordinator = new ExecutionCoordinator(address(hook));
        hook.exposeSetExecutionCoordinator(address(coordinator));
    }

    function _buildPayload(
        bytes32 poolId,
        uint256 expectedLpLoss,
        uint256 expectedLeakage,
        uint256 toxicityScore,
        uint24 recommendedSpread,
        uint256 expiry,
        uint256 nonce,
        address signer
    ) internal view returns (SignatureEngine.LossPayload memory payload) {
        payload.poolId = poolId;
        payload.expectedLpLoss = expectedLpLoss;
        payload.expectedLeakage = expectedLeakage;
        payload.toxicityScore = toxicityScore;
        payload.recommendedSpread = recommendedSpread;
        payload.settlementToken = hook.USDC();
        payload.settlementAmount = 5e6;
        payload.destinationDomain = 3;
        payload.recipient = bytes32(uint256(0x4444));
        payload.expiry = expiry;
        payload.nonce = nonce;
        payload.signer = signer;
    }

    function test_classifyLossReturnsExpectedTieredOverrides() public view {
        assertEq(hook.exposeClassifyLoss(1e18), 300);
        assertEq(hook.exposeClassifyLoss(5e18), 1000);
        assertEq(hook.exposeClassifyLoss(20e18), 3000);
        assertEq(hook.exposeClassifyLoss(100e18), 10000);
    }

    function test_nonUsdcSettlementTokenIsRejected() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetExecutionCoordinator(address(coordinator));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            101,
            signer
        );
        payload.settlementToken = address(0x9999);

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert();
        hook.submitRiskPayload(key, payload, signature);
    }

    function test_resolveFeeOverrideUsesRecommendedSpread() public view {
        assertEq(hook.exposeResolveFeeOverride(8000), 8000);
    }

    function test_quorumAttestationsAreAcceptedWhenThresholdIsMet() public {
        uint256 signerPk1 = 0xA11CE;
        uint256 signerPk2 = 0xBEEF;
        address signer1 = vm.addr(signerPk1);
        address signer2 = vm.addr(signerPk2);
        hook.exposeSetQuorumThreshold(2);
        hook.exposeSetTrustedSigner(signer1, true);
        hook.exposeSetTrustedSigner(signer2, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            7,
            signer1
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerPk1, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerPk2, digest);

        SignatureEngine.Attestation[] memory attestations = new SignatureEngine.Attestation[](2);
        attestations[0] = SignatureEngine.Attestation({operator: signer1, signature: abi.encodePacked(r1, s1, v1)});
        attestations[1] = SignatureEngine.Attestation({operator: signer2, signature: abi.encodePacked(r2, s2, v2)});

        vm.expectEmit(true, true, true, true);
        emit EventPublisher.PriceVerified(poolId, signer1, payload.nonce);

        hook.exposeProcessPayload(key, payload, attestations);

        (uint256 expectedLpLoss, uint256 expectedLeakage, uint256 toxicityScore, uint24 spread, uint256 updatedAt) = hook.poolLoss(poolId);
        assertEq(expectedLpLoss, 1e18);
        assertEq(expectedLeakage, 2e17);
        assertEq(toxicityScore, 75);
        assertEq(spread, 1200);
        assertGt(updatedAt, 0);
    }

    function test_riskPolicyRejectsHighRiskPayload() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetRiskPolicy(5e17, 2e17, 50, 20000, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            13,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory hookData = abi.encode(payload, signature);

        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskThresholdExceeded.selector));
        hook.exposeBeforeSwap(address(this), key, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), hookData);
    }

    function test_executionCoordinatorRejectsRiskPolicyFailures() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetRiskPolicy(5e17, 2e17, 50, 20000, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            97,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        SignatureEngine.Attestation[] memory attestations = new SignatureEngine.Attestation[](1);
        attestations[0] = SignatureEngine.Attestation({operator: signer, signature: abi.encodePacked(r, s, v)});

        vm.expectEmit(true, true, false, true, address(coordinator));
        emit EventPublisher.ExecutionRejected(payload.poolId, signer, "risk policy failed");

        vm.expectRevert(abi.encodeWithSelector(RiskEngine.RiskThresholdExceeded.selector));
        hook.exposeCoordinateSubmission(key, payload, attestations);
    }

    function test_oracleUnavailableRejectsExecution() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetOracleAvailability(false);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            101,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.OracleUnavailable.selector));
        hook.submitRiskPayload(key, payload, signature);
    }

    function test_expiredOrderIsRejected() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp - 1,
            102,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.ExpiredPayload.selector));
        hook.submitRiskPayload(key, payload, signature);
    }

    function test_wrongSignatureIsRejected() public {
        uint256 signerPk = 0xA11CE;
        uint256 attackerPk = 0xBEEF;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            103,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.InvalidSignature.selector));
        hook.submitRiskPayload(key, payload, signature);
    }

    function test_wrongNonceIsRejected() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            102,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        payload.nonce = payload.nonce + 1;
        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.InvalidSignature.selector));
        hook.submitRiskPayload(key, payload, signature);
    }

    function test_modifiedPayloadHashMismatchIsRejected() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            107,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        payload.recommendedSpread = 9000;
        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.InvalidSignature.selector));
        hook.submitRiskPayload(key, payload, signature);
    }

    function test_replayAttackIsRejectedOnSecondSubmission() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            106,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        hook.submitRiskPayload(key, payload, signature);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.ReplayDetected.selector));
        hook.submitRiskPayload(key, payload, signature);
    }

    function test_insufficientSettlementBalanceRevertsWithoutPartialExecution() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        address relayer = address(0xBEEF);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetSettlementRelayer(relayer);

        usdc.mint(relayer, 2e6);
        vm.prank(relayer);
        usdc.approve(address(hook), 5e6);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            105,
            signer
        );
        payload.settlementToken = address(usdc);
        payload.settlementAmount = 5e6;
        payload.recipient = bytes32(uint256(uint160(address(0xCAFE))));

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 settlementId = hook.submitRiskPayload(key, payload, signature);

        vm.expectRevert(abi.encodeWithSelector(SettlementCoordinator.TransferFailed.selector));
        vm.prank(relayer);
        hook.completeSettlement(settlementId);

        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
        (, , , bool settled) = hook.settlements(settlementId);
        assertFalse(settled);
    }

    function test_executionCoordinatorApprovesAndAuthorizesSettlement() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            101,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);

        SignatureEngine.Attestation[] memory attestations = new SignatureEngine.Attestation[](1);
        attestations[0] = SignatureEngine.Attestation({operator: signer, signature: abi.encodePacked(r, s, v)});

        bytes32 settlementId = keccak256(abi.encode(payload.poolId, payload.nonce));

        vm.expectEmit(true, true, false, true, address(hook));
        emit EventPublisher.PriceVerified(payload.poolId, signer, payload.nonce);
        vm.expectEmit(true, false, false, true, address(hook));
        emit EventPublisher.SettlementCreated(settlementId, payload.settlementToken, payload.settlementAmount, payload.destinationDomain);
        vm.expectEmit(true, true, true, true, address(hook));
        emit EventPublisher.SettlementAuthorized(
            settlementId,
            address(uint160(uint256(payload.recipient))),
            payload.settlementToken,
            payload.settlementAmount
        );
        vm.expectEmit(true, true, false, true, address(coordinator));
        emit ExecutionCoordinator.ExecutionDecision(
            settlementId,
            payload.poolId,
            signer,
            payload.recommendedSpread,
            payload.recommendedSpread,
            true
        );

        bytes32 actualSettlementId = hook.exposeCoordinateSubmission(key, payload, attestations);

        assertEq(actualSettlementId, settlementId);
        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));

        (uint256 settledAmount, uint32 destinationDomain, address token, bool settled) = hook.settlements(settlementId);
        assertEq(settledAmount, payload.settlementAmount);
        assertEq(destinationDomain, payload.destinationDomain);
        assertEq(token, payload.settlementToken);
        assertFalse(settled);

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(poolId);
        assertEq(actualLpLoss, 1e18);
        assertEq(actualLeakage, 2e17);
        assertEq(actualToxicity, 75);
        assertEq(actualSpread, 1200);
        assertGt(actualUpdatedAt, 0);
    }

    function test_completeSettlementMarksSettlementCompleted() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetSettlementRelayer(address(hook));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        usdc.mint(address(hook), 10e6);
        vm.prank(address(hook));
        usdc.approve(address(hook), 10e6);

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            99,
            signer
        );
        payload.settlementToken = address(usdc);
        payload.settlementAmount = 5e6;
        payload.recipient = bytes32(uint256(uint160(address(0xBEEF))));

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 settlementId = hook.submitRiskPayload(key, payload, signature);
        hook.exposeCompleteSettlement(settlementId);

        assertTrue(hook.settlementStatus(settlementId) == StateEngine.SettlementStatus.Completed);
        (, , , bool settled) = hook.settlements(settlementId);
        assertTrue(settled);
        assertEq(usdc.balanceOf(address(hook)), 5e6);
        assertEq(usdc.balanceOf(address(0xBEEF)), 5e6);
    }

    function test_integrationFlowExecutesSettlementAndTransfersTokens() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        address trader = address(0xBEEF);
        address receiver = address(0xCAFE);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetSettlementRelayer(trader);

        usdc.mint(trader, 10e6);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            111,
            signer
        );
        payload.settlementToken = address(usdc);
        payload.settlementAmount = 5e6;
        payload.recipient = bytes32(uint256(uint160(receiver)));

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(trader);
        usdc.approve(address(hook), payload.settlementAmount);

        vm.expectEmit(true, true, true, true, address(hook));
        emit EventPublisher.SettlementAuthorized(
            keccak256(abi.encode(payload.poolId, payload.nonce)),
            address(uint160(uint256(payload.recipient))),
            payload.settlementToken,
            payload.settlementAmount
        );

        uint256 submitGasBefore = gasleft();
        bytes32 settlementId = hook.submitRiskPayload(key, payload, signature);

        vm.expectEmit(true, true, false, true, address(hook));
        emit EventPublisher.SettlementExecuted(settlementId, trader);

        vm.expectEmit(true, true, false, true, address(hook));
        emit EventPublisher.FundsTransferred(settlementId, payload.settlementToken, payload.settlementAmount, payload.recipient);
        uint256 submitGasUsed = submitGasBefore - gasleft();
        assertLt(submitGasUsed, 500000);

        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
        assertEq(hook.settlementRecipients(settlementId), payload.recipient);

        vm.expectEmit(true, false, false, true, address(hook));
        emit EventPublisher.SettlementCompleted(settlementId, payload.settlementAmount);

        uint256 completeGasBefore = gasleft();
        vm.prank(trader);
        hook.completeSettlement(settlementId);
        uint256 completeGasUsed = completeGasBefore - gasleft();
        assertLt(completeGasUsed, 300000);

        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Completed));
        assertEq(usdc.balanceOf(trader), 5e6);
        assertEq(usdc.balanceOf(receiver), 5e6);
        (, , address tokenAddress, bool settled) = hook.settlements(settlementId);
        assertEq(tokenAddress, address(usdc));
        assertTrue(settled);
    }

    function test_completeSettlementRejectsUnauthorizedOrInvalidInputs() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        address attacker = address(0xDAD);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetSettlementRelayer(attacker);

        usdc.mint(attacker, 10e6);
        vm.prank(attacker);
        usdc.approve(address(hook), 10e6);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            112,
            signer
        );
        payload.settlementToken = address(usdc);
        payload.settlementAmount = 5e6;
        payload.recipient = bytes32(uint256(uint160(address(0xBEEF))));

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 settlementId = hook.submitRiskPayload(key, payload, signature);

        vm.expectRevert(abi.encodeWithSelector(SettlementCoordinator.UnauthorizedSettlementExecutor.selector));
        vm.prank(address(0xDEAD));
        hook.completeSettlement(settlementId);

        vm.expectRevert(abi.encodeWithSelector(SettlementCoordinator.InvalidRecipient.selector));
        vm.prank(attacker);
        hook.completeSettlement(bytes32(uint256(0x999)));
    }

    function test_endToEndUserSwapFlowSignsIntentSubmitsAndSettles() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        address bundler = address(0xB0B);
        address receiver = address(0xBEEF);
        address alice = address(0xC0FFEE);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetSettlementRelayer(alice);

        usdc.mint(alice, 1000e6);
        vm.prank(alice);
        usdc.approve(address(hook), 1000e6);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 5 minutes,
            200,
            signer
        );
        payload.settlementToken = hook.USDC();
        payload.settlementAmount = 1000e6;
        payload.recipient = bytes32(uint256(uint160(receiver)));

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 settlementId = keccak256(abi.encode(payload.poolId, payload.nonce));

        vm.expectEmit(true, false, false, true);
        emit EventPublisher.LossProtectionApplied(poolId, 1e18, 2e17, 75, 1200);

        vm.expectEmit(true, true, true, true);
        emit EventPublisher.SettlementAuthorized(
            settlementId,
            address(uint160(uint256(payload.recipient))),
            payload.settlementToken,
            payload.settlementAmount
        );

        uint256 submitGasBefore = gasleft();
        vm.prank(bundler);
        bytes32 submittedSettlementId = hook.submitRiskPayload(key, payload, signature);
        uint256 submitGasUsed = submitGasBefore - gasleft();
        assertEq(submittedSettlementId, settlementId);
        assertLt(submitGasUsed, 600000);

        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
        assertEq(hook.settlementRecipients(settlementId), payload.recipient);
        assertEq(hook.lastFee(key.toId()), 1200);

        SignatureEngine.LossPayload memory swapPayload = payload;
        swapPayload.nonce = 201;
        swapPayload.expiry = block.timestamp + 5 minutes;
        bytes32 swapPayloadHash = hook.exposeHashPayload(swapPayload);
        bytes32 swapDigest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), swapPayloadHash));
        (uint8 swapV, bytes32 swapR, bytes32 swapS) = vm.sign(signerPk, swapDigest);
        bytes memory swapSignature = abi.encodePacked(swapR, swapS, swapV);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1000e6,
            sqrtPriceLimitX96: 0
        });
        bytes memory hookData = abi.encode(swapPayload, swapSignature);

        uint256 swapGasBefore = gasleft();
        (bytes4 selector, , uint24 feeOverride) = hook.exposeBeforeSwap(bundler, key, params, hookData);
        uint256 swapGasUsed = swapGasBefore - gasleft();
        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(feeOverride, uint24(1200 | LPFeeLibrary.OVERRIDE_FEE_FLAG));
        assertLt(swapGasUsed, 500000);

        assertEq(hook.lastFee(key.toId()), 1200);
        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(poolId);
        assertEq(actualLpLoss, 1e18);
        assertEq(actualLeakage, 2e17);
        assertEq(actualToxicity, 75);
        assertEq(actualSpread, 1200);
        assertGt(actualUpdatedAt, 0);

        bytes32 swapSettlementId = keccak256(abi.encode(swapPayload.poolId, swapPayload.nonce));
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 receiverBalanceBefore = usdc.balanceOf(receiver);

        vm.expectEmit(true, false, false, true);
        emit EventPublisher.SettlementCompleted(swapSettlementId, payload.settlementAmount);

        uint256 completeGasBefore = gasleft();
        vm.prank(alice);
        hook.completeSettlement(swapSettlementId);
        uint256 completeGasUsed = completeGasBefore - gasleft();
        assertLt(completeGasUsed, 300000);

        assertEq(uint8(hook.settlementStatus(swapSettlementId)), uint8(StateEngine.SettlementStatus.Completed));
        assertEq(usdc.balanceOf(alice), aliceBalanceBefore - payload.settlementAmount);
        assertEq(usdc.balanceOf(receiver), receiverBalanceBefore + payload.settlementAmount);
        (, , address settledToken, bool settled) = hook.settlements(swapSettlementId);
        assertEq(settledToken, address(usdc));
        assertTrue(settled);
    }

    function test_riskPolicyConstrainsFeeWhenThresholdIsExceeded() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetRiskPolicy(5e17, 2e17, 50, 1000, false);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            14,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory hookData = abi.encode(payload, signature);

        (, , uint24 feeOverride) = hook.exposeBeforeSwap(address(this), key, SwapParams({zeroForOne: true, amountSpecified: 1e18, sqrtPriceLimitX96: 0}), hookData);

        assertEq(feeOverride, 1000);
    }

    function test_signedPayloadIsAcceptedAndStored() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            7,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        hook.exposeProcessPayload(key, payload, signature);

        (uint256 expectedLpLoss, uint256 expectedLeakage, uint256 toxicityScore, uint24 spread, uint256 updatedAt) = hook.poolLoss(poolId);
        assertEq(expectedLpLoss, 1e18);
        assertEq(expectedLeakage, 2e17);
        assertEq(toxicityScore, 75);
        assertEq(spread, 1200);
        assertGt(updatedAt, 0);
    }

    function test_beforeSwapIntegrationAppliesVerifiedPayload() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            7,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory hookData = abi.encode(payload, signature);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });

        (bytes4 selector, , uint24 feeOverride) = hook.exposeBeforeSwap(address(this), key, params, hookData);

        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(feeOverride, 1200);

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(poolId);
        assertEq(actualLpLoss, 1e18);
        assertEq(actualLeakage, 2e17);
        assertEq(actualToxicity, 75);
        assertEq(actualSpread, 1200);
        assertGt(actualUpdatedAt, 0);
    }

    function test_hookLifecycleBeforeSwapAuthorizesSettlementAndCompletesWithoutRevert() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        address trader = address(0xBEEF);
        address receiver = address(0xCAFE);
        hook.exposeSetTrustedSigner(signer, true);
        hook.exposeSetSettlementRelayer(trader);

        usdc.mint(trader, 10e6);
        vm.prank(trader);
        usdc.approve(address(hook), 10e6);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            123,
            signer
        );
        payload.settlementToken = address(usdc);
        payload.settlementAmount = 5e6;
        payload.recipient = bytes32(uint256(uint160(receiver)));

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory hookData = abi.encode(payload, signature);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });

        bytes32 settlementId = keccak256(abi.encode(payload.poolId, payload.nonce));

        vm.expectEmit(true, true, true, true);
        emit EventPublisher.SettlementAuthorized(
            settlementId,
            address(uint160(uint256(payload.recipient))),
            payload.settlementToken,
            payload.settlementAmount
        );

        (bytes4 selector, , uint24 feeOverride) = hook.exposeBeforeSwap(address(this), key, params, hookData);

        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(feeOverride, 1200);
        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
        assertEq(hook.settlementRecipients(settlementId), payload.recipient);

        vm.expectEmit(true, false, false, true);
        emit EventPublisher.SettlementCompleted(settlementId, payload.settlementAmount);

        vm.prank(trader);
        hook.completeSettlement(settlementId);

        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Completed));
        (, , , bool settled) = hook.settlements(settlementId);
        assertTrue(settled);
        assertEq(usdc.balanceOf(trader), 5e6);
        assertEq(usdc.balanceOf(receiver), 5e6);
        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(poolId);
        assertEq(actualLpLoss, payload.expectedLpLoss);
        assertEq(actualLeakage, payload.expectedLeakage);
        assertEq(actualToxicity, payload.toxicityScore);
        assertEq(actualSpread, payload.recommendedSpread);
        assertGt(actualUpdatedAt, 0);
    }

    function test_submitRiskPayloadAuthorizesSettlement() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            11,
            signer
        );
        payload.settlementAmount = 0;

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 settlementId = hook.submitRiskPayload(key, payload, signature);

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(poolId);
        assertEq(actualLpLoss, 1e18);
        assertEq(actualLeakage, 2e17);
        assertEq(actualToxicity, 75);
        assertEq(actualSpread, 1200);
        assertGt(actualUpdatedAt, 0);

        (uint256 settledAmount, uint32 destinationDomain, address token, bool settled) = hook.settlements(settlementId);
        assertEq(settledAmount, payload.settlementAmount);
        assertEq(destinationDomain, payload.destinationDomain);
        assertEq(token, payload.settlementToken);
        assertEq(settled, false);
        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
    }

    function test_submitRiskPayloadDoesNotTransferSettlementTokens() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        usdc.mint(address(hook), 10e6);

        hook.exposeSetSettlementRelayer(address(0xF00D));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            17,
            signer
        );
        payload.settlementToken = address(usdc);
        payload.settlementAmount = 5e6;
        payload.recipient = bytes32(uint256(uint160(address(0xBEEF))));

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 settlementId = hook.submitRiskPayload(key, payload, signature);

        assertEq(usdc.balanceOf(address(0xF00D)), 0);
        assertEq(usdc.balanceOf(address(hook)), 10e6);
        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
    }

    function test_beforeSwapDynamicFeeOverrideReturnsFlaggedFee() public {
        uint256 signerPk = 0xA11CE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            75,
            1200,
            block.timestamp + 1 hours,
            7,
            signer
        );
        payload.settlementToken = hook.USDC();
        payload.settlementAmount = 5e6;
        payload.destinationDomain = 3;
        payload.recipient = bytes32(uint256(0x4444));

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        bytes memory hookData = abi.encode(payload, signature);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });

        vm.expectEmit(true, true, true, true);
        emit EventPublisher.SettlementAuthorized(
            keccak256(abi.encode(payload.poolId, payload.nonce)),
            address(uint160(uint256(payload.recipient))),
            payload.settlementToken,
            payload.settlementAmount
        );

        (bytes4 selector, , uint24 feeOverride) = hook.exposeBeforeSwap(address(this), key, params, hookData);

        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(feeOverride, uint24(1200 | LPFeeLibrary.OVERRIDE_FEE_FLAG));

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(poolId);
        assertEq(actualLpLoss, 1e18);
        assertEq(actualLeakage, 2e17);
        assertEq(actualToxicity, 75);
        assertEq(actualSpread, 1200);
        assertGt(actualUpdatedAt, 0);

        bytes32 settlementId = keccak256(abi.encode(payload.poolId, payload.nonce));
        (uint256 settledAmount, uint32 destinationDomain, address token, bool settled) = hook.settlements(settlementId);
        assertEq(settledAmount, payload.settlementAmount);
        assertEq(destinationDomain, payload.destinationDomain);
        assertEq(token, payload.settlementToken);
        assertEq(settled, false);
        assertEq(uint8(hook.settlementStatus(settlementId)), uint8(StateEngine.SettlementStatus.Pending));
    }

    function test_fullBackendSignedPayloadIntegration() public {
        uint256 signerPk = 0x1111111111111111111111111111111111111111111111111111111111111111;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        string[] memory ffiArgs = new string[](3);
        ffiArgs[0] = "bash";
        ffiArgs[1] = "-lc";
        ffiArgs[2] = string.concat(
            "cd ", vm.projectRoot(), "/babackend && ",
            "PRIVATE_KEY=0x1111111111111111111111111111111111111111111111111111111111111111 ",
            "VERIFYING_CONTRACT=", vm.toString(address(hook)), " ",
            "CHAIN_ID=", vm.toString(block.chainid), " npx tsx src/scripts/generateSignedPayloadJson.ts"
        );

        // forge-lint: disable-next-line(unsafe-cheatcode)
        bytes memory rawResult = vm.ffi(ffiArgs);
        string memory jsonResult = string(rawResult);

        bytes32 poolId = jsonResult.readBytes32(".payload.poolId");
        uint256 expectedLpLoss = jsonResult.readUint(".payload.expectedLpLoss");
        uint256 expectedLeakage = jsonResult.readUint(".payload.expectedLeakage");
        uint256 toxicityScore = jsonResult.readUint(".payload.toxicityScore");
        uint24 recommendedSpread = uint24(jsonResult.readUint(".payload.recommendedSpread"));
        address settlementToken = jsonResult.readAddress(".payload.settlementToken");
        uint256 settlementAmount = jsonResult.readUint(".payload.settlementAmount");
        uint32 destinationDomain = uint32(jsonResult.readUint(".payload.destinationDomain"));
        bytes32 recipient = jsonResult.readBytes32(".payload.recipient");
        uint256 expiry = jsonResult.readUint(".payload.expiry");
        uint256 nonce = jsonResult.readUint(".payload.nonce");
        address payloadSigner = jsonResult.readAddress(".payload.signer");
        bytes memory signature = jsonResult.readBytes(".signature");

        assertEq(payloadSigner, signer);
        assertEq(poolId, keccak256(abi.encode(key.toId())));

        SignatureEngine.LossPayload memory payload = SignatureEngine.LossPayload({
            poolId: poolId,
            expectedLpLoss: expectedLpLoss,
            expectedLeakage: expectedLeakage,
            toxicityScore: toxicityScore,
            recommendedSpread: recommendedSpread,
            settlementToken: settlementToken,
            settlementAmount: settlementAmount,
            destinationDomain: destinationDomain,
            recipient: recipient,
            expiry: expiry,
            nonce: nonce,
            signer: payloadSigner
        });

        hook.exposeProcessPayload(key, payload, signature);

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(poolId);
        assertEq(actualLpLoss, expectedLpLoss);
        assertEq(actualLeakage, expectedLeakage);
        assertEq(actualToxicity, toxicityScore);
        assertEq(actualSpread, recommendedSpread);
        assertGt(actualUpdatedAt, 0);
    }

    function test_fuzz_signedPayloadIsAccepted(
        uint256 signerPk,
        uint256 expectedLpLoss,
        uint256 expectedLeakage,
        uint256 toxicityScore,
        uint24 recommendedSpread,
        uint256 expiryDelay,
        uint256 nonce
    ) public {
        vm.assume(signerPk != 0);
        vm.assume(signerPk < 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141);
        vm.assume(toxicityScore <= 100);
        vm.assume(expectedLpLoss < 1e25);
        vm.assume(expectedLeakage < 1e25);
        vm.assume(expiryDelay < 1 days);

        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            expectedLpLoss,
            expectedLeakage,
            toxicityScore,
            recommendedSpread % 20001,
            block.timestamp + 1 + expiryDelay,
            nonce,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        hook.exposeProcessPayload(key, payload, signature);

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(poolId);
        assertEq(actualLpLoss, expectedLpLoss);
        assertEq(actualLeakage, expectedLeakage);
        assertEq(actualToxicity, toxicityScore);
        assertEq(actualSpread, payload.recommendedSpread);
        assertGt(actualUpdatedAt, 0);
    }

    function test_variant_expiredPayloadReverts() public {
        uint256 signerPk = 0xDEAD;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        uint256 expiry = block.timestamp + 1;
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            50,
            1200,
            expiry,
            1,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.warp(expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.ExpiredPayload.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_untrustedSignerReverts() public {
        uint256 signerPk = 0xBEEFBEEF;
        address signer = vm.addr(signerPk);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            50,
            1200,
            block.timestamp + 1 hours,
            1,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.UntrustedSigner.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_setTrustedSignerRevertsWhenCallerIsNotMultisig() public {
        address signer = vm.addr(0xCAFE);
        vm.prank(address(0xBEEF));
        vm.expectRevert(SignatureEngine.UnauthorizedSignatureEngine.selector);
        hook.setTrustedSigner(signer, true);
    }

    function test_variant_setTrustedSignerAllowsMultisig() public {
        address signer = vm.addr(0xCAFE);

        hook.exposeSetTrustedSigner(signer, true);

        assertTrue(hook.isTrustedSigner(signer));
    }

    function test_variant_invalidSignatureReverts() public {
        uint256 signerPk = 0xCAFE;
        uint256 attackerPk = 0xBADA55;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            50,
            1200,
            block.timestamp + 1 hours,
            1,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.InvalidSignature.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_invalidSignatureLengthReverts() public {
        uint256 signerPk = 0xCAFE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            50,
            1200,
            block.timestamp + 1 hours,
            1,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.InvalidSignature.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_invalidSignatureBadVReverts() public {
        uint256 signerPk = 0xCAFE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            50,
            1200,
            block.timestamp + 1 hours,
            1,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, uint8(0));

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.InvalidSignature.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_invalidPayloadRevertsWhenRecommendedSpreadExceedsMaxFee() public {
        uint256 signerPk = 0xCAFE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            50,
            20001,
            block.timestamp + 1 hours,
            1,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.InvalidPayload.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_invalidPayloadRevertsWithMismatchedPoolId() public {
        uint256 signerPk = 0xCAFE;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(address(0x1234)));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            50,
            1200,
            block.timestamp + 1 hours,
            1,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.InvalidPayload.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_untrustedSignerRevertsWhenSignerIsZeroAddress() public {
        uint256 signerPk = 0xCAFE;
        SignatureEngine.LossPayload memory payload = _buildPayload(
            keccak256(abi.encode(address(0x1234))),
            1e18,
            2e17,
            50,
            1200,
            block.timestamp + 1 hours,
            1,
            address(0)
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.InvalidPayload.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_replayProtectionRejectsDuplicateNonce() public {
        uint256 signerPk = 0xD15EA5E;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            50,
            1200,
            block.timestamp + 1 hours,
            1,
            signer
        );

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        hook.exposeProcessPayload(key, payload, signature);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.ReplayDetected.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_replayProtectionRejectsDifferentPayloadSameNonce() public {
        uint256 signerPk = 0xD15EA5E;
        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x0000000000000000000000000000000000001000)),
            currency1: Currency.wrap(address(0x0000000000000000000000000000000000002000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory firstPayload = _buildPayload(
            poolId,
            1e18,
            2e17,
            50,
            1200,
            block.timestamp + 1 hours,
            1,
            signer
        );

        bytes32 firstHash = hook.exposeHashPayload(firstPayload);
        bytes32 firstDigest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), firstHash));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerPk, firstDigest);
        bytes memory firstSignature = abi.encodePacked(r1, s1, v1);

        hook.exposeProcessPayload(key, firstPayload, firstSignature);

        SignatureEngine.LossPayload memory secondPayload = _buildPayload(
            poolId,
            2e18,
            3e17,
            60,
            1300,
            block.timestamp + 2 hours,
            1,
            signer
        );

        bytes32 secondHash = hook.exposeHashPayload(secondPayload);
        bytes32 secondDigest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), secondHash));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerPk, secondDigest);
        bytes memory secondSignature = abi.encodePacked(r2, s2, v2);

        vm.expectRevert(abi.encodeWithSelector(SignatureEngine.ReplayDetected.selector));
        hook.exposeProcessPayload(key, secondPayload, secondSignature);
    }
}

contract MEVShieldHookMultiOperatorTest is Test {
    MEVShieldHookHarness public hook;
    MockERC20 public usdc;

    function setUp() public {
        MockPoolManager poolManager = new MockPoolManager();
        usdc = new MockERC20();
        hook = new MEVShieldHookHarness(address(poolManager), address(usdc));
        // Do NOT override quorumThreshold here — use the contract default (now 2)
    }

    function _buildPayload(
        bytes32 poolId,
        uint256 expectedLpLoss,
        uint256 expectedLeakage,
        uint256 toxicityScore,
        uint24 recommendedSpread,
        uint256 expiry,
        uint256 nonce,
        address signer
    ) internal view returns (SignatureEngine.LossPayload memory payload) {
        payload.poolId = poolId;
        payload.expectedLpLoss = expectedLpLoss;
        payload.expectedLeakage = expectedLeakage;
        payload.toxicityScore = toxicityScore;
        payload.recommendedSpread = recommendedSpread;
        payload.settlementToken = hook.USDC();
        payload.settlementAmount = 5e6;
        payload.destinationDomain = 3;
        payload.recipient = bytes32(uint256(0x4444));
        payload.expiry = expiry;
        payload.nonce = nonce;
        payload.signer = signer;
    }

    function test_multiOperatorAttestationsAreAccepted() public {
        uint256 signerPk1 = 0xC0FFEE;
        uint256 signerPk2 = 0xBADDCAFE;
        address signer1 = vm.addr(signerPk1);
        address signer2 = vm.addr(signerPk2);

        // Both operators must be trusted and the default quorum is 2, so two attestations are required.
        hook.exposeSetTrustedSigner(signer1, true);
        hook.exposeSetTrustedSigner(signer2, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(key.toId()));
        SignatureEngine.LossPayload memory payload = _buildPayload(
            poolId,
            1e18,
            2e17,
            20,
            800,
            block.timestamp + 1 hours,
            42,
            signer1
        );

        // Build digest and signatures for both operators
        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerPk1, digest);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerPk2, digest);

        SignatureEngine.Attestation[] memory attestations = new SignatureEngine.Attestation[](2);
        attestations[0] = SignatureEngine.Attestation({operator: signer1, signature: abi.encodePacked(r1, s1, v1)});
        attestations[1] = SignatureEngine.Attestation({operator: signer2, signature: abi.encodePacked(r2, s2, v2)});

        // The default quorum is 2, so this should succeed with two distinct operators.
        hook.exposeProcessPayload(key, payload, attestations);

        (uint256 expectedLpLoss, , uint256 toxicityScore, uint24 spread, uint256 updatedAt) = hook.poolLoss(poolId);
        assertEq(expectedLpLoss, 1e18);
        assertEq(toxicityScore, 20);
        assertEq(spread, 800);
        assertGt(updatedAt, 0);
    }
}
