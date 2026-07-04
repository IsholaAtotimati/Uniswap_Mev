// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {MEVShieldHook} from "../src/MEVShieldHook.sol";
import {BaseHook} from "v4-hooks-public/lib/briefcase/src/protocols/v4-periphery/utils/BaseHook.sol";
import {PoolKey} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolKey.sol";
import {Currency} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/Currency.sol";
import {SwapParams} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolOperation.sol";
import {BeforeSwapDelta} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/BeforeSwapDelta.sol";
import {LPFeeLibrary} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/libraries/LPFeeLibrary.sol";
import {IHooks} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/interfaces/IHooks.sol";

contract MockPoolManager {
    function updateDynamicLPFee(PoolKey calldata, uint24) external pure {}
}

contract MEVShieldHookBeforeSwapHarness is MEVShieldHook {
    constructor(address poolManager) MEVShieldHook(poolManager, address(this)) {}

    function validateHookAddress(BaseHook) internal pure override {}

    function exposeSetTrustedSigner(address signer, bool trusted) external {
        this.setTrustedSigner(signer, trusted);
    }

    function exposeDomainSeparator() public view returns (bytes32) {
        return _domainSeparator();
    }

    function exposeHashPayload(LossPayload memory payload) public pure returns (bytes32) {
        return _hashPayload(payload);
    }

    function exposeBeforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        external
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        return _beforeSwap(sender, key, params, hookData);
    }
}

contract MEVShieldHookBeforeSwapTest is Test {
    MEVShieldHookBeforeSwapHarness public hook;

    function setUp() public {
        MockPoolManager poolManager = new MockPoolManager();
        hook = new MEVShieldHookBeforeSwapHarness(address(poolManager));
    }

    function _buildAndSignPayload(uint256 signerPk, PoolKey memory key, uint24 recommendedSpread, uint256 nonce) internal returns (MEVShieldHook.LossPayload memory, bytes memory) {
        address signer = vm.addr(signerPk);
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: keccak256(abi.encode(key.toId())),
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 75,
            recommendedSpread: recommendedSpread,
            expiry: block.timestamp + 1 hours,
            nonce: nonce,
            signer: signer
        });

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        return (payload, signature);
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

        (MEVShieldHook.LossPayload memory payload, bytes memory signature) = _buildAndSignPayload(signerPk, key, 1200, 7);
        bytes memory hookData = abi.encode(payload, signature);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });

        (bytes4 selector, , uint24 feeOverride) = hook.exposeBeforeSwap(address(this), key, params, hookData);

        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(feeOverride, uint24(1200 | LPFeeLibrary.OVERRIDE_FEE_FLAG));

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(payload.poolId);
        assertEq(actualLpLoss, 1e18);
        assertEq(actualLeakage, 2e17);
        assertEq(actualToxicity, 75);
        assertEq(actualSpread, 1200);
        assertGt(actualUpdatedAt, 0);
    }

    function test_beforeSwapStaticFeeReturnsUnflaggedFee() public {
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

        (MEVShieldHook.LossPayload memory payload, bytes memory signature) = _buildAndSignPayload(signerPk, key, 1200, 8);
        bytes memory hookData = abi.encode(payload, signature);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });

        (bytes4 selector, , uint24 feeOverride) = hook.exposeBeforeSwap(address(this), key, params, hookData);

        assertEq(selector, IHooks.beforeSwap.selector);
        assertEq(feeOverride, 1200);
        assertEq(feeOverride & LPFeeLibrary.OVERRIDE_FEE_FLAG, 0);

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(payload.poolId);
        assertEq(actualLpLoss, 1e18);
        assertEq(actualLeakage, 2e17);
        assertEq(actualToxicity, 75);
        assertEq(actualSpread, 1200);
        assertGt(actualUpdatedAt, 0);
    }

    function test_fuzz_beforeSwap_appliesPayload(
        uint256 signerPk,
        uint24 recommendedSpread,
        uint256 nonce,
        bool isDynamic
    ) public {
        vm.assume(signerPk != 0);
        vm.assume(signerPk < 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141);
        vm.assume(recommendedSpread <= 20000);
        vm.assume(nonce < 1e6);

        address signer = vm.addr(signerPk);
        hook.exposeSetTrustedSigner(signer, true);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0x1000)),
            currency1: Currency.wrap(address(0x2000)),
            fee: isDynamic ? LPFeeLibrary.DYNAMIC_FEE_FLAG : uint24(3000),
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });

        (MEVShieldHook.LossPayload memory payload, bytes memory signature) = _buildAndSignPayload(signerPk, key, recommendedSpread, nonce);
        bytes memory hookData = abi.encode(payload, signature);

        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: 1e18,
            sqrtPriceLimitX96: 0
        });

        (bytes4 selector, , uint24 feeOverride) = hook.exposeBeforeSwap(address(this), key, params, hookData);

        assertEq(selector, IHooks.beforeSwap.selector);
        if (isDynamic) {
            assertEq(feeOverride, uint24(recommendedSpread | LPFeeLibrary.OVERRIDE_FEE_FLAG));
        } else {
            assertEq(feeOverride, recommendedSpread);
            assertEq(feeOverride & LPFeeLibrary.OVERRIDE_FEE_FLAG, 0);
        }

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(payload.poolId);
        assertEq(actualLpLoss, 1e18);
        assertEq(actualToxicity, 75);
        assertEq(actualSpread, recommendedSpread);
        assertGt(actualUpdatedAt, 0);
    }
}
