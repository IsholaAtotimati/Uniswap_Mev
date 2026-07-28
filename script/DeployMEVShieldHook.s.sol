// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";

import {Hooks} from "v4-core/libraries/Hooks.sol";
import {HookMiner} from "v4-hooks-public/src/utils/HookMiner.sol";

import {MEVShieldHook} from "../src/MEVShieldHook.sol";


contract DeployMEVShieldHook is Script {

    address constant CREATE2_DEPLOYER =
        0x4e59b44847b379578588920cA78FbF26c0B4956C;


    function run() external {

        address poolManager =
            vm.envAddress("POOL_MANAGER");

        address multisig =
            vm.envAddress("MULTISIG");

        address usdc =
            vm.envAddress("USDC");


        uint160 flags =
            uint160(
                Hooks.BEFORE_SWAP_FLAG
            );


        bytes memory constructorArgs =
            abi.encode(
                poolManager,
                multisig,
                usdc
            );


        (
            address hookAddress,
            bytes32 salt
        ) =
            HookMiner.find(
                CREATE2_DEPLOYER,
                flags,
                type(MEVShieldHook).creationCode,
                constructorArgs
            );


        console2.log(
            "Hook address:",
            hookAddress
        );


        vm.startBroadcast();


        MEVShieldHook hook =
            new MEVShieldHook{salt:salt}(
                poolManager,
                multisig,
                usdc
            );


        require(
            address(hook)==hookAddress,
            "Hook mismatch"
        );


        vm.stopBroadcast();
    }
}