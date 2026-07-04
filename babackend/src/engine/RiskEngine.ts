import { FeatureExtractor } from "./FeatureExtractor.js";
import { RiskAggregator } from "./RiskAggregator.js";
import { LossEstimator } from "./LossEstimator.js";
import { FeeRecommendationEngine } from "./FeeRecommendationEngine.js";
import { PolicyValidator } from "./PolicyValidator.js";

import { SandwichDetector } from "../detectors/SandwichDetector.js";
import { ToxicFlowDetector } from "../detectors/ToxicFlowDetector.js";
import { ArbitrageDetector } from "../detectors/ArbitrageDetector.js";
import { WalletProfiler } from "../detectors/WalletProfiler.js";

import { SwapContext } from "../models/SwapContext.js";
import { RiskLevel } from "../types/enums.js";
import { RiskResult } from "../models/RiskResult.js";

export class RiskEngine {

    constructor(
        private extractor = new FeatureExtractor(),
        private sandwich = new SandwichDetector(),
        private toxic = new ToxicFlowDetector(),
        private arbitrage = new ArbitrageDetector(),
        private wallet = new WalletProfiler(),
        private aggregator = new RiskAggregator(),
        private estimator = new LossEstimator(),
        private feeEngine = new FeeRecommendationEngine(),
        private validator = new PolicyValidator()
    ) {}

    async analyzeSwap(context: SwapContext): Promise<RiskResult> {

        const features =
            await this.extractor.extract(context);

        // 🔥 run detectors in parallel (important upgrade)
        const [
            sandwichResult,
            toxicResult,
            arbitrageResult,
            walletResult
        ] = await Promise.all([
            this.sandwich.analyze(features),
            this.toxic.analyze(features),
            this.arbitrage.analyze(features),
            this.wallet.analyze(features)
        ]);

        const detectorResults = [
            sandwichResult,
            toxicResult,
            arbitrageResult,
            walletResult
        ];

        const aggregate =
            this.aggregator.aggregate(detectorResults);

        const loss =
            this.estimator.estimate(
                aggregate.finalRiskScore,
                features
            );

        const fee =
            this.feeEngine.recommend(
                aggregate.finalRiskScore,
                loss.expectedLpLossUSD
            );

        if (!this.validator.validate(fee, aggregate.confidence)) {
            throw new Error("Risk policy validation failed.");
        }

        return {
            sandwichScore: sandwichResult.score,
            toxicityScore: toxicResult.score,
            arbitrageScore: arbitrageResult.score,
            walletScore: walletResult.score,

            volatilityScore: features.recentVolatility,

            finalRiskScore: Math.floor(aggregate.finalRiskScore * 10000),
            confidence: aggregate.confidence,

            riskLevel:
                aggregate.finalRiskScore > 0.85
                    ? RiskLevel.CRITICAL
                    : aggregate.finalRiskScore > 0.65
                    ? RiskLevel.HIGH
                    : aggregate.finalRiskScore > 0.35
                    ? RiskLevel.MEDIUM
                    : RiskLevel.LOW,

            expectedLpLossUSD: loss.expectedLpLossUSD,
            expectedLeakageUSD: loss.expectedLeakageUSD,
            expectedPriceImpact: features.priceImpact,

            recommendedSpread: fee
        };
    }
}