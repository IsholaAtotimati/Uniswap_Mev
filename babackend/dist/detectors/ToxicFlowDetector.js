export class ToxicFlowDetector {
    analyze(features) {
        let score = 0;
        if (features.walletFrequency > 25)
            score += 0.30;
        if (features.recentVolatility > 0.25)
            score += 0.25;
        if (features.uniqueWallets24h < 150)
            score += 0.25;
        if (features.utilization > 0.30)
            score += 0.20;
        return {
            name: "ToxicFlow",
            score: Math.min(score, 1),
            confidence: 0.88,
            reason: "Toxic order flow"
        };
    }
}
