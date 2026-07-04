import { SwapDirection } from "../types/enums.js";

export interface SwapContext {

    poolId: string;

    blockNumber: number;

    txHash: string;

    sender: string;

    recipient: string;

    token0: string;

    token1: string;

    amount0: bigint;

    amount1: bigint;

    sqrtPriceX96: bigint;

    liquidity: bigint;

    tick: number;

    fee: number;

    gasPrice: bigint;

    timestamp: number;

    direction: SwapDirection;

}