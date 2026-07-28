import { logger } from "../config/logger.js";
import { SettlementStatus } from "./SettlementService.js";
import { ethers } from "ethers";
import { env } from "../config/env.js";
const DEFAULT_MAX_RETRIES = 3;
const DEFAULT_RETRY_DELAY_MS = 1000;
export class SettlementExecutor {
    settlementService;
    transferExecutorImpl;
    options;
    constructor(settlementService, transferExecutorImpl, options = {}) {
        this.settlementService = settlementService;
        this.transferExecutorImpl = transferExecutorImpl;
        this.options = options;
    }
    async processSettlement(settlementId) {
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
            const txHash = await this.executeTransferWithRetries(record);
            this.settlementService.updateStatus(record.settlementId, SettlementStatus.Completed, txHash);
            logger.info({ msg: "Settlement completed", settlementId, txHash });
            return true;
        }
        catch (error) {
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
    async executeTransferWithRetries(record) {
        const maxRetries = this.options.maxRetries ?? DEFAULT_MAX_RETRIES;
        const retryDelayMs = this.options.retryDelayMs ?? DEFAULT_RETRY_DELAY_MS;
        let lastError;
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
            }
            catch (error) {
                lastError = error;
                logger.warn({ msg: "Settlement attempt failed", settlementId: record.settlementId, attempt, error: error instanceof Error ? error.message : "Unknown error" });
            }
        }
        throw lastError instanceof Error ? lastError : new Error("Settlement execution failed");
    }
    async executeTransfer(record) {
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
