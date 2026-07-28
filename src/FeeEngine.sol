// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {LPFeeLibrary} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/libraries/LPFeeLibrary.sol";
import {PoolKey} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolKey.sol";
import {PoolId} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-hooks-public/lib/briefcase/src/protocols/v4-core/interfaces/IPoolManager.sol";
import {EventPublisher} from "./EventPublisher.sol";

abstract contract FeeEngine is EventPublisher {
    using LPFeeLibrary for uint24;

    mapping(PoolId => uint24) public lastFee;
    mapping(PoolId => uint256) public lastFeeUpdateBlock;

    uint24 public constant MAX_FEE = 20000; // 2.00% max LP fee override
    uint256 public constant FEE_HYSTERESIS = 500; // 5 bps minimum change to update PoolManager
    uint256 public constant MIN_UPDATE_INTERVAL = 1; // blocks between PoolManager updates

    function _poolManager() internal view virtual returns (IPoolManager);

    function _updateFee(PoolKey calldata key, uint24 fee) internal {
        PoolKey memory keyMem = PoolKey({
            currency0: key.currency0,
            currency1: key.currency1,
            fee: key.fee,
            tickSpacing: key.tickSpacing,
            hooks: key.hooks
        });
        PoolId poolId = keyMem.toId();

        uint24 prev = lastFee[poolId];
        if (fee > MAX_FEE) fee = MAX_FEE;

        if (prev == fee) return;

        uint256 feeDiff = fee > prev ? uint256(fee) - uint256(prev) : uint256(prev) - uint256(fee);
        lastFee[poolId] = fee;

        if (feeDiff < FEE_HYSTERESIS) return;

        if (key.fee.isDynamicFee()) {
            uint256 lastUpdate = lastFeeUpdateBlock[poolId];
            if (lastUpdate == 0 || block.number >= lastUpdate + MIN_UPDATE_INTERVAL) {
                _poolManager().updateDynamicLPFee(keyMem, fee);
                lastFeeUpdateBlock[poolId] = block.number;
            }
        }

        emit FeeUpdated(poolId, prev, fee);
    }

    function classifyLoss(uint256 expectedLoss)
        internal
        pure
        returns (uint24)
    {
        if (expectedLoss < 5e18) {
            return 300;
        }

        if (expectedLoss < 20e18) {
            return 1000;
        }

        if (expectedLoss < 50e18) {
            return 3000;
        }

        return 10000;
    }

    function resolveFeeOverride(uint24 recommendedSpread)
        internal
        pure
        returns (uint24)
    {
        return recommendedSpread;
    }
}
