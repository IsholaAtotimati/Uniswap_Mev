// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;


import "forge-std/Script.sol";


contract GenerateRiskPayload is Script {


    struct RiskPayload {

        bytes32 poolId;

        uint256 riskScore;

        uint256 toxicity;

        uint256 expectedLeakage;

        uint256 recommendedFee;

        uint256 nonce;

        uint256 expiry;
    }



    function run()
        external
        returns(RiskPayload memory payload)
    {


        payload =
            RiskPayload({

            poolId:
                keccak256(
                "USDC-ETH"
                ),

            riskScore:
                8500,

            toxicity:
                9000,

            expectedLeakage:
                1500e6,

            recommendedFee:
                80,

            nonce:
                1,

            expiry:
                block.timestamp + 1 hours

        });


        console.log(
            "Risk score:",
            payload.riskScore
        );


        console.log(
            "Recommended fee:",
            payload.recommendedFee
        );

    }

}