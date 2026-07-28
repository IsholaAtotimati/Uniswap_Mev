import { logger } from "../config/logger.js";
import { SettlementService, SettlementStatus } from "./SettlementService.js";
import { SettlementRelayer } from "./SettlementRelayer.js";
import { ethers } from "ethers";
import { env } from "../config/env.js";

const DEFAULT_MAX_RETRIES = 3;
const DEFAULT_RETRY_DELAY_MS = 1000;

export interface SettlementTransferExecutor {
    transferExecutor(record: {
        settlementId: string;
        token: string;
        amount: number;
        recipient: string;
        destinationDomain: number;
    }): Promise<string>;
}

export class SettlementExecutor {
    constructor(
        private settlementService: SettlementService,
        private transferExecutorImpl?: SettlementTransferExecutor,
        private settlementRelayer?: SettlementRelayer,
        private options: {
            maxRetries?: number;
            retryDelayMs?: number;
            settlementMode?: "cctp" | "direct" | "disabled";
        } = {}
    ) {}

    async processSettlement(settlementId: string): Promise<boolean> {
        const record = this.settlementService.get(settlementId);
        if (!record) {
            logger.warn({ msg: "Settlement not found", settlementId });
            return false;
        }

        if (record.status === SettlementStatus.Completed) {
            return true;
        }

        if (record.status === SettlementStatus.Failed) {
            logger.warn({ msg: "Settlement previously failed", settlementId });
            return false;
        }

        if (this.options.settlementMode === "disabled") {
            logger.info({ msg: "Settlement execution disabled by configuration", settlementId });
            this.settlementService.updateStatus(record.settlementId, SettlementStatus.Failed);
            return false;
        }

        try {
            // If using CCTP flow and relayer is available, progress through relayer
            if (this.options.settlementMode === "cctp" && this.settlementRelayer) {
                return await this.processViaCCTPRelayer(record.settlementId);
            }

            // Otherwise use direct transfer
            const txHash = await this.executeTransferWithRetries(record);
            this.settlementService.updateStatus(record.settlementId, SettlementStatus.Completed, txHash);
            logger.info({ msg: "Settlement completed", settlementId, txHash });
            return true;
        } catch (error) {
            const errorMessage = error instanceof Error ? error.message : "Unknown error";
            const nextRetryCount = record.retryCount + 1;
            this.settlementService.updateStatus(record.settlementId, SettlementStatus.Failed, undefined, {
                retryCount: nextRetryCount,
                lastError: errorMessage
            });
            logger.error({ msg: "Settlement execution failed", settlementId, error: errorMessage, retryCount: nextRetryCount });
            return false;
        }
    }

