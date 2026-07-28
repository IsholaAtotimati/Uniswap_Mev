import { ethers } from "ethers";
import { logger } from "../config/logger.js";
import { env } from "../config/env.js";

export interface SubmitPayloadParams {
    key: {
        currency0: string;
        currency1: string;
        fee: number;
        tickSpacing: number;
        hooks: string;
    };
    payload: {
        poolId: string;
        expectedLpLoss: number;
        expectedLeakage: number;
        toxicityScore: number;
        recommendedSpread: number;
        settlementToken: string;
        settlementAmount: number | string | bigint;
        destinationDomain: number;
        recipient: string;
        expiry: number;
        nonce: number;
        signer: string;
    };
    attestations: Array<{operator: string; signature: string}>;
}

export interface HookPolicyConfig {
    quorumThreshold?: number | string | bigint;
    maxExpectedLpLoss?: number | string | bigint;
    maxExpectedLeakage?: number | string | bigint;
    maxToxicityScore?: number | string | bigint;
    maxRecommendedSpread?: number | string | bigint;
    rejectOnThreshold?: boolean;
}

export interface NormalizedHookPolicy {
    quorumThreshold: bigint;
    maxExpectedLpLoss: bigint;
    maxExpectedLeakage: bigint;
    maxToxicityScore: bigint;
    maxRecommendedSpread: bigint;
    rejectOnThreshold: boolean;
}

function toBigInt(value: unknown, fallback: bigint): bigint {
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

export function normalizeHookPolicy(input: HookPolicyConfig = {}): NormalizedHookPolicy {
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

export function serializeHookPolicy(policy: NormalizedHookPolicy) {
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
    private provider: ethers.Provider;
    private wallet?: ethers.Wallet;

    constructor(
        private hookAddress: string,
        private hookAbi: any[]
    ) {
        const rpcUrl = env.RPC_URL || "http://localhost:8545";
        this.provider = new ethers.JsonRpcProvider(rpcUrl);

        if (env.PRIVATE_KEY) {
            this.wallet = new ethers.Wallet(env.PRIVATE_KEY, this.provider);
        }
    }

    /**
     * Validate common on-chain and env configuration that can break EIP-712 signing.
     * Returns an array of warning strings (empty if all checks pass).
     */
    async validateOnchainSetup(): Promise<string[]> {
        const warnings: string[] = [];

        const contract = new ethers.Contract(this.hookAddress, this.hookAbi, this.provider);

        // Check chain id
        try {
            const network = await this.provider.getNetwork();
            const providerChainId = Number(network.chainId);
            const envChainId = Number(env.CHAIN_ID || 0);
            if (envChainId === 0) {
                warnings.push("env.CHAIN_ID is not set; signatures may target wrong chainId");
            } else if (envChainId !== providerChainId) {
                warnings.push(`CHAIN_ID mismatch: env=${envChainId} provider=${providerChainId}`);
            }
        } catch (err) {
            warnings.push("Failed to read provider chainId");
        }

        // Check verifying contract in env matches hook address used for signing
        try {
            const verifying = env.VERIFYING_CONTRACT || "";
            if (!verifying) {
                warnings.push("env.VERIFYING_CONTRACT is not set; typed-data domain may be incorrect");
            } else if (verifying.toLowerCase() !== this.hookAddress.toLowerCase()) {
                warnings.push(`VERIFYING_CONTRACT mismatch: env=${verifying} hook=${this.hookAddress}`);
            }
        } catch (err) {
            warnings.push("Failed to validate VERIFYING_CONTRACT env var");
        }

        // If wallet is present, check whether that address is a trusted signer on-chain
        if (this.wallet) {
            try {
                const isTrusted = await contract.isTrustedSigner(this.wallet.address);
                if (!isTrusted) {
                    warnings.push(`Configured wallet address ${this.wallet.address} is not a trusted signer on-chain`);
                }
            } catch (err) {
                warnings.push("Failed to read isTrustedSigner from hook contract");
            }
        }

        // Check quorum threshold
        try {
            const quorum = await contract.quorumThreshold();
            if (BigInt(quorum) === 0n) {
                warnings.push("quorumThreshold is 0 on-chain; no attestations will be accepted");
            }
        } catch (err) {
            warnings.push("Failed to read quorumThreshold from hook contract");
        }

        // Check settlementRelayer presence
        try {
            const relayer = await contract.settlementRelayer();
            if (!relayer || relayer === ethers.ZeroAddress) {
                warnings.push("settlementRelayer is not set on-chain; settlements cannot be progressed");
            }
        } catch (err) {
            warnings.push("Failed to read settlementRelayer from hook contract");
        }

        return warnings;
    }

    async configurePolicy(policy: NormalizedHookPolicy): Promise<string[]> {
        if (!this.wallet) {
            throw new Error("PRIVATE_KEY not configured; cannot configure policy");
        }

        try {
            const contract = new ethers.Contract(
                this.hookAddress,
                this.hookAbi,
                this.wallet
            );

            const tx = await contract.setRiskPolicy(
                policy.maxExpectedLpLoss,
                policy.maxExpectedLeakage,
                policy.maxToxicityScore,
                policy.maxRecommendedSpread,
                policy.rejectOnThreshold,
                {
                    gasLimit: 500000
                }
            );

            const receipt = await tx.wait();
            logger.info({ msg: "Hook policy updated", txHash: receipt?.transactionHash, blockNumber: receipt?.blockNumber });
            return [receipt?.transactionHash || tx.hash];
        } catch (error) {
            const message = error instanceof Error ? error.message : "Unknown error";
            logger.error({ msg: "Failed to configure hook policy", error: message });
            throw error;
        }
    }

    async submitPayload(params: SubmitPayloadParams): Promise<string> {
        if (!this.wallet) {
            throw new Error("PRIVATE_KEY not configured; cannot submit payload");
        }
        try {
            const contract = new ethers.Contract(
                this.hookAddress,
                this.hookAbi,
                this.wallet
            );

            logger.info({
                msg: "Submitting payload to hook",
                hook: this.hookAddress,
                poolId: params.payload.poolId
            });

            // Ensure settlementAmount is provided as an integer in token base
            // units (default 18 decimals). Protect against floats and
            // non-numeric strings.
            const payloadForContract: any = { ...params.payload };
            try {
                const raw = payloadForContract.settlementAmount;
                if (raw === undefined || raw === null) {
                    payloadForContract.settlementAmount = 0n;
                } else if (typeof raw === "bigint") {
                    // already fine
                } else if (typeof raw === "number") {
                    // convert human-readable number to base units
                    payloadForContract.settlementAmount = ethers.parseUnits(String(raw), 18);
                } else if (typeof raw === "string") {
                    if (/^-?\d+(?:\.\d+)?$/.test(raw)) {
                        payloadForContract.settlementAmount = ethers.parseUnits(raw, 18);
                    } else {
                        payloadForContract.settlementAmount = BigInt(raw);
                    }
                } else {
                    payloadForContract.settlementAmount = BigInt(raw);
                }
            } catch (parseErr) {
                logger.warn({ msg: "Failed to normalize settlementAmount; using zero", error: parseErr instanceof Error ? parseErr.message : String(parseErr) });
                payloadForContract.settlementAmount = 0n;
            }

            // Disambiguate overloaded submitRiskPayload by using the fully
            // qualified function signature to avoid ethers' ambiguous function
            // resolution when multiple overloads exist.
            const fnSig = "submitRiskPayload((address,address,uint24,int24,address),(bytes32,uint256,uint256,uint256,uint24,address,uint256,uint32,bytes32,uint256,uint256,address),(address,bytes)[])";

            let tx;
            try {
                if (typeof (contract as any)[fnSig] === "function") {
                    tx = await (contract as any)[fnSig](
                        params.key,
                        payloadForContract,
                        params.attestations,
                        {
                            gasLimit: 500000
                        }
                    );
                } else {
                    // Fallback to the plain call if the signature isn't available
                    tx = await contract.submitRiskPayload(
                        params.key,
                        payloadForContract,
                        params.attestations,
                        {
                            gasLimit: 500000
                        }
                    );
                }
            } catch (callErr) {
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
                    } as any;

                    tx = await this.wallet.sendTransaction(txRequest);
                } catch (encodeErr) {
                    const message = encodeErr instanceof Error ? encodeErr.message : String(encodeErr);
                    logger.error({ msg: "Encoded fallback failed", error: message });
                    throw encodeErr;
                }
            }

            const receipt = await tx.wait();
            logger.info({ msg: "Payload submitted successfully", txHash: receipt?.transactionHash, blockNumber: receipt?.blockNumber });

            return receipt?.transactionHash || tx.hash;
        } catch (error) {
            const message = error instanceof Error ? error.message : "Unknown error";
            logger.error({ msg: "Failed to submit payload", error: message });
            throw error;
        }
    }

    async getSettlementStatus(settlementId: string): Promise<{
        amount: number;
        destinationDomain: number;
        token: string;
        settled: boolean;
    }> {
        try {
            const contract = new ethers.Contract(
                this.hookAddress,
                this.hookAbi,
                this.provider
            );

            const settlement = await contract.settlements(settlementId);
            return settlement;
        } catch (error) {
            logger.error({
                msg: "Failed to get settlement status",
                error: error instanceof Error ? error.message : "Unknown error"
            });
            throw error;
        }
    }
}
