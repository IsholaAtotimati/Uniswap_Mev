type OperatorVote = {
    signature?: string;
    operator?: string;
    finalRiskScore: number;
    recommendedSpread: number;
    expectedLpLoss: number;
};

export class AvsAggregator {

    threshold: number;

    constructor(threshold: number) {
        this.threshold = threshold;
    }

    aggregate(votes: OperatorVote[]) {

        const validVotes = this.verifyVotes(votes);

        if (validVotes.length < this.threshold) {
            throw new Error("INSUFFICIENT_QUORUM");
        }

        const avgRisk =
            validVotes.reduce((a, v) => a + v.finalRiskScore, 0)
            / validVotes.length;

        const avgSpread =
            validVotes.reduce((a, v) => a + v.recommendedSpread, 0)
            / validVotes.length;

        const avgLoss =
            validVotes.reduce((a, v) => a + v.expectedLpLoss, 0)
            / validVotes.length;

        return {
            finalRiskScore: avgRisk,
            recommendedSpread: Math.floor(avgSpread),
            expectedLpLoss: avgLoss,
            quorum: validVotes.length
        };
    }

    verifyVotes(votes: OperatorVote[]) {
        return votes.filter(v => v.signature && v.operator);
    }
}