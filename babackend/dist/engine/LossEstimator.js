export class LossEstimator {
    estimate(risk, features) {
        const expectedLpLossUSD = risk *
            features.swapValueUSD *
            features.priceImpact;
        const expectedLeakageUSD = expectedLpLossUSD *
            0.65;
        return {
            expectedLpLossUSD,
            expectedLeakageUSD
        };
    }
}
