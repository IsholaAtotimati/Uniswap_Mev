import { RiskLevel } from "../types/enums.js";

export interface RiskResult {

    sandwichScore: number;

    toxicityScore: number;

    arbitrageScore: number;

    walletScore: number;

    volatilityScore: number;

    finalRiskScore: number;

    confidence: number;

    riskLevel: RiskLevel;

    expectedLpLossUSD: number;

    expectedLeakageUSD: number;

    expectedPriceImpact: number;

    recommendedSpread: number;

}