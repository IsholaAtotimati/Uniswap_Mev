// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";

contract DeployPoolManager is Script {

    function run() external {

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        address owner = vm.envAddress("MULTISIG");

        vm.startBroadcast(deployerKey);

        PoolManager poolManager = new PoolManager(owner);

        console.log(
            "PoolManager:",
            address(poolManager)
        );

        vm.stopBroadcast();
    }
}