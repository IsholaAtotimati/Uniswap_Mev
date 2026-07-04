import { FeatureExtractor } from "./FeatureExtractor.js";
import { RiskAggregator } from "./RiskAggregator.js";
import { LossEstimator } from "./LossEstimator.js";
import { FeeRecommendationEngine } from "./FeeRecommendationEngine.js";
import { PolicyValidator } from "./PolicyValidator.js";
import { SandwichDetector } from "../detectors/SandwichDetector.js";
import { ToxicFlowDetector } from "../detectors/ToxicFlowDetector.js";
import { ArbitrageDetector } from "../detectors/ArbitrageDetector.js";
import { WalletProfiler } from "../detectors/WalletProfiler.js";
import { RiskLevel } from "../types/enums.js";
export class RiskEngine {
    extractor;
    sandwich;
    toxic;
    arbitrage;
    wallet;
    aggregator;
    estimator;
    feeEngine;
    validator;
    constructor(extractor = new FeatureExtractor(), sandwich = new SandwichDetector(), toxic = new ToxicFlowDetector(), arbitrage = new ArbitrageDetector(), wallet = new WalletProfiler(), aggregator = new RiskAggregator(), estimator = new LossEstimator(), feeEngine = new FeeRecommendationEngine(), validator = new PolicyValidator()) {
        this.extractor = extractor;
        this.sandwich = sandwich;
        this.toxic = toxic;
        this.arbitrage = arbitrage;
        this.wallet = wallet;
        this.aggregator = aggregator;
        this.estimator = estimator;
        this.feeEngine = feeEngine;
        this.validator = validator;
    }
    async analyzeSwap(context) {
        const features = await this.extractor.extract(context);
        // 🔥 run detectors in parallel (important upgrade)
        const [sandwichResult, toxicResult, arbitrageResult, walletResult] = await Promise.all([
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
        const aggregate = this.aggregator.aggregate(detectorResults);
        const loss = this.estimator.estimate(aggregate.finalRiskScore, features);
        const fee = this.feeEngine.recommend(aggregate.finalRiskScore, loss.expectedLpLossUSD);
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
            riskLevel: aggregate.finalRiskScore > 0.85
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
