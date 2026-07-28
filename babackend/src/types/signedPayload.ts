export type SignedRiskPayload = {
    poolId: string;
    expectedLpLoss: number;
    expectedLeakage: number;
    toxicityScore: number;
    recommendedSpread: number;
    settlementToken: string;
    settlementAmount: number;
    destinationDomain: number;
    recipient: string;
    expiry: number;
    nonce: number;
    signer: string;
};

export type Attestation = {
    operator: string;
    signature: string;
};