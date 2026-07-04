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

contract MEVShieldHook is BaseHook{
    using LPFeeLibrary for uint24;
    /**
     * @notice LossPayload signed by off-chain Loss Engine
     * @param poolId The Uniswap v4 pool ID
     * @param expectedLpLoss Estimated LP loss expected from the swap path
     * @param expectedLeakage Predicted MEV value that could be extracted
     * @param toxicityScore 0-100 transaction toxicity (sandwich/MEV indicators)
     * @param recommendedSpread Dynamic LP spread in basis points (0-2% = 0-20000)
     * @param expiry Block timestamp expiration for signature validity
     * @param nonce Replay protection counter per signer
     * @param signer Address of Loss Engine signer (must be trusted)
     */
    struct LossPayload{ 
        bytes32 poolId;
        uint256 expectedLpLoss;
        uint256 expectedLeakage;
        uint256 toxicityScore;
        uint24 recommendedSpread;
        uint256 expiry;
        uint256 nonce;
        address signer;
    }
    /**
     * @notice Per-pool loss state snapshot
     */
    struct PoolLossState {
        uint256 expectedLpLoss;
        uint256 expectedLeakage;
        uint256 toxicityScore;
        uint24 spread;
        uint256 updatedAt;
    }

    // State tracking
    mapping(PoolId => uint24) public lastFee;
    mapping(PoolId => uint256) public lastFeeUpdateBlock;
    mapping(address => mapping(uint256 => bool)) public usedNonces;
    mapping(address => bool) public isTrustedSigner;
    mapping(bytes32 => PoolLossState) public poolLoss;

    // Admin
    address public immutable MULTISIG;

    // Fee control constants
    uint24 public constant MAX_FEE = 20000; // 2.00% max LP fee override
    uint256 public constant FEE_HYSTERESIS = 500; // 5 bps minimum change to update PoolManager
    uint256 public constant MIN_UPDATE_INTERVAL = 1; // blocks between PoolManager updates

    // EIP-712 signature scheme
    bytes32 public constant DOMAIN_TYPEHASH =
    keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 public constant LOSS_PAYLOAD_TYPEHASH =
        keccak256(
            "LossPayload(bytes32 poolId,uint256 expectedLpLoss,uint256 expectedLeakage,uint256 toxicityScore,uint24 recommendedSpread,uint256 expiry,uint256 nonce,address signer)"
        );
    bytes32 public constant NAME_HASH = keccak256("MEVShieldHook");
    bytes32 public constant VERSION_HASH = keccak256("1");
    // Events
    event FeeUpdated(PoolId indexed poolId, uint24 oldFee, uint24 newFee);
    event TrustedSignerUpdated(address indexed signer, bool trusted);
    event LossProtectionApplied(
        bytes32 indexed poolId,
        uint256 expectedLPLoss,
        uint256 expectedLeakage,
        uint256 toxicityScore,
        uint24  spread
    );

    // Errors
    error InvalidSignature();
    error ExpiredPayload();
    error ReplayDetected();
    error InvalidPayload();
    error UntrustedSigner();
    error ZeroAddress();

    /**
     * @param _poolManager Uniswap v4 PoolManager address
     * @param _multisig Admin multisig for trusted signer management
     */
    constructor(address _poolManager, address _multisig) BaseHook(IPoolManager(_poolManager)){
        MULTISIG = _multisig;
    }

    modifier onlyMultisig() {
        _onlyMultisig();
        _;
    }

    function _onlyMultisig() internal view {
        require(msg.sender == MULTISIG, "Unauthorized");
    }

    /**
     * @notice Add or remove a trusted Risk Engine signer
     * @dev Only callable by multisig. Signers must be explicitly added.
     * @param signer Address of Risk Engine backend
     * @param trusted True to trust, false to revoke
     */
    function setTrustedSigner(address signer, bool trusted) external onlyMultisig {
        if (signer == address(0)) revert ZeroAddress();
        isTrustedSigner[signer] = trusted;
        emit TrustedSignerUpdated(signer, trusted);
    }

    /**
     * @notice EIP-712 domain separator for signature verification
     */
    function _domainSeparator() internal view returns (bytes32){
    return keccak256(
        abi.encode(
            DOMAIN_TYPEHASH,
            NAME_HASH,
            VERSION_HASH,
            block.chainid,
            address(this)
        )
    );
}

    /**
     * @notice Hash the RiskPayload struct for EIP-712 signing
     */
    function _hashPayload(LossPayload memory payload) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                LOSS_PAYLOAD_TYPEHASH,
                payload.poolId,
                payload.expectedLpLoss,
                payload.expectedLeakage,
                payload.toxicityScore,
                payload.recommendedSpread,
                payload.expiry,
                payload.nonce,
                payload.signer
            )
        );
    }

    /**
     * @notice Recover signer address from EIP-712 signature
     * @dev Uses ecrecover with v,r,s components extracted from 65-byte signature
     */
    function _recoverSigner(bytes32 digest, bytes memory signature) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            let ptr := add(signature, 0x20)
            r := mload(ptr)
            s := mload(add(ptr, 0x20))
            v := byte(0, mload(add(ptr, 0x40)))
        }

        return ecrecover(digest, v, r, s);
    }

    /**
     * @notice Verify LossPayload signature and replay protection
     * @dev Checks:
     *   - Signature is valid (ECDSA + EIP-712)
     *   - Payload not expired
     *   - Signer is trusted Risk Engine
     *   - Nonce not already used (replay protection)
     *   - Pool ID matches
     * @param key Pool key
     * @param payload Signed loss payload
     * @param signature 65-byte ECDSA signature
     */
    function _verifyPayload(
        PoolKey calldata key,
        LossPayload memory payload,
        bytes memory signature
    ) internal {
        if (payload.expiry < block.timestamp) revert ExpiredPayload();
        if (!isTrustedSigner[payload.signer]) revert UntrustedSigner();
        if (payload.recommendedSpread > MAX_FEE) revert InvalidPayload();

        PoolKey memory keyMem = PoolKey({
            currency0: key.currency0,
            currency1: key.currency1,
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: key.hooks
        });
        if (keccak256(abi.encode(keyMem.toId())) != payload.poolId)
         revert InvalidPayload();
        if (usedNonces[payload.signer][payload.nonce]) revert ReplayDetected();

        bytes32 payloadHash = _hashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), payloadHash));
        address recovered = _recoverSigner(digest, signature);

        if (recovered != payload.signer) revert InvalidSignature();

        // Mark nonce as used for replay protection
        usedNonces[payload.signer][payload.nonce] = true;
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
    function _updateFee(PoolKey calldata key, uint24 fee) internal {
        PoolKey memory keyMem = PoolKey({
            currency0: key.currency0,
            currency1: key.currency1,
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: key.hooks
        });
        PoolId poolId = keyMem.toId();

        uint24 prev = lastFee[poolId];
        if (fee > MAX_FEE) fee = MAX_FEE;

        if (prev == fee) return;

        uint256 feeDiff = fee > prev ? uint256(fee) - uint256(prev) : uint256(prev) - uint256(fee);
        // Always cache the new fee
        lastFee[poolId] = fee;

        // Only call PoolManager if change exceeds hysteresis threshold
        if (feeDiff < FEE_HYSTERESIS) return;

        if (key.fee.isDynamicFee()) {
            uint256 lastUpdate = lastFeeUpdateBlock[poolId];
            if (lastUpdate == 0 || block.number >= lastUpdate + MIN_UPDATE_INTERVAL) {
                poolManager.updateDynamicLPFee(keyMem, fee);
                lastFeeUpdateBlock[poolId] = block.number;
            }
        }

        emit FeeUpdated(poolId, prev, fee);
    }

    function classifyLoss(uint256 expectedLoss)
        internal
        pure
        returns (uint24)
    {
        if (expectedLoss < 5e18) {
            return 300;
        }

        if (expectedLoss < 20e18) {
            return 1000;
        }

        if (expectedLoss < 50e18){
            return 3000;
        }

        return 10000;
    }

    /**
     * @notice Resolve the effective fee override from a recommended spread.
     * @dev Currently returns the recommended spread directly but centralizes
     * behaviour for future adjustments (capping, transformations, etc.).
     */
    function resolveFeeOverride(uint24 recommendedSpread)
    internal
    pure
    returns (uint24)
{
    return recommendedSpread;
}

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
        // Decode LossPayload and signature
        (LossPayload memory payload, bytes memory signature) =
            abi.decode(data, (LossPayload, bytes));

        // Verify signature, nonce, expiry, and trusted signer
        _verifyPayload(key, payload, signature);

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

        // Update cached fee with hysteresis protection
        _updateFee(key, payload.recommendedSpread);

        uint24 feeOverride = resolveFeeOverride(payload.recommendedSpread);

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