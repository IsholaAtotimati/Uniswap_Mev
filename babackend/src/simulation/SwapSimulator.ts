import { randomUUID } from "crypto";
import { SwapContext } from "../models/SwapContext.js";
import { SwapDirection } from "../types/enums.js";

export class SwapSimulator {

    private pools = [
        "USDC/ETH",
        "ETH/USDT",
        "WBTC/ETH"
    ];

    generate(): SwapContext {

        const pool = this.pools[
            Math.floor(Math.random() * this.pools.length)
        ];

        const amount = Math.random() * 10_000;

        const liquidity = 1_000_000 + Math.random() * 5_000_000;

        return {
            poolId: pool,
            blockNumber: Math.floor(Date.now() / 1000),
            txHash: randomUUID(),
            sender: "0x" + Math.random().toString(16).slice(2, 42),
            recipient: "0x" + Math.random().toString(16).slice(2, 42),
            token0: "TOKEN0",
            token1: "TOKEN1",
            amount0: BigInt(Math.floor(amount * 1e6)),
            amount1: BigInt(0),
            sqrtPriceX96: BigInt(Math.floor(Math.random() * 1e18)),
            liquidity: BigInt(Math.floor(liquidity * 1e6)),
            tick: Math.floor(Math.random() * 1000),
            fee: 3000,
            gasPrice: BigInt(30 + Math.floor(Math.random() * 100)),
            timestamp: Date.now(),
            direction:
                Math.random() > 0.5
                    ? SwapDirection.ZERO_FOR_ONE
                    : SwapDirection.ONE_FOR_ZERO
        };
    }
}