import { ethers } from "ethers";
import { logger } from "../config/logger.js";
import { env } from "../config/env.js";
function toBigInt(value, fallback) {
    if (typeof value === "bigint") {
        return value;
    }
    if (typeof value === "number" && Number.isFinite(value)) {
        return BigInt(Math.trunc(value));
    }
    if (typeof value === "string" && value.trim() !== "") {
        return BigInt(value);
    }
    return fallback;
}
export function normalizeHookPolicy(input = {}) {
    const quorumThreshold = toBigInt(input.quorumThreshold, 1n);
    const maxExpectedLpLoss = toBigInt(input.maxExpectedLpLoss, 0n);
    const maxExpectedLeakage = toBigInt(input.maxExpectedLeakage, 0n);
    const maxToxicityScore = toBigInt(input.maxToxicityScore, 0n);
    const maxRecommendedSpread = toBigInt(input.maxRecommendedSpread, 20000n);
    return {
        quorumThreshold: quorumThreshold > 0n ? quorumThreshold : 1n,
        maxExpectedLpLoss,
        maxExpectedLeakage,
        maxToxicityScore,
        maxRecommendedSpread: maxRecommendedSpread > 20000n ? 20000n : maxRecommendedSpread,
        rejectOnThreshold: Boolean(input.rejectOnThreshold)
    };
}
export function serializeHookPolicy(policy) {
    return {
        quorumThreshold: policy.quorumThreshold.toString(),
        maxExpectedLpLoss: policy.maxExpectedLpLoss.toString(),
        maxExpectedLeakage: policy.maxExpectedLeakage.toString(),
        maxToxicityScore: policy.maxToxicityScore.toString(),
        maxRecommendedSpread: policy.maxRecommendedSpread.toString(),
        rejectOnThreshold: policy.rejectOnThreshold
    };
}
export class HookClient {
    hookAddress;
    hookAbi;
    provider;
    wallet;
    constructor(hookAddress, hookAbi) {
        this.hookAddress = hookAddress;
        this.hookAbi = hookAbi;
        const rpcUrl = env.RPC_URL || "http://localhost:8545";
        this.provider = new ethers.JsonRpcProvider(rpcUrl);
        if (env.PRIVATE_KEY) {
            this.wallet = new ethers.Wallet(env.PRIVATE_KEY, this.provider);
        }
    }
    async configurePolicy(policy) {
        if (!this.wallet) {
            throw new Error("PRIVATE_KEY not configured; cannot configure policy");
        }
        try {
            const contract = new ethers.Contract(this.hookAddress, this.hookAbi, this.wallet);
            const tx = await contract.setRiskPolicy(policy.maxExpectedLpLoss, policy.maxExpectedLeakage, policy.maxToxicityScore, policy.maxRecommendedSpread, policy.rejectOnThreshold, {
                gasLimit: 500000
            });
            const receipt = await tx.wait();
            logger.info({ msg: "Hook policy updated", txHash: receipt?.transactionHash, blockNumber: receipt?.blockNumber });
            return [receipt?.transactionHash || tx.hash];
        }
        catch (error) {
            const message = error instanceof Error ? error.message : "Unknown error";
            logger.error({ msg: "Failed to configure hook policy", error: message });
            throw error;
        }
    }
    async submitPayload(params) {
        if (!this.wallet) {
            throw new Error("PRIVATE_KEY not configured; cannot submit payload");
        }
        try {
            const contract = new ethers.Contract(this.hookAddress, this.hookAbi, this.wallet);
            logger.info({
                msg: "Submitting payload to hook",
                hook: this.hookAddress,
                poolId: params.payload.poolId
            });
            // Ensure settlementAmount is provided as an integer in token base
            // units (default 18 decimals). Protect against floats and
            // non-numeric strings.
            const payloadForContract = { ...params.payload };
            try {
                const raw = payloadForContract.settlementAmount;
                if (raw === undefined || raw === null) {
                    payloadForContract.settlementAmount = 0n;
                }
                else if (typeof raw === "bigint") {
                    // already fine
                }
                else if (typeof raw === "number") {
                    // convert human-readable number to base units
                    payloadForContract.settlementAmount = ethers.parseUnits(String(raw), 18);
                }
                else if (typeof raw === "string") {
                    if (/^-?\d+(?:\.\d+)?$/.test(raw)) {
                        payloadForContract.settlementAmount = ethers.parseUnits(raw, 18);
                    }
                    else {
                        payloadForContract.settlementAmount = BigInt(raw);
                    }
                }
                else {
                    payloadForContract.settlementAmount = BigInt(raw);
                }
            }
            catch (parseErr) {
                logger.warn({ msg: "Failed to normalize settlementAmount; using zero", error: parseErr instanceof Error ? parseErr.message : String(parseErr) });
                payloadForContract.settlementAmount = 0n;
            }
            // Disambiguate overloaded submitRiskPayload by using the fully
            // qualified function signature to avoid ethers' ambiguous function
            // resolution when multiple overloads exist.
            const fnSig = "submitRiskPayload((address,address,uint24,int24,address),(bytes32,uint256,uint256,uint256,uint24,address,uint256,uint32,bytes32,uint256,uint256,address),(address,bytes)[])";
            let tx;
            try {
                if (typeof contract[fnSig] === "function") {
                    tx = await contract[fnSig](params.key, payloadForContract, params.attestations, {
                        gasLimit: 500000
                    });
                }
                else {
                    // Fallback to the plain call if the signature isn't available
                    tx = await contract.submitRiskPayload(params.key, payloadForContract, params.attestations, {
                        gasLimit: 500000
                    });
                }
            }
            catch (callErr) {
                const errMsg = callErr instanceof Error ? callErr.message : String(callErr);
                logger.warn({ msg: "Contract call failed; attempting encoded fallback", error: errMsg });
                // If ethers can't disambiguate overloads, encode the calldata
                // using the exact function signature and send a raw tx via the
                // configured wallet. This avoids relying on runtime method
                // resolution.
                try {
                    const data = contract.interface.encodeFunctionData(fnSig, [
                        params.key,
                        payloadForContract,
                        params.attestations
                    ]);
                    if (!this.wallet) {
                        throw new Error("PRIVATE_KEY not configured; cannot submit payload (encoded fallback)");
                    }
                    const txRequest = {
                        to: this.hookAddress,
                        data,
                        gasLimit: 500000
                    };
                    tx = await this.wallet.sendTransaction(txRequest);
                }
                catch (encodeErr) {
                    const message = encodeErr instanceof Error ? encodeErr.message : String(encodeErr);
                    logger.error({ msg: "Encoded fallback failed", error: message });
                    throw encodeErr;
                }
            }
            const receipt = await tx.wait();
            logger.info({ msg: "Payload submitted successfully", txHash: receipt?.transactionHash, blockNumber: receipt?.blockNumber });
            return receipt?.transactionHash || tx.hash;
        }
        catch (error) {
            const message = error instanceof Error ? error.message : "Unknown error";
            logger.error({ msg: "Failed to submit payload", error: message });
            throw error;
        }
    }
    async getSettlementStatus(settlementId) {
        try {
            const contract = new ethers.Contract(this.hookAddress, this.hookAbi, this.provider);
            const settlement = await contract.settlements(settlementId);
            return settlement;
        }
        catch (error) {
            logger.error({
                msg: "Failed to get settlement status",
                error: error instanceof Error ? error.message : "Unknown error"
            });
            throw error;
        }
    }
}
