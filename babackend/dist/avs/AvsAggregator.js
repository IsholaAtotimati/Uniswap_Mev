export class AvsAggregator {
    threshold;
    constructor(threshold) {
        this.threshold = threshold;
    }
    aggregate(votes) {
        const validVotes = this.verifyVotes(votes);
        if (validVotes.length < this.threshold) {
            throw new Error("INSUFFICIENT_QUORUM");
        }
        const avgRisk = validVotes.reduce((a, v) => a + v.finalRiskScore, 0)
            / validVotes.length;
        const avgSpread = validVotes.reduce((a, v) => a + v.recommendedSpread, 0)
            / validVotes.length;
        const avgLoss = validVotes.reduce((a, v) => a + v.expectedLpLoss, 0)
            / validVotes.length;
        return {
            finalRiskScore: avgRisk,
            recommendedSpread: Math.floor(avgSpread),
            expectedLpLoss: avgLoss,
            quorum: validVotes.length
        };
    }
    verifyVotes(votes) {
        return votes.filter(v => v.signature && v.operator);
    }
}
