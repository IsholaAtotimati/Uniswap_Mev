// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {WETH9} from "../src/WETH9.sol";

contract DeployWETH9 is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        WETH9 weth = new WETH9();

        console2.log("WETH9:", address(weth));

        vm.stopBroadcast();
    }
}