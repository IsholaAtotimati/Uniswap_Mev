import { RiskResult } from "../models/RiskResult.js";
import { SignedRiskPayload } from "../types/signedPayload.js";

export class PayloadBuilder {

    private nonce = 0;

    build(
        result: RiskResult,
        poolId: string,
        signer: string,
        expirySeconds = 300
    ): SignedRiskPayload {
        return {
            poolId,
            expectedLpLoss: Math.floor(result.expectedLpLossUSD),
            expectedLeakage: Math.floor(result.expectedLeakageUSD),
            toxicityScore: result.toxicityScore,
            recommendedSpread: Math.floor(result.recommendedSpread),
            expiry: Math.floor(Date.now() / 1000) + expirySeconds,
            nonce: this.nonce++,
            signer
        };
    }
}
