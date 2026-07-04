export interface RiskPayload {

    poolId: string;

    riskScore: number;

    recommendedSpread: number;

    expectedLpLossUSD: number;

    expectedLeakageUSD: number;

    confidence: number;

    expiry: number;

    nonce: bigint;

}