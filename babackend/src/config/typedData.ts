import { env } from "./env.js";

export const DOMAIN = {
    name: "MEVShieldHook",
    version: "1",
    chainId: env.CHAIN_ID,
    verifyingContract: env.VERIFYING_CONTRACT
};

export const TYPES = {
    LossPayload: [
        { name: "poolId", type: "bytes32" },
        { name: "expectedLpLoss", type: "uint256" },
        { name: "expectedLeakage", type: "uint256" },
        { name: "toxicityScore", type: "uint256" },
        { name: "recommendedSpread", type: "uint24" },
        { name: "expiry", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "signer", type: "address" }
    ]
};