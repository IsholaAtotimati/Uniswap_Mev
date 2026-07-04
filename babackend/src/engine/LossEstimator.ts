import { FeatureVector } from "./FeatureExtractor.js";

export class LossEstimator {

    estimate(
        risk: number,
        features: FeatureVector
    ) {

        const expectedLpLossUSD =
            risk *
            features.swapValueUSD *
            features.priceImpact;

        const expectedLeakageUSD =
            expectedLpLossUSD *
            0.65;

        return {

            expectedLpLossUSD,

            expectedLeakageUSD

        };

    }

}