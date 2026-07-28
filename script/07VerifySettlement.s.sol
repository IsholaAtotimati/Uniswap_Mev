// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import "forge-std/Script.sol";


interface Settlement {


function lastSettlement()
external view returns(bytes32);


}



contract VerifySettlement is Script {


function run() external {


address coordinator =
vm.envAddress(
"SETTLEMENT"
);



bytes32 result =
Settlement(coordinator)
.lastSettlement();



console.logBytes32(result);



}

}