import { DetectorResult } from "../models/DetectorResult.js";
import { FeatureVector } from "../engine/FeatureExtractor.js";

export class WalletProfiler {

    analyze(features: FeatureVector): DetectorResult {

        let score = 0;

        if (features.walletAgeDays < 30)
            score += 0.40;

        if (features.walletFrequency > 50)
            score += 0.35;

        if (features.gasPriceGwei > 80)
            score += 0.25;

        return {
            name: "WalletProfiler",
            score: Math.min(score, 1),
            confidence: 0.82,
            reason: "Wallet reputation"
        };

    }

}