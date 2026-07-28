import { logger } from "../config/logger.js";
export var SettlementStatus;
(function (SettlementStatus) {
    SettlementStatus["Pending"] = "pending";
    SettlementStatus["Submitted"] = "submitted";
    SettlementStatus["Completed"] = "completed";
    SettlementStatus["Failed"] = "failed";
})(SettlementStatus || (SettlementStatus = {}));
export class SettlementService {
    settlements = new Map();
    create(settlementId, poolId, nonce, token, amount, destinationDomain, recipient, metadata) {
        const record = {
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
    get(settlementId) {
        return this.settlements.get(settlementId);
    }
    updateStatus(settlementId, status, txHash, extra) {
        const record = this.settlements.get(settlementId);
        if (!record)
            return undefined;
        record.status = status;
        record.updatedAt = Date.now();
        if (txHash)
            record.txHash = txHash;
        if (extra?.retryCount !== undefined)
            record.retryCount = extra.retryCount;
        if (extra?.lastError !== undefined)
            record.lastError = extra.lastError;
        logger.info({
            msg: "Settlement status updated",
            settlementId,
            status,
            txHash
        });
        return record;
    }
    listPending() {
        return Array.from(this.settlements.values()).filter((r) => r.status === SettlementStatus.Pending);
    }
    listAll() {
        return Array.from(this.settlements.values());
    }
}
