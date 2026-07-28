import { RiskResult } from "../models/RiskResult.js";
import { SignedRiskPayload } from "../types/signedPayload.js";
import { env } from "../config/env.js";
import { ethers } from "ethers";

function normalizeIntegerAmount(value: number, fallback = 0): number {
    if (!Number.isFinite(value)) {
        return fallback;
    }

    if (value <= 0) {
        return fallback;
    }

    return Math.max(1, Math.round(value));
}

export class PayloadBuilder {

    private nonce = 0;

    private normalizePoolId(poolId: string): string {
        const bytes32Regex = /^0x[0-9a-fA-F]{64}$/;
        return bytes32Regex.test(poolId) ? poolId : ethers.id(poolId);
    }

    build(
        result: RiskResult,
        poolId: string,
        signer: string,
        expirySeconds = 300
    ): SignedRiskPayload {
        const payloadPoolId = this.normalizePoolId(poolId);
        const payload: SignedRiskPayload = {
            poolId: payloadPoolId,
            expectedLpLoss: normalizeIntegerAmount(result.expectedLpLossUSD),
            expectedLeakage: normalizeIntegerAmount(result.expectedLeakageUSD),
            toxicityScore: Math.floor(result.toxicityScore * 10000),            recommendedSpread: Math.floor(result.recommendedSpread),
            settlementToken: env.USDC,
            settlementAmount: normalizeIntegerAmount(result.expectedLpLossUSD),
            destinationDomain: 0,
            recipient: "0x0000000000000000000000000000000000000000000000000000000000000000",
            expiry: Math.floor(Date.now() / 1000) + expirySeconds,
            nonce: this.nonce++,
            signer
        };
        return payload;
    }

    /**
     * Create a payload with custom settlement parameters
     */
    buildWithSettlement(
        result: RiskResult,
        poolId: string,
        signer: string,
        settlementToken: string,
        settlementAmount: number,
        destinationDomain: number,
        recipient: string,
        expirySeconds = 300
    ): SignedRiskPayload {
        const payloadPoolId = this.normalizePoolId(poolId);
        const payload: SignedRiskPayload = {
            poolId: payloadPoolId,
            expectedLpLoss: normalizeIntegerAmount(result.expectedLpLossUSD),
            expectedLeakage: normalizeIntegerAmount(result.expectedLeakageUSD),
            toxicityScore: Math.floor(result.toxicityScore * 10000),            recommendedSpread: Math.floor(result.recommendedSpread),
            settlementToken,
            settlementAmount: normalizeIntegerAmount(settlementAmount),
            destinationDomain,
            recipient,
            expiry: Math.floor(Date.now() / 1000) + expirySeconds,
            nonce: this.nonce++,
            signer
        };
        return payload;
    }
}
