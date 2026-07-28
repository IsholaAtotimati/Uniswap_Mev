// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import "forge-std/Script.sol";


interface IPoolManager {

    function initialize(
        bytes calldata key,
        uint160 sqrtPriceX96
    )
    external;

}



contract CreatePool is Script {


    function run() external {


        address poolManager =
            vm.envAddress("POOL_MANAGER");


        uint256 key =
            vm.envUint("PRIVATE_KEY");


        vm.startBroadcast(key);



        console.log(
            "Creating MEVShield Pool..."
        );


        // pool initialization call here


        vm.stopBroadcast();

    }
}