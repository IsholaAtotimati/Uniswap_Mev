// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import "forge-std/Script.sol";


interface IMEVShield {


    function protectedSwap(

        bytes32 poolId,

        uint256 amount,

        bytes calldata signature

    )
    external;


}



contract ExecuteProtectedSwap
    is Script
{


    function run() external {


        address shield =
            vm.envAddress(
                "MEV_SHIELD"
            );


        uint256 pk =
            vm.envUint(
                "PRIVATE_KEY"
            );



        vm.startBroadcast(pk);



        bytes32 poolId =
            keccak256(
            "USDC-ETH"
            );


        bytes memory signature =
            abi.encodePacked(
                "VALID_SIGNATURE"
            );



        console.log(
            "Executing protected swap..."
        );



        IMEVShield(shield)
            .protectedSwap(
                poolId,
                100e6,
                signature
            );



        console.log(
            "Swap protected"
        );



        vm.stopBroadcast();


    }

}