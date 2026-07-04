export class SandwichDetector {
    analyze(features) {
        let score = 0;
        if (features.utilization > 0.25)
            score += 0.35;
        if (features.priceImpact > 0.20)
            score += 0.25;
        if (features.pendingTxDensity > 0.50)
            score += 0.20;
        if (features.gasPriceGwei > 40)
            score += 0.20;
        score = Math.min(score, 1);
        return {
            name: "Sandwich",
            score,
            confidence: 0.91,
            reason: "Sandwich probability",
            metadata: {
                utilization: features.utilization,
                gas: features.gasPriceGwei
            }
        };
    }
}
