// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library LossEstimator {

    function estimateLoss(
        uint256 amountSpecified,
        uint256 liquidity
    )
        internal
        pure
        returns (uint256)
    {
        if (liquidity == 0) return 10000;

        return (amountSpecified * 10000) / liquidity;
    }
}