import { logger } from "../config/logger.js";

export enum SettlementStatus {
    Pending = "pending",
    Submitted = "submitted",
    Completed = "completed",
    Failed = "failed"
}

export interface SettlementMetadata {
    asset?: string;
    executionMode?: "direct" | "conditional";
    cctpEnabled?: boolean;
    paymasterEnabled?: boolean;
    crossChainEnabled?: boolean;
}

export interface SettlementRecord {
    settlementId: string;
    poolId: string;
    nonce: number;
    token: string;
    amount: number;
    destinationDomain: number;
    recipient: string;
    status: SettlementStatus;
    txHash?: string;
    retryCount: number;
    lastError?: string;
    metadata?: SettlementMetadata;
    createdAt: number;
    updatedAt: number;
}

export class SettlementService {
    private settlements = new Map<string, SettlementRecord>();

    create(
        settlementId: string,
        poolId: string,
        nonce: number,
        token: string,
        amount: number,
        destinationDomain: number,
        recipient: string,
        metadata?: SettlementMetadata
    ): SettlementRecord {
        const record: SettlementRecord = {
            settlementId,
            poolId,
            nonce,
            token,
            amount,
            destinationDomain,
            recipient,
            status: SettlementStatus.Pending,
            retryCount: 0,
            metadata,
            createdAt: Date.now(),
            updatedAt: Date.now()
        };

        this.settlements.set(settlementId, record);
        logger.info({
            msg: "Settlement created",
            settlementId,
            poolId,
            amount
        });

        return record;
    }

    get(settlementId: string): SettlementRecord | undefined {
        return this.settlements.get(settlementId);
    }

    updateStatus(settlementId: string, status: SettlementStatus, txHash?: string, extra?: { retryCount?: number; lastError?: string }): SettlementRecord | undefined {
        const record = this.settlements.get(settlementId);
        if (!record) return undefined;

        record.status = status;
        record.updatedAt = Date.now();
        if (txHash) record.txHash = txHash;
        if (extra?.retryCount !== undefined) record.retryCount = extra.retryCount;
        if (extra?.lastError !== undefined) record.lastError = extra.lastError;

        logger.info({
            msg: "Settlement status updated",
            settlementId,
            status,
            txHash
        });

        return record;
    }

    listPending(): SettlementRecord[] {
        return Array.from(this.settlements.values()).filter(
            (r) => r.status === SettlementStatus.Pending
        );
    }

    listAll(): SettlementRecord[] {
        return Array.from(this.settlements.values());
    }
}
