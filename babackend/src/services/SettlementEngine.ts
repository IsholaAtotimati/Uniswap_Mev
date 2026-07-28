import { logger } from "../config/logger.js";
import { SettlementService, SettlementStatus } from "./SettlementService.js";

export interface SettlementCompletionClient {
    completeSettlement(settlementId: string): Promise<string>;
}

export interface SettlementEngineOptions {
    cctpDelayMs?: number;
    requireAttestation?: boolean;
}

export class SettlementEngine {
    constructor(
        private settlementService: SettlementService,
        private completionClient?: SettlementCompletionClient,
        private options: SettlementEngineOptions = {}
    ) {}

    async processSettlement(settlementId: string, attestation?: string): Promise<boolean> {
        const record = this.settlementService.get(settlementId);
        if (!record) {
            logger.warn({ msg: "Settlement record not found", settlementId });
            return false;
        }

        if (record.status === SettlementStatus.Completed) {
            return true;
        }

        if (record.status === SettlementStatus.Failed) {
            return false;
        }

        const requiresAttestation = this.options.requireAttestation || record.metadata?.executionMode === "conditional";
        if (requiresAttestation && (!attestation || attestation.trim().length === 0)) {
            const message = "Attestation required for conditional settlement execution";
            this.settlementService.updateStatus(record.settlementId, SettlementStatus.Failed, undefined, { lastError: message });
            logger.warn({ msg: "Conditional settlement blocked without attestation", settlementId, metadata: record.metadata });
            return false;
        }

        logger.info({
            msg: "Preparing settlement execution",
            settlementId,
            metadata: record.metadata,
            attestationProvided: Boolean(attestation && attestation.trim().length > 0)
        });

        this.settlementService.updateStatus(record.settlementId, SettlementStatus.Submitted, attestation);

        if (this.options.cctpDelayMs && this.options.cctpDelayMs > 0) {
            await new Promise((resolve) => setTimeout(resolve, this.options.cctpDelayMs));
        }

        if (!this.completionClient) {
            this.settlementService.updateStatus(record.settlementId, SettlementStatus.Completed, attestation);
            return true;
        }

        try {
            const txHash = await this.completionClient.completeSettlement(settlementId);
            this.settlementService.updateStatus(record.settlementId, SettlementStatus.Completed, txHash);
            return true;
        } catch (error) {
            const message = error instanceof Error ? error.message : "Unknown error";
            this.settlementService.updateStatus(record.settlementId, SettlementStatus.Failed, undefined, { lastError: message });
            logger.error({ msg: "Settlement completion failed", settlementId, error: message });
            return false;
        }
    }
}
