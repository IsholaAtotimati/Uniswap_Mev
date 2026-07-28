// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

import "../src/MEVShieldHook.sol";


contract DeployProtocol is Script {

    function run() external {

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address poolManager = vm.envAddress("POOL_MANAGER");
        address multisig = vm.envAddress("MULTISIG");
        address usdc = vm.envAddress("USDC");

        vm.startBroadcast(deployerKey);

        MEVShieldHook hook =
            new MEVShieldHook(poolManager, multisig, usdc);

        console.log(
            "MEVShieldHook:",
            address(hook)
        );

        vm.stopBroadcast();
    }
}