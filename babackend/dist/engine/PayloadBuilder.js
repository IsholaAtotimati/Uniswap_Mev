import { env } from "../config/env.js";
import { ethers } from "ethers";
function normalizeIntegerAmount(value, fallback = 0) {
    if (!Number.isFinite(value)) {
        return fallback;
    }
    if (value <= 0) {
        return fallback;
    }
    return Math.max(1, Math.round(value));
}
export class PayloadBuilder {
    nonce = 0;
    normalizePoolId(poolId) {
        const bytes32Regex = /^0x[0-9a-fA-F]{64}$/;
        return bytes32Regex.test(poolId) ? poolId : ethers.id(poolId);
    }
    build(result, poolId, signer, expirySeconds = 300) {
        const payloadPoolId = this.normalizePoolId(poolId);
        const payload = {
            poolId: payloadPoolId,
            expectedLpLoss: normalizeIntegerAmount(result.expectedLpLossUSD),
            expectedLeakage: normalizeIntegerAmount(result.expectedLeakageUSD),
            toxicityScore: Math.floor(result.toxicityScore * 10000), recommendedSpread: Math.floor(result.recommendedSpread),
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
    buildWithSettlement(result, poolId, signer, settlementToken, settlementAmount, destinationDomain, recipient, expirySeconds = 300) {
        const payloadPoolId = this.normalizePoolId(poolId);
        const payload = {
            poolId: payloadPoolId,
            expectedLpLoss: normalizeIntegerAmount(result.expectedLpLossUSD),
            expectedLeakage: normalizeIntegerAmount(result.expectedLeakageUSD),
            toxicityScore: Math.floor(result.toxicityScore * 10000), recommendedSpread: Math.floor(result.recommendedSpread),
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
