import { ethers } from "ethers";
import { logger } from "../config/logger.js";
import { env } from "../config/env.js";
import fs from "fs";
import path from "path";

export interface SettlementEvent {
    settlementId: string;
    token: string;
    amount: string;
    destinationDomain: number;
    transactionHash: string;
    blockNumber: number;
}

export class SettlementEventListener {
    private provider: ethers.Provider;
    private contract?: ethers.Contract;
    private listening = false;
    private callbacks: Array<(event: SettlementEvent) => Promise<void>> = [];

    constructor(
        private hookAddress: string,
        private hookAbi: any[]
    ) {
        const rpcUrl = env.RPC_URL || "http://localhost:8545";
        this.provider = new ethers.JsonRpcProvider(rpcUrl);

        if (hookAddress && hookAddress !== "0x") {
            this.contract = new ethers.Contract(hookAddress, hookAbi, this.provider);
        }
    }

    /**
     * Register a callback to be called when a SettlementAuthorized event is detected
     */
    onSettlementAuthorized(callback: (event: SettlementEvent) => Promise<void>) {
        this.callbacks.push(callback);
    }

    /**
     * Start listening for SettlementAuthorized events
     */
    async start() {
        if (!this.contract) {
            logger.warn("Hook contract not configured; settlement listener disabled");
            return;
        }

        this.listening = true;

        logger.info({
            msg: "Settlement event listener started",
            hook: this.hookAddress
        });

        try {
            // Listen for new events
            this.contract.on("SettlementAuthorized", async (settlementId, token, amount, destinationDomain, event) => {
                const settlementEvent: SettlementEvent = {
                    settlementId,
                    token,
                    amount: amount.toString(),
                    destinationDomain,
                    transactionHash: event.transactionHash,
                    blockNumber: event.blockNumber
                };

                logger.info({
                    msg: "SettlementAuthorized event detected",
                    settlementId,
                    amount: amount.toString(),
                    txHash: event.transactionHash
                });

                // Call all registered callbacks
                for (const callback of this.callbacks) {
                    try {
                        await callback(settlementEvent);
                    } catch (error) {
                        logger.error({
                            msg: "Settlement event callback failed",
                            error: error instanceof Error ? error.message : "Unknown error"
                        });
                    }
                }
            });

            // Query historical events
            await this.queryHistoricalEvents();
        } catch (error) {
            logger.error({
                msg: "Failed to set up settlement listener",
                error: error instanceof Error ? error.message : "Unknown error"
            });
        }
    }

    /**
     * Query historical events from the last 1000 blocks
     */
    private async queryHistoricalEvents() {
        if (!this.contract) return;

        try {
            const currentBlock = await this.provider.getBlockNumber();
            const lookbackBlocks = 1000;
            const fromBlock = Math.max(0, currentBlock - lookbackBlocks);

            logger.info({
                msg: "Querying historical settlement events",
                fromBlock,
                toBlock: currentBlock
            });

            const events = await this.contract.queryFilter(
                this.contract.filters.SettlementAuthorized(),
                fromBlock,
                currentBlock
            );

            logger.info({
                msg: "Found historical settlement events",
                count: events.length
            });

            for (const event of events) {
                const log = event as any;
                const settlementEvent: SettlementEvent = {
                    settlementId: log.args?.[0],
                    token: log.args?.[1],
                    amount: log.args?.[2]?.toString() || "0",
                    destinationDomain: log.args?.[3] || 0,
                    transactionHash: log.transactionHash,
                    blockNumber: log.blockNumber
                };

                logger.debug({
                    msg: "Historical settlement event",
                    settlementId: settlementEvent.settlementId
                });

                for (const callback of this.callbacks) {
                    try {
                        await callback(settlementEvent);
                    } catch (error) {
                        logger.error({
                            msg: "Historical settlement event callback failed",
                            error: error instanceof Error ? error.message : "Unknown error"
                        });
                    }
                }
            }
        } catch (error) {
            logger.error({
                msg: "Failed to query historical settlement events",
                error: error instanceof Error ? error.message : "Unknown error"
            });
        }
    }

    /**
     * Stop listening for events
     */
    async stop() {
        if (this.contract) {
            this.contract.removeAllListeners("SettlementAuthorized");
        }
        this.listening = false;
        logger.info("Settlement event listener stopped");
    }

    isListening(): boolean {
        return this.listening;
    }
}

/**
 * Load hook ABI from file path
 */
export function loadHookAbi(abiPath: string): any[] {
    try {
        if (!abiPath) {
            logger.warn("Hook ABI path not configured");
            return [];
        }

        const absolutePath = path.isAbsolute(abiPath) ? abiPath : path.join(process.cwd(), abiPath);
        const abiContent = fs.readFileSync(absolutePath, "utf-8");
        const parsed = JSON.parse(abiContent);
        return Array.isArray(parsed) ? parsed : Array.isArray(parsed?.abi) ? parsed.abi : [];
    } catch (error) {
        logger.error({
            msg: "Failed to load hook ABI",
            error: error instanceof Error ? error.message : "Unknown error"
        });
        return [];
    }
}
