import { DetectorResult } from "../models/DetectorResult.js";
import { FeatureVector } from "../engine/FeatureExtractor.js";

export class ArbitrageDetector {

    analyze(features: FeatureVector): DetectorResult {

        let score = 0;

        score += features.recentVolatility * 0.6;

        score += features.priceImpact * 0.4;

        return {
            name: "Arbitrage",
            score: Math.min(score, 1),
            confidence: 0.87,
            reason: "Cross-market arbitrage probability"
        };

    }

}