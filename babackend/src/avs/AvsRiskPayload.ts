export type AvsRiskPayload = {
    poolId: string;

    finalRiskScore: number;
    recommendedSpread: number;
    expectedLpLoss: number;

    quorum: number;
    blockNumber: number;
    timestamp: number;

    nonce: number;
};