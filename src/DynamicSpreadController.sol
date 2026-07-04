// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library DynamicSpreadController{

    uint24 constant MAX_FEE = 20000; // 2%

    function calculateFee(
        uint256 riskScore,        // 0 - 10000 scaled (recommended)
        uint256 toxicityScore,
        uint256 volatilityScore
    )
        internal
        pure
        returns (uint24)
    {
        uint256 composite =
            (riskScore * 60) +
            (toxicityScore * 25) +
            (volatilityScore * 15);

        uint256 normalized = composite / 100;

        if (normalized < 1000) {
            return 300; // 0.03%
        }

        if (normalized < 3000) {
            return 1000; // 0.1%
        }

        if (normalized < 6000) {
            return 3000; // 0.3%
        }

        uint24 fee = 10000; // 1%

        if (fee > MAX_FEE) {
            return MAX_FEE;
        }

        return fee;
    }
}