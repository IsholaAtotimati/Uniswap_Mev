export const ARC = {
    id: Number(import.meta.env.VITE_CHAIN_ID),

    name: "Arc",

    rpcUrl: import.meta.env.VITE_RPC_URL,

    nativeCurrency: {
        name: "Ether",
        symbol: "ETH",
        decimals: 18,
    },
};