export class FeatureExtractor {
    async extract(context) {
        const liquidityUSD = Number(context.liquidity) / 1e18;
        const swapValueUSD = Math.abs(Number(context.amount0)) / 1e18;
        const utilization = swapValueUSD / Math.max(liquidityUSD, 1);
        return {
            swapValueUSD,
            liquidityUSD,
            utilization,
            priceImpact: utilization,
            gasPriceGwei: Number(context.gasPrice) / 1e9,
            recentVolatility: 0.18,
            walletAgeDays: 250,
            walletFrequency: 18,
            recentPoolVolumeUSD: 850000,
            uniqueWallets24h: 480,
            pendingTxDensity: 0.42
        };
    }
}
