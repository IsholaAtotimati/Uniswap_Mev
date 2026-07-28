import { HookSimulator } from "./HookSimulator.js";
import { RiskLevel } from "../types/enums.js";

describe("HookSimulator", () => {
    const simulator = new HookSimulator();

    it("rejects swaps with a high sandwich score", () => {
        const decision = simulator.beforeSwap({
            sandwichScore: 0.9,
            toxicityScore: 0.1,
            arbitrageScore: 0.2,
            walletScore: 0.1,
            volatilityScore: 0.2,
            finalRiskScore: 9500,
            confidence: 0.95,
            riskLevel: RiskLevel.CRITICAL,
            expectedLpLossUSD: 120,
            expectedLeakageUSD: 30,
            expectedPriceImpact: 0.35,
            recommendedSpread: 1800
        });

        expect(decision.reject).toBe(true);
        expect(decision.action).toBe("BLOCK");
        expect(decision.fee).toBe(0);
        expect(decision.reason).toBe("sandwich attack detected");
    });

    it("rejects expired transactions", () => {
        const decision = simulator.beforeSwap({
            sandwichScore: 0.1,
            toxicityScore: 0.1,
            arbitrageScore: 0.1,
            walletScore: 0.1,
            volatilityScore: 0.1,
            finalRiskScore: 2000,
            confidence: 0.7,
            riskLevel: RiskLevel.LOW,
            expectedLpLossUSD: 5,
            expectedLeakageUSD: 1,
            expectedPriceImpact: 0.05,
            recommendedSpread: 30
        }, Date.now() - 1000);

        expect(decision.reject).toBe(true);
        expect(decision.action).toBe("BLOCK");
        expect(decision.fee).toBe(0);
        expect(decision.reason).toBe("deadline exceeded");
    });
});
