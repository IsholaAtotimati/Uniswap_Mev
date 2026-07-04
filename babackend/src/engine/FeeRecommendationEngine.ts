import { BASE_FEE, MAX_FEE } from "../config/constants.js";

export class FeeRecommendationEngine {

    recommend(
        risk: number,
        expectedLossUSD: number
    ) {

        let fee =
            BASE_FEE +
            risk * 300 +
            expectedLossUSD * 0.02;

        fee = Math.min(
            fee,
            MAX_FEE
        );

        return Math.round(fee);

    }

}