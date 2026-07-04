export interface WalletProfile {
    address: string;

    ageInDays: number;

    totalSwaps: number;

    averageGasPrice: bigint;

    averageTradeSize: bigint;

    previousSandwichFlags: number;

    previousArbitrageFlags: number;

    previousToxicFlags: number;

    reputationScore: number;

    lastSeenBlock: number;
}