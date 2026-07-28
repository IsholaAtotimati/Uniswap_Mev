// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title MEVShieldHook
 * @notice On-chain enforcement layer for MEV protection via Uniswap v4 hooks.
 
 * This contract:
 * - Receives signed LossPayload from off-chain Loss Engine
 * - Verifies signature, nonce, and expiry for replay protection
 * - Stores loss metadata per pool
 * - Applies dynamic LP spread based on expected LP loss
 * - Enforces spread hysteresis and rate-limiting for efficiency
 *
 * Architecture role: ENFORCEMENT (verify → store → apply)
 * Counterpart: Off-chain Loss Engine (analyze → compute → sign)
 *
 * @dev Spread calculation is entirely off-chain. This contract only applies the
 * recommended spread from the signed LossPayload. All loss modeling (price impact,
 * toxicity, leakage, and expected LP loss) is computed off-chain and verified here.
 */

import {BaseHook} from "v4-hooks-public/lib/briefcase/src/protocols/v4-periphery/utils/BaseHook.sol";
import {Hooks} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/libraries/LPFeeLibrary.sol";
import {PoolId} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolId.sol";
import {IHooks} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/interfaces/IHooks.sol";
import {SwapParams} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolOperation.sol";
import {ExecutionCoordinator} from "./ExecutionCoordinator.sol";
import {SignatureEngine} from "./SignatureEngine.sol";
import {RiskEngine} from "./RiskEngine.sol";
import {FeeEngine} from "./FeeEngine.sol";
import {SettlementCoordinator} from "./SettlementCoordinator.sol";

contract MEVShieldHook is BaseHook, SignatureEngine, RiskEngine, FeeEngine, SettlementCoordinator {
    using LPFeeLibrary for uint24;

    // State tracking
    address public executionCoordinator;
    bool public oracleAvailable = true;

    // Errors
    error ZeroAddress();
    error OracleUnavailable();

    /**
     * @param poolManager_ Uniswap v4 PoolManager address
     * @param multisig Admin multisig for trusted signer management
     */
    constructor(address poolManager_, address multisig, address usdc)
        BaseHook(IPoolManager(poolManager_))
        SignatureEngine(multisig)
        SettlementCoordinator(usdc)
    {
        _initializeRiskPolicy();
    }

    function _multisig() internal view virtual override(RiskEngine, SettlementCoordinator) returns (address) {
        return MULTISIG;
    }

    function _poolManager() internal view virtual override returns (IPoolManager) {
        return poolManager;
    }

    function _executionCoordinator() internal view virtual override returns (address) {
        return executionCoordinator;
    }

    function setExecutionCoordinator(address coordinator) external onlyMultisig {
        if (coordinator == address(0)) revert ZeroAddress();
        executionCoordinator = coordinator;
    }

    function setOracleAvailability(bool available) external onlyMultisig {
        oracleAvailable = available;
    }

    function submitRiskPayload(
        PoolKey calldata key,
        LossPayload calldata payload,
        bytes calldata signature
    ) external returns (bytes32 settlementId) {
        Attestation[] memory attestations = new Attestation[](1);
        attestations[0] = Attestation({operator: payload.signer, signature: signature});
        return submitRiskPayload(key, payload, attestations);
    }

    function submitRiskPayload(
        PoolKey calldata key,
        LossPayload calldata payload,
        Attestation[] memory attestations
    ) public returns (bytes32 settlementId) {
        if (executionCoordinator == address(0)) revert InvalidPayload();
        return ExecutionCoordinator(executionCoordinator).coordinateSubmission(key, payload, attestations);
    }

    function verifyPayload(
        PoolKey calldata key,
        LossPayload calldata payload,
        Attestation[] calldata attestations
    ) external onlyExecutionCoordinator {
        if (!oracleAvailable) revert OracleUnavailable();
        LossPayload memory payloadCopy = payload;
        _verifyPayload(key, payloadCopy, attestations);
    }

    function storeRiskSnapshot(
        bytes32 poolId,
        uint256 expectedLpLoss,
        uint256 expectedLeakage,
        uint256 toxicityScore,
        uint24 spread
    ) external onlyExecutionCoordinator {
        poolLoss[poolId] = PoolLossState({
            expectedLpLoss: expectedLpLoss,
            expectedLeakage: expectedLeakage,
            toxicityScore: toxicityScore,
            spread: spread,
            updatedAt: block.timestamp
        });

        emit LossProtectionApplied(
            poolId,
            expectedLpLoss,
            expectedLeakage,
            toxicityScore,
            spread
        );
    }

    function applyFee(PoolKey calldata key, uint24 fee) external onlyExecutionCoordinator returns (uint24) {
        _updateFee(key, fee);
        return fee;
    }

    function assessRiskPolicy(LossPayload calldata payload)
        external
        view
        returns (bool riskOk, uint24 constrainedSpread)
    {
        bool exceeds =
            payload.expectedLpLoss > maxExpectedLpLoss ||
            payload.expectedLeakage > maxExpectedLeakage ||
            payload.toxicityScore > maxToxicityScore ||
            payload.recommendedSpread > maxRecommendedSpread;

        if (exceeds && rejectOnThreshold) {
            return (false, 0);
        }

        constrainedSpread = payload.recommendedSpread > maxRecommendedSpread
            ? maxRecommendedSpread
            : payload.recommendedSpread;

        return (true, constrainedSpread);
    }

    /**
     * @notice Register which hook entrypoints are called
     * @dev Only beforeSwap is enabled for MEV protection
     */
    function getHookPermissions()
        public
        pure
        virtual
        override
        returns (Hooks.Permissions memory)
    {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /**
     * @notice Internal fee updater with hysteresis and rate-limiting
     * @dev Applies fee changes only when delta exceeds FEE_HYSTERESIS to reduce gas costs
     * @param key Pool key
     * @param fee Recommended fee from RiskPayload (capped at MAX_FEE)
     */

    /**
     * @notice Main hook entrypoint called before every swap
     * @dev Expects calldata encoded as: abi.encode(LossPayload, signature)
     *
     * Flow:
     * 1. Decode LossPayload and signature from calldata
     * 2. Verify signature against trusted signer
     * 3. Check replay protection (nonce + expiry)
     * 4. Store risk data on-chain
     * 5. Apply dynamic fee override
     *
     * @param key Pool key 
     * @param data Encoded LossPayload + signature
     * @return The hook selector
     * @return Zero delta (no token changes)
     * @return Dynamic fee override (or 0 if static fee)
     */
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata,
        bytes calldata data
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        if (!oracleAvailable) revert OracleUnavailable();

        // Decode LossPayload and signature
        (LossPayload memory payload, bytes memory signature) =
            abi.decode(data, (LossPayload, bytes));

        // Verify quorum-backed attestation, nonce, expiry, and trusted signers
        Attestation[] memory attestations = new Attestation[](1);
        attestations[0] = Attestation({operator: payload.signer, signature: signature});
        _verifyPayload(key, payload, attestations);

        uint24 constrainedSpread = evaluateRiskPolicy(payload);

        // Store risk snapshot for off-chain monitoring
        poolLoss[payload.poolId] = PoolLossState({
            expectedLpLoss: payload.expectedLpLoss,
            expectedLeakage: payload.expectedLeakage,
            toxicityScore: payload.toxicityScore,
            spread: payload.recommendedSpread,
            updatedAt: block.timestamp
        });

        emit LossProtectionApplied(
            payload.poolId,
            payload.expectedLpLoss,
            payload.expectedLeakage,
            payload.toxicityScore,
            payload.recommendedSpread
        );

        _authorizeSettlement(
            payload.poolId,
            payload.settlementToken,
            payload.settlementAmount,
            payload.destinationDomain,
            payload.recipient,
            payload.nonce
        );

        // Update cached fee with hysteresis protection
        _updateFee(key, constrainedSpread);

        uint24 feeOverride = resolveFeeOverride(constrainedSpread);

        if (key.fee.isDynamicFee()) {
            feeOverride |= LPFeeLibrary.OVERRIDE_FEE_FLAG;
        }

        bytes4 selector = IHooks.beforeSwap.selector;

        return (
            selector,
            BeforeSwapDeltaLibrary.ZERO_DELTA,
            feeOverride
        );
 }
}   