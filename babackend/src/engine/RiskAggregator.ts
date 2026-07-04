import { DetectorResult } from "../models/DetectorResult.js";

export class RiskAggregator {

    aggregate(results: DetectorResult[]) {

        const weightedRisk =
            results.reduce(
                (sum, detector) =>
                    sum + detector.score * detector.confidence,
                0
            );

        const confidence =
            results.reduce(
                (sum, detector) =>
                    sum + detector.confidence,
                0
            ) / results.length;

        const normalizedRisk =
            weightedRisk /
            results.reduce(
                (sum, detector) =>
                    sum + detector.confidence,
                0
            );

        return {

            finalRiskScore: normalizedRisk,

            confidence

        };

    }

}