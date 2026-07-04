import express from "express";
import { RiskEngine } from "./engine/RiskEngine.js";
import { SwapDirection } from "./types/enums.js";
export const app = express();
app.use(express.json());
const riskEngine = new RiskEngine();
function buildSwapContext(payload) {
    const amount = Number(payload.amount || 1000);
    const scaledAmount = BigInt(Math.round(Math.max(1, amount) * 1e18));
    return {
        poolId: payload.pool || "ETH-USDC",
        blockNumber: 12_345_678 + Math.round(amount % 97),
        txHash: `0x${Math.random().toString(16).slice(2, 66)}`,
        sender: "0x1111111111111111111111111111111111111111",
        recipient: "0x2222222222222222222222222222222222222222",
        token0: "0x0000000000000000000000000000000000000001",
        token1: "0x0000000000000000000000000000000000000002",
        amount0: scaledAmount,
        amount1: scaledAmount / 1000n * 999n,
        sqrtPriceX96: 2000000000000000n,
        liquidity: 2000000000000000000n,
        tick: 120_000,
        fee: 3000,
        gasPrice: 35000000000n,
        timestamp: Date.now(),
        direction: SwapDirection.ZERO_FOR_ONE
    };
}
app.get("/health", (_, res) => {
    res.json({
        status: "healthy",
        service: "MEVShield Risk Engine"
    });
});
app.post("/api/analyze", async (req, res) => {
    try {
        const payload = req.body ?? {};
        const context = buildSwapContext(payload);
        const result = await riskEngine.analyzeSwap(context);
        res.json({
            riskScore: Math.min(99, Math.round(result.finalRiskScore / 100)),
            toxicity: result.toxicityScore > 0.75 ? "HIGH" : result.toxicityScore > 0.5 ? "MEDIUM" : "LOW",
            recommendedSpread: result.recommendedSpread,
            feePercent: `${(result.recommendedSpread / 100).toFixed(2)}%`,
            verified: true,
            pool: context.poolId,
            confidence: result.confidence,
            riskLevel: result.riskLevel,
            expectedLpLossUSD: result.expectedLpLossUSD,
            expectedLeakageUSD: result.expectedLeakageUSD,
            expectedPriceImpact: result.expectedPriceImpact
        });
    }
    catch (error) {
        res.status(500).json({
            error: error instanceof Error ? error.message : "Risk analysis failed"
        });
    }
});