    /**
     * Process settlement through CCTP relayer state machine
     * Pending → BurnSubmitted → AwaitingAttestation → MintSubmitted → Completed
     */
    private async processViaCCTPRelayer(settlementId: string): Promise<boolean> {
        if (!this.settlementRelayer) {
            logger.error({ msg: "CCTP relayer not available", settlementId });
            return false;
        }

        const record = this.settlementService.get(settlementId);
        if (!record) {
            return false;
        }

        try {
            // For demo purposes, we'll simulate the CCTP flow
            // In production, this would integrate with actual CCTP infrastructure

            // Step 1: Record CCTP message (Pending → BurnSubmitted)
            logger.info({
                msg: "CCTP step 1: Recording CCTP message",
                settlementId
            });
            const messageId = ethers.hexlify(ethers.randomBytes(32));
            const nonce = 1n;
            await this.settlementRelayer.recordCCTPMessage(settlementId, messageId, nonce);

            // Step 2: Mark awaiting attestation (BurnSubmitted → AwaitingAttestation)
            logger.info({
                msg: "CCTP step 2: Waiting for attestation",
                settlementId
            });
            await this.sleep(1000);
            await this.settlementRelayer.markAwaitingAttestation(settlementId);

            // Step 3: Mark mint submitted (AwaitingAttestation → MintSubmitted)
            logger.info({
                msg: "CCTP step 3: Mint submitted",
                settlementId
            });
            await this.sleep(1000);
            await this.settlementRelayer.markMintSubmitted(settlementId);

            // Step 4: Complete settlement (MintSubmitted → Completed)
            logger.info({
                msg: "CCTP step 4: Completing settlement",
                settlementId
            });
            await this.sleep(1000);
            const txHash = await this.settlementRelayer.completeSettlement(settlementId);

            logger.info({
                msg: "CCTP settlement flow completed",
                settlementId,
                txHash
            });

            return true;
        } catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            logger.error({
                msg: "CCTP settlement flow failed",
                settlementId,
                error: errorMsg
            });

            try {
                await this.settlementRelayer.markSettlementFailed(settlementId, errorMsg);
            } catch (markError) {
                logger.error({
                    msg: "Failed to mark settlement as failed on-chain",
                    settlementId,
                    error: markError instanceof Error ? markError.message : String(markError)
                });
            }

            return false;
        }
    }

    private sleep(ms: number): Promise<void> {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }

    private async executeTransferWithRetries(record: {
        settlementId: string;
        token: string;
        amount: number;
        recipient: string;
        destinationDomain: number;
    }): Promise<string> {
        const maxRetries = this.options.maxRetries ?? DEFAULT_MAX_RETRIES;
        const retryDelayMs = this.options.retryDelayMs ?? DEFAULT_RETRY_DELAY_MS;

        let lastError: unknown;
        for (let attempt = 1; attempt <= maxRetries; attempt += 1) {
            try {
                if (attempt > 1) {
                    logger.warn({ msg: "Retrying settlement execution", settlementId: record.settlementId, attempt });
                    await new Promise((resolve) => setTimeout(resolve, retryDelayMs));
                }

                const retryCount = attempt - 1;
                this.settlementService.updateStatus(record.settlementId, SettlementStatus.Submitted, undefined, {
                    retryCount,
                    lastError: undefined
                });

                return await this.executeTransfer(record);
            } catch (error) {
                lastError = error;
                logger.warn({ msg: "Settlement attempt failed", settlementId: record.settlementId, attempt, error: error instanceof Error ? error.message : "Unknown error" });
            }
        }

        throw lastError instanceof Error ? lastError : new Error("Settlement execution failed");
    }

    private async executeTransfer(record: {
        settlementId: string;
        token: string;
        amount: number;
        recipient: string;
        destinationDomain: number;
    }): Promise<string> {
        if (this.transferExecutorImpl) {
            return this.transferExecutorImpl.transferExecutor(record);
        }

        const provider = new ethers.JsonRpcProvider(env.RPC_URL || "http://localhost:8545");
        const wallet = new ethers.Wallet(env.PRIVATE_KEY, provider);

        const erc20Abi = [
            "function transfer(address to, uint256 amount) external returns (bool)",
            "function balanceOf(address owner) external view returns (uint256)"
        ];

        const tokenContract = new ethers.Contract(record.token, erc20Abi, wallet);

        // Convert the incoming (possibly fractional) amount into token base units.
        // Use 18 decimals as a sensible default for ERC-20 tokens; callers should
        // pass amounts in human-readable units (e.g. 0.2 for 0.2 tokens).
        const amountParsed = ethers.parseUnits(String(record.amount), 18);

        // If the amount resolves to zero (very small USD/float values), skip
        // the transfer to avoid passing fractional values to ethers.
        if (amountParsed === 0n) {
            logger.info({ msg: "Settlement amount is zero after scaling; skipping transfer", settlementId: record.settlementId, amount: record.amount });
            return "";
        }

        const balance = await tokenContract.balanceOf(wallet.address);
        if (balance < amountParsed) {
            throw new Error(`Insufficient balance for settlement ${record.settlementId}`);
        }

        const tx = await tokenContract.transfer(record.recipient, amountParsed);
        await tx.wait();

        return tx.hash;
    }
}
