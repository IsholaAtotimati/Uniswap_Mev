export type SignedRiskPayload = {
    poolId: string;
    expectedLpLoss: number;
    expectedLeakage: number;
    toxicityScore: number;
    recommendedSpread: number;
    expiry: number;
    nonce: number;
    signer: string;
};