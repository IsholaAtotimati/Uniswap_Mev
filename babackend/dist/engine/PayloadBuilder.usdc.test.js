import assert from "node:assert/strict";
import test from "node:test";
import { PayloadBuilder } from "./PayloadBuilder.js";
import { RiskLevel } from "../types/enums.js";
test("build uses configured USDC settlementToken and preserves bytes32 poolId", () => {
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
        expectedLpLossUSD: 15.75,
        expectedLeakageUSD: 3.4,
        expectedPriceImpact: 0,
        recommendedSpread: 115
    }, "0x0000000000000000000000000000000000000000000000000000000000000001", "0xsigner");
    assert.equal(payload.poolId, "0x0000000000000000000000000000000000000000000000000000000000000001");
    assert.equal(payload.settlementAmount, 16);
    assert.equal(payload.expectedLpLoss, 16);
    assert.equal(payload.expectedLeakage, 3);
    assert.equal(payload.settlementToken, "0x0000000000000000000000000000000000000000");
});
test("buildWithSettlement preserves bytes32 poolId and settlement token", () => {
    const builder = new PayloadBuilder();
    const payload = builder.buildWithSettlement({
        sandwichScore: 0,
        toxicityScore: 0,
        arbitrageScore: 0,
        walletScore: 0,
        volatilityScore: 0,
        finalRiskScore: 0,
        confidence: 0,
        riskLevel: RiskLevel.LOW,
        expectedLpLossUSD: 10.4,
        expectedLeakageUSD: 1.1,
        expectedPriceImpact: 0,
        recommendedSpread: 50
    }, "0xpool", "0xsigner", "0x3600000000000000000000000000000000000000", 42, 0, "0x0000000000000000000000000000000000000000");
    assert.equal(payload.poolId.length, 66);
    assert.equal(payload.settlementToken, "0x3600000000000000000000000000000000000000");
    assert.equal(payload.settlementAmount, 42);
});
