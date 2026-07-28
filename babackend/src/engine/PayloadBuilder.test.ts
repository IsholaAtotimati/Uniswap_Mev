import assert from "node:assert/strict";
import test from "node:test";
import { PayloadBuilder } from "./PayloadBuilder.js";
import { RiskLevel } from "../types/enums.js";

test("build preserves a positive settlement amount for tiny loss estimates", () => {
    const builder = new PayloadBuilder();
    const payload = builder.build({
        sandwichScore: 0,
        toxicityScore: 0,
        arbitrageScore: 0,
        walletScore: 0,
        volatilityScore: 0,
        finalRiskScore: 0,
        confidence: 0,
        riskLevel: RiskLevel.LOW,
        expectedLpLossUSD: 0.2,
        expectedLeakageUSD: 0.1,
        expectedPriceImpact: 0,
        recommendedSpread: 10
    }, "0xpool", "0xsigner");

    assert.equal(payload.settlementAmount, 1);
    assert.equal(payload.expectedLpLoss, 1);
    assert.equal(payload.expectedLeakage, 1);
});
