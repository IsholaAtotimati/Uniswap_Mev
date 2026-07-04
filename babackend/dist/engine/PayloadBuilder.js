export class PayloadBuilder {
    nonce = 0;
    build(result, poolId, signer, expirySeconds = 300) {
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
