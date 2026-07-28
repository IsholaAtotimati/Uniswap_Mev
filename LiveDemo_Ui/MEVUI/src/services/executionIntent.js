import api from "./api";

// Use environment variables or fallback to common token standards
const TOKEN_ADDRESS_MAP = {
    // Native token (ETH or similar)
    ETH: import.meta.env.VITE_ETH || "0x0000000000000000000000000000000000000001",
    // USDC token address from Arc testnet
    USDC: import.meta.env.VITE_USDC || "0x3600000000000000000000000000000000000000"
};

export async function analyzeRisk(data){
    const response = await api.post(
        "/api/analyze",
        data
    );

    return response.data;
}

export async function createExecutionIntent(data){
    const tokenInAddress = TOKEN_ADDRESS_MAP[data.tokenIn] || data.tokenIn;
    const tokenOutAddress = TOKEN_ADDRESS_MAP[data.tokenOut] || data.tokenOut;

    const response = await api.post(
        "/swap/analyze",
        {
            userWallet: data.userWallet || "0x1111111111111111111111111111111111111111",
            poolId: data.poolId || "ETH-USDC",
            tokenIn: tokenInAddress,
            tokenOut: tokenOutAddress,
            amountIn: data.amount,
            recipient: data.recipient || "0x2222222222222222222222222222222222222222",
            destinationDomain: data.destinationDomain || 0
        }
    );
    return response.data;
}