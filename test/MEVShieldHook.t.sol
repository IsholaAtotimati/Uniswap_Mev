// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, stdJson} from "forge-std/Test.sol";
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

contract MEVShieldHookHarness is MEVShieldHook {
    constructor(address poolManager) MEVShieldHook(poolManager, address(this)) {}

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

    function exposeDomainSeparator() public view returns (bytes32) {
        return _domainSeparator();
    }

    function exposeHashPayload(LossPayload memory payload) public pure returns (bytes32) {
        return _hashPayload(payload);
    }

    function exposeProcessPayload(PoolKey calldata key, LossPayload calldata payload, bytes calldata signature) external {
        _verifyPayload(key, payload, signature);
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
}

contract MEVShieldHookTest is Test {
    using stdJson for string;

    MEVShieldHookHarness public hook;

    function setUp() public {
        MockPoolManager poolManager = new MockPoolManager();
        hook = new MEVShieldHookHarness(address(poolManager));
    }

    function test_classifyLossReturnsExpectedTieredOverrides() public view {
        assertEq(hook.exposeClassifyLoss(1e18), 300);
        assertEq(hook.exposeClassifyLoss(5e18), 1000);
        assertEq(hook.exposeClassifyLoss(20e18), 3000);
        assertEq(hook.exposeClassifyLoss(100e18), 10000);
    }

    function test_resolveFeeOverrideUsesRecommendedSpread() public view {
        assertEq(hook.exposeResolveFeeOverride(8000), 8000);
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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 75,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 7,
            signer: signer
        });

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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 75,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 7,
            signer: signer
        });

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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 75,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 7,
            signer: signer
        });

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
        assertEq(feeOverride, uint24(1200 | LPFeeLibrary.OVERRIDE_FEE_FLAG));

        (uint256 actualLpLoss, uint256 actualLeakage, uint256 actualToxicity, uint24 actualSpread, uint256 actualUpdatedAt) = hook.poolLoss(poolId);
        assertEq(actualLpLoss, 1e18);
        assertEq(actualLeakage, 2e17);
        assertEq(actualToxicity, 75);
        assertEq(actualSpread, 1200);
        assertGt(actualUpdatedAt, 0);
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

        bytes memory rawResult = vm.ffi(ffiArgs);
        string memory jsonResult = string(rawResult);

        bytes32 poolId = jsonResult.readBytes32(".payload.poolId");
        uint256 expectedLpLoss = jsonResult.readUint(".payload.expectedLpLoss");
        uint256 expectedLeakage = jsonResult.readUint(".payload.expectedLeakage");
        uint256 toxicityScore = jsonResult.readUint(".payload.toxicityScore");
        uint24 recommendedSpread = uint24(jsonResult.readUint(".payload.recommendedSpread"));
        uint256 expiry = jsonResult.readUint(".payload.expiry");
        uint256 nonce = jsonResult.readUint(".payload.nonce");
        address payloadSigner = jsonResult.readAddress(".payload.signer");
        bytes memory signature = jsonResult.readBytes(".signature");

        assertEq(payloadSigner, signer);
        assertEq(poolId, keccak256(abi.encode(key.toId())));

        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: expectedLpLoss,
            expectedLeakage: expectedLeakage,
            toxicityScore: toxicityScore,
            recommendedSpread: recommendedSpread,
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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: expectedLpLoss,
            expectedLeakage: expectedLeakage,
            toxicityScore: toxicityScore,
            recommendedSpread: recommendedSpread % 20001,
            expiry: block.timestamp + 1 + expiryDelay,
            nonce: nonce,
            signer: signer
        });

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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 1200,
            expiry: expiry,
            nonce: 1,
            signer: signer
        });

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.warp(expiry + 1);
        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.ExpiredPayload.selector));
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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 1,
            signer: signer
        });

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.UntrustedSigner.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_setTrustedSignerRevertsWhenCallerIsNotMultisig() public {
        address signer = vm.addr(0xCAFE);
        vm.prank(address(0xBEEF));
        vm.expectRevert("Unauthorized");
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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 1,
            signer: signer
        });

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.InvalidSignature.selector));
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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 1,
            signer: signer
        });

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s);

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.InvalidSignature.selector));
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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 1,
            signer: signer
        });

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, uint8(0));

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.InvalidSignature.selector));
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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 20001,
            expiry: block.timestamp + 1 hours,
            nonce: 1,
            signer: signer
        });

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.InvalidPayload.selector));
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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 1,
            signer: signer
        });

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.InvalidPayload.selector));
        hook.exposeProcessPayload(key, payload, signature);
    }

    function test_variant_untrustedSignerRevertsWhenSignerIsZeroAddress() public {
        uint256 signerPk = 0xCAFE;
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: keccak256(abi.encode(address(0x1234))),
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 1,
            signer: address(0)
        });

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

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.UntrustedSigner.selector));
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
        MEVShieldHook.LossPayload memory payload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 1,
            signer: signer
        });

        bytes32 payloadHash = hook.exposeHashPayload(payload);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), payloadHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        hook.exposeProcessPayload(key, payload, signature);

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.ReplayDetected.selector));
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
        MEVShieldHook.LossPayload memory firstPayload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 1e18,
            expectedLeakage: 2e17,
            toxicityScore: 50,
            recommendedSpread: 1200,
            expiry: block.timestamp + 1 hours,
            nonce: 1,
            signer: signer
        });

        bytes32 firstHash = hook.exposeHashPayload(firstPayload);
        bytes32 firstDigest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), firstHash));
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(signerPk, firstDigest);
        bytes memory firstSignature = abi.encodePacked(r1, s1, v1);

        hook.exposeProcessPayload(key, firstPayload, firstSignature);

        MEVShieldHook.LossPayload memory secondPayload = MEVShieldHook.LossPayload({
            poolId: poolId,
            expectedLpLoss: 2e18,
            expectedLeakage: 3e17,
            toxicityScore: 60,
            recommendedSpread: 1300,
            expiry: block.timestamp + 2 hours,
            nonce: 1,
            signer: signer
        });

        bytes32 secondHash = hook.exposeHashPayload(secondPayload);
        bytes32 secondDigest = keccak256(abi.encodePacked("\x19\x01", hook.exposeDomainSeparator(), secondHash));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(signerPk, secondDigest);
        bytes memory secondSignature = abi.encodePacked(r2, s2, v2);

        vm.expectRevert(abi.encodeWithSelector(MEVShieldHook.ReplayDetected.selector));
        hook.exposeProcessPayload(key, secondPayload, secondSignature);
    }
}
