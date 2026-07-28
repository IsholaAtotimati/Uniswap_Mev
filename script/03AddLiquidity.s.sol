// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import "forge-std/Script.sol";


contract AddLiquidity is Script {


    function run() external {


        uint256 pk =
            vm.envUint("PRIVATE_KEY");


        vm.startBroadcast(pk);



        console.log(
            "Adding protected liquidity"
        );


        /*
          Modify liquidity position

          PoolManager.modifyLiquidity()
        */


        vm.stopBroadcast();

    }
}