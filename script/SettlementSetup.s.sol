// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../src/MEVShieldHook.sol";
import "../src/ExecutionCoordinator.sol";

/**
 * @title SettlementSetupScript
 * @notice Configure settlement relayer, trusted signers, and policies on MEVShieldHook
 * 
 * Usage:
 * forge script script/SettlementSetup.s.sol --rpc-url $RPC_URL --broadcast
 */
contract SettlementSetupScript is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerKey);

        address hookAddress = vm.envAddress("HOOK_ADDRESS");
        address settlementRelayerAddress = vm.envAddress("SETTLEMENT_RELAYER");
        address trustedSignerAddress = vm.envAddress("TRUSTED_SIGNER");

        MEVShieldHook hook = MEVShieldHook(hookAddress);

        vm.startBroadcast(deployerKey);

        // 1. Set settlement relayer
        if (settlementRelayerAddress != address(0)) {
            console.log("Setting settlement relayer:", settlementRelayerAddress);
            hook.setSettlementRelayer(settlementRelayerAddress);
        }

        // 2. Set trusted signer
        if (trustedSignerAddress != address(0)) {
            console.log("Setting trusted signer:", trustedSignerAddress);
            hook.setTrustedSigner(trustedSignerAddress, true);
        }

        // 3. Set quorum threshold (default 1 for single signer)
        uint256 quorumThreshold = vm.envOr("QUORUM_THRESHOLD", uint256(1));
        console.log("Setting quorum threshold:", quorumThreshold);
        hook.setQuorumThreshold(quorumThreshold);

        // 4. Set risk policy
        uint256 maxExpectedLpLoss = vm.envOr("MAX_LP_LOSS", uint256(10e18));
        uint256 maxExpectedLeakage = vm.envOr("MAX_LEAKAGE", uint256(5e18));
        uint256 maxToxicityScore = vm.envOr("MAX_TOXICITY", uint256(100));
        uint24 maxRecommendedSpread = uint24(vm.envOr("MAX_SPREAD", uint256(20000)));
        bool rejectOnThreshold = vm.envOr("REJECT_ON_THRESHOLD", false);

        console.log("Setting risk policy:");
        console.log("  maxExpectedLpLoss:", maxExpectedLpLoss);
        console.log("  maxExpectedLeakage:", maxExpectedLeakage);
        console.log("  maxToxicityScore:", maxToxicityScore);
        console.log("  maxRecommendedSpread:", maxRecommendedSpread);
        console.log("  rejectOnThreshold:", rejectOnThreshold);

        hook.setRiskPolicy(
            maxExpectedLpLoss,
            maxExpectedLeakage,
            maxToxicityScore,
            maxRecommendedSpread,
            rejectOnThreshold
        );

        vm.stopBroadcast();

        console.log("Settlement setup completed!");
        console.log("Hook address:", hookAddress);
        console.log("Deployer:", deployerAddress);
    }
}
