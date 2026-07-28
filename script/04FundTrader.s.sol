// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import "forge-std/Script.sol";


interface IERC20 {

    function transfer(
        address,
        uint256
    ) external returns(bool);

}



contract FundTrader is Script {


    function run() external {


        address usdc =
            vm.envAddress("USDC");


        address trader =
            vm.envAddress("TRADER");


        uint256 pk =
            vm.envUint("PRIVATE_KEY");


        vm.startBroadcast(pk);



        IERC20(usdc)
            .transfer(
                trader,
                1000e6
            );


        console.log(
            "Trader funded"
        );


        vm.stopBroadcast();

    }
}