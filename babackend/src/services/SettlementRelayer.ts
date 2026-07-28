import { ethers } from "ethers";
import { logger } from "../config/logger.js";
import { env } from "../config/env.js";
import { SettlementService, SettlementStatus } from "./SettlementService.js";

export interface SettlementRelayerConfig {
    hookAddress: string;
    hookAbi: any[];
    enableCCTP?: boolean;
    retryDelayMs?: number;
    maxRetries?: number;
}

/**
 * SettlementRelayer coordinates settlement state progression on-chain.
 * 
 * Flow:
 * 1. Settlement created in Pending status by ExecutionCoordinator
 * 2. recordCCTPMessage() → BurnSubmitted
 * 3. markAwaitingAttestation() → AwaitingAttestation
 * 4. markMintSubmitted() → MintSubmitted
 * 5. completeSettlement() → Completed
 */
export class SettlementRelayer {
    private provider: ethers.Provider;
    private wallet?: ethers.Wallet;
    private contract?: ethers.Contract;

    constructor(
        private settlementService: SettlementService,
        private config: SettlementRelayerConfig
    ) {
        const rpcUrl = env.RPC_URL || "http://localhost:8545";
        this.provider = new ethers.JsonRpcProvider(rpcUrl);

        if (env.PRIVATE_KEY) {
            this.wallet = new ethers.Wallet(env.PRIVATE_KEY, this.provider);
            this.contract = new ethers.Contract(
                config.hookAddress,
                config.hookAbi,
                this.wallet
            );
        }
    }

    /**
     * Record CCTP burn message on-chain
     * Transitions: Pending → BurnSubmitted
     */
    async recordCCTPMessage(
        settlementId: string,
        messageId: string,
        nonce: bigint | string | number
    ): Promise<string> {
        if (!this.contract) {
            throw new Error("PRIVATE_KEY not configured; cannot record CCTP message");
        }

        const record = this.settlementService.get(settlementId);
        if (!record) {
            throw new Error(`Settlement ${settlementId} not found`);
        }

        if (record.status !== SettlementStatus.Pending) {
            logger.warn({
                msg: "Settlement not in Pending status; skipping recordCCTPMessage",
                settlementId,
                currentStatus: record.status
            });
            return "";
        }

        try {
            logger.info({
                msg: "Recording CCTP message on-chain",
                settlementId,
                messageId,
                nonce: nonce.toString()
            });

            const tx = await this.contract.recordCCTPMessage(
                settlementId,
                messageId,
                nonce,
                { gasLimit: 300000 }
            );

            const receipt = await tx.wait();
            const txHash = receipt?.transactionHash || tx.hash;

            this.settlementService.updateStatus(settlementId, SettlementStatus.Submitted, txHash);

            logger.info({
                msg: "CCTP message recorded successfully",
                settlementId,
                txHash
            });

            return txHash;
        } catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            logger.error({
                msg: "Failed to record CCTP message",
                settlementId,
                error: errorMsg
            });
            throw error;
        }
    }

    /**
     * Mark settlement as awaiting CCTP attestation
     * Transitions: BurnSubmitted → AwaitingAttestation
     */
    async markAwaitingAttestation(settlementId: string): Promise<string> {
        if (!this.contract) {
            throw new Error("PRIVATE_KEY not configured; cannot mark awaiting attestation");
        }

        const record = this.settlementService.get(settlementId);
        if (!record) {
            throw new Error(`Settlement ${settlementId} not found`);
        }

        if (record.status !== SettlementStatus.Submitted) {
            logger.warn({
                msg: "Settlement not in Submitted status; skipping markAwaitingAttestation",
                settlementId,
                currentStatus: record.status
            });
            return "";
        }

        try {
            logger.info({
                msg: "Marking settlement as awaiting attestation",
                settlementId
            });

            const tx = await this.contract.markAwaitingAttestation(settlementId, {
                gasLimit: 200000
            });

            const receipt = await tx.wait();
            const txHash = receipt?.transactionHash || tx.hash;

            // Update service status to track on-chain progression
            this.settlementService.updateStatus(settlementId, SettlementStatus.Submitted, txHash);

            logger.info({
                msg: "Settlement marked as awaiting attestation",
                settlementId,
                txHash
            });

            return txHash;
        } catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            logger.error({
                msg: "Failed to mark awaiting attestation",
                settlementId,
                error: errorMsg
            });
            throw error;
        }
    }

    /**
     * Mark settlement CCTP mint as submitted
     * Transitions: AwaitingAttestation → MintSubmitted
     */
    async markMintSubmitted(settlementId: string): Promise<string> {
        if (!this.contract) {
            throw new Error("PRIVATE_KEY not configured; cannot mark mint submitted");
        }

        const record = this.settlementService.get(settlementId);
        if (!record) {
            throw new Error(`Settlement ${settlementId} not found`);
        }

        if (record.status !== SettlementStatus.Submitted) {
            logger.warn({
                msg: "Settlement not in Submitted status; skipping markMintSubmitted",
                settlementId,
                currentStatus: record.status
            });
            return "";
        }

        try {
            logger.info({
                msg: "Marking settlement CCTP mint as submitted",
                settlementId
            });

            const tx = await this.contract.markMintSubmitted(settlementId, {
                gasLimit: 200000
            });

            const receipt = await tx.wait();
            const txHash = receipt?.transactionHash || tx.hash;

            this.settlementService.updateStatus(settlementId, SettlementStatus.Submitted, txHash);

            logger.info({
                msg: "Settlement CCTP mint marked as submitted",
                settlementId,
                txHash
            });

            return txHash;
        } catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            logger.error({
                msg: "Failed to mark mint submitted",
                settlementId,
                error: errorMsg
            });
            throw error;
        }
    }

    /**
     * Complete settlement on-chain
     * Transitions: * → Completed (final state)
     * Requires relayer to have sufficient USDC balance
     */
    async completeSettlement(settlementId: string): Promise<string> {
        if (!this.contract || !this.wallet) {
            throw new Error("PRIVATE_KEY not configured; cannot complete settlement");
        }

        const record = this.settlementService.get(settlementId);
        if (!record) {
            throw new Error(`Settlement ${settlementId} not found`);
        }

        if (record.status === SettlementStatus.Completed) {
            logger.info({
                msg: "Settlement already completed",
                settlementId
            });
            return "";
        }

        try {
            logger.info({
                msg: "Completing settlement on-chain",
                settlementId,
                amount: record.amount,
                recipient: record.recipient
            });

            // Ensure relayer has sufficient balance
            const usdcAddress = record.token;
            const usdcContract = new ethers.Contract(
                usdcAddress,
                ["function balanceOf(address) public view returns (uint256)"],
                this.wallet
            );

            const balance = await usdcContract.balanceOf(this.wallet.address);
            if (balance < record.amount) {
                throw new Error(
                    `Insufficient USDC balance. Have: ${balance.toString()}, Need: ${record.amount}`
                );
            }

            const tx = await this.contract.completeSettlement(settlementId, {
                gasLimit: 300000
            });

            const receipt = await tx.wait();
            const txHash = receipt?.transactionHash || tx.hash;

            this.settlementService.updateStatus(settlementId, SettlementStatus.Completed, txHash);

            logger.info({
                msg: "Settlement completed successfully",
                settlementId,
                txHash
            });

            return txHash;
        } catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            logger.error({
                msg: "Failed to complete settlement",
                settlementId,
                error: errorMsg
            });
            
            // Mark as failed on backend too
            this.settlementService.updateStatus(settlementId, SettlementStatus.Failed, undefined, {
                lastError: errorMsg
            });

            throw error;
        }
    }

    /**
     * Mark settlement as failed on-chain
     * Transitions: * → Failed (final state)
     */
    async markSettlementFailed(settlementId: string, reason: string): Promise<string> {
        if (!this.contract) {
            throw new Error("PRIVATE_KEY not configured; cannot mark settlement failed");
        }

        const record = this.settlementService.get(settlementId);
        if (!record) {
            throw new Error(`Settlement ${settlementId} not found`);
        }

        try {
            logger.info({
                msg: "Marking settlement as failed on-chain",
                settlementId,
                reason
            });

            const tx = await this.contract.markSettlementFailed(settlementId, reason, {
                gasLimit: 200000
            });

            const receipt = await tx.wait();
            const txHash = receipt?.transactionHash || tx.hash;

            this.settlementService.updateStatus(settlementId, SettlementStatus.Failed, txHash);

            logger.info({
                msg: "Settlement marked as failed on-chain",
                settlementId,
                txHash
            });

            return txHash;
        } catch (error) {
            const errorMsg = error instanceof Error ? error.message : String(error);
            logger.error({
                msg: "Failed to mark settlement as failed",
                settlementId,
                error: errorMsg
            });
            throw error;
        }
    }

    /**
     * Get the relayer's address (if private key is configured)
     */
    getRelayerAddress(): string | null {
        return this.wallet?.address || null;
    }

    /**
     * Verify that the relayer is properly configured on-chain
     */
    async verifyConfiguration(): Promise<string[]> {
        const warnings: string[] = [];

        if (!this.wallet) {
            warnings.push("PRIVATE_KEY not configured; settlement relayer cannot operate");
            return warnings;
        }

        if (!this.contract) {
            warnings.push("Hook contract not available");
            return warnings;
        }

        try {
            const relayerAddress = await this.contract.settlementRelayer();
            if (!relayerAddress || relayerAddress === ethers.ZeroAddress) {
                warnings.push("settlementRelayer not set on-chain; call setSettlementRelayer()");
            } else if (relayerAddress.toLowerCase() !== this.wallet.address.toLowerCase()) {
                warnings.push(
                    `Settlement relayer mismatch: configured=${this.wallet.address} on-chain=${relayerAddress}`
                );
            }
        } catch (error) {
            warnings.push("Failed to read settlementRelayer from contract");
        }

        return warnings;
    }
}
