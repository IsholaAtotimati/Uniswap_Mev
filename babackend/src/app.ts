import express from "express";
import { RiskEngine } from "./engine/RiskEngine.js";
import { SwapContext } from "./models/SwapContext.js";
import { SwapDirection } from "./types/enums.js";
import { PayloadBuilder } from "./engine/PayloadBuilder.js";
import { SignatureService } from "./services/SignatureService.js";
import { SettlementService, SettlementStatus } from "./services/SettlementService.js";
import { HookClient, normalizeHookPolicy, serializeHookPolicy } from "./services/HookClient.js";
import { SettlementEngine } from "./services/SettlementEngine.js";
import { loadHookAbi } from "./listeners/SettlementEventListener.js";
import { logger } from "./config/logger.js";
import { env } from "./config/env.js";
import { ethers } from "ethers";
import { buildSettlementId, normalizeSettlementAmount, toRecipientBytes32 } from "./engine/SwapSubmissionFlow.js";
import { PayloadSigner } from "./engine/PayloadSigner.js";
function corsMiddleware(req: express.Request, res: express.Response, next: express.NextFunction) {
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    if (req.method === "OPTIONS") {
        res.sendStatus(204);
        return;
    }
    next();
}

export const app = express();
app.use(corsMiddleware);
app.use(express.json());


const riskEngine = new RiskEngine();
const payloadBuilder = new PayloadBuilder();
export const settlementService = new SettlementService();

let signatureService: SignatureService | undefined;
let signerAddress: string | undefined;
let hookClient: HookClient | undefined;
let payloadSigner: PayloadSigner | undefined;

if (env.PRIVATE_KEY) {
    payloadSigner = new PayloadSigner(env.PRIVATE_KEY);
}
export const settlementEngine = new SettlementEngine(settlementService, undefined, {
    cctpDelayMs: 0
});

if (env.PRIVATE_KEY) {
    signatureService = new SignatureService(env.PRIVATE_KEY);
    signerAddress = new ethers.Wallet(env.PRIVATE_KEY).address;
}

if (env.HOOK_ADDRESS) {
    const hookAbi = loadHookAbi(env.HOOK_ABI_PATH || "src/abi/MEVShieldHook.json");
    if (!env.USDC || !ethers.isAddress(env.USDC)) {
        throw new Error("USDC address must be configured in environment variable USDC");
    }
    hookClient = new HookClient(env.HOOK_ADDRESS, hookAbi);
}

function buildSwapContext(payload: { pool?: string; amount?: number }): SwapContext {
    const amount = Number(payload.amount || 1000);
    const scaledAmount = BigInt(Math.round(Math.max(1, amount) * 1e18));

    return {
        poolId: payload.pool || "ETH-USDC",
        blockNumber: 12_345_678 + Math.round(amount % 97),
        txHash: `0x${Math.random().toString(16).slice(2, 66)}`,
        sender: "0x1111111111111111111111111111111111111111",
        recipient: "0x2222222222222222222222222222222222222222",
        token0: "0x0000000000000000000000000000000000000001",
        token1: "0x0000000000000000000000000000000000000002",
        amount0: scaledAmount,
        amount1: scaledAmount / 1000n * 999n,
        sqrtPriceX96: 2_000_000_000_000_000n,
        liquidity: 2_000_000_000_000_000_000n,
        tick: 120_000,
        fee: 3000,
        gasPrice: 35_000_000_000n,
        timestamp: Date.now(),
        direction: SwapDirection.ZERO_FOR_ONE
    };
}

function buildPoolKey(tokenIn: string, tokenOut: string) {
    return {
        currency0: tokenIn,
        currency1: tokenOut,
        fee: 3000,
        tickSpacing: 60,
        hooks: "0x0000000000000000000000000000000000000000"
    };
}

function buildPoolId(tokenIn: string, tokenOut: string): string {
     const [currency0, currency1] =
        tokenIn.toLowerCase() < tokenOut.toLowerCase()
         ? [tokenIn, tokenOut]
        : [tokenOut, tokenIn];


    const abiCoder = new ethers.AbiCoder();

    const encoded = abiCoder.encode(
        [
          "address",
          "address",
          "uint24",
          "int24",
          "address"
        ],
        [
          currency0,
          currency1,
          3000,
          60,
          "0x0000000000000000000000000000000000000000"
        ]
    );


    return ethers.keccak256(encoded);
};

app.get("/health", (_, res) => {
    res.json({
        status: "healthy",
        service: "MEVShield Risk Engine"
    });
});

app.get("/api/dashboard/metrics", (_, res) => {
    const dashboardMetrics = {
        totalValue: 12875000,
        mevPrevented: 842500,
        activeSwaps: 18,
        protectedPools: 24,
        recentProtectedSwaps: [
            {
                id: "swap-001",
                pool: "ETH-USDC",
                amount: 1250,
                status: "protected",
                timestamp: Date.now() - 60_000,
                mevSaved: 132.4
            },
            {
                id: "swap-002",
                pool: "WBTC-ETH",
                amount: 420,
                status: "completed",
                timestamp: Date.now() - 180_000,
                mevSaved: 87.9
            },
            {
                id: "swap-003",
                pool: "ARB-USDC",
                amount: 980,
                status: "pending",
                timestamp: Date.now() - 300_000,
                mevSaved: 52.2
            }
        ],
        liveProtectionStatus: {
            activePools: 24,
            avgProtectionScore: 0.91,
            successRate: 0.98
        }
    };


    res.json({
        success: true,
        data: dashboardMetrics,
        timestamp: Date.now()
    });
});

app.get("/api/swaps/events", (_, res) => {
    const now = Date.now();
    const swapEvents = [
        {
            id: "swap-001",
            sender: "0x1111111111111111111111111111111111111111",
            pool: "ETH-USDC",
            tokenIn: "ETH",
            tokenOut: "USDC",
            amountIn: 1,
            minAmountOut: 2482.17,
            settlementId: "0x9d3a9f3b2bd4c1e7f4f5a6b7c8d9e0f123456789",
            signature: {
                payload: {
                    poolId: "0x0f1e2d3c4b5a697887766554433221100ffeeddccbb99887766554433221100",
                    expectedLpLoss: 28,
                    expectedLeakage: 5,
                    toxicityScore: 2800,
                    recommendedSpread: 1,
                    settlementToken: "USDC",
                    settlementAmount: 2482,
                    nonce: 42,
                    expiry: Math.floor(now / 1000) + 30,
                    signer: "0xD87A27143199F9F3659630A1385521Bc597AeE5f"
                },
                signature: "0xabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdef",
                isValid: true
            },
            status: "completed",
            timestamp: now - 120_000,
            txHash: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        },
        {
            id: "swap-002",
            sender: "0x2222222222222222222222222222222222222222",
            pool: "ETH-USDC",
            tokenIn: "ETH",
            tokenOut: "USDC",
            amountIn: 0.5,
            minAmountOut: 1241.08,
            settlementId: "0x4b1c2d3e4f5a6b7c8d9e0f112233445566778899",
            signature: {
                payload: {
                    poolId: "0x0f1e2d3c4b5a697887766554433221100ffeeddccbb99887766554433221100",
                    expectedLpLoss: 16,
                    expectedLeakage: 3,
                    toxicityScore: 2200,
                    recommendedSpread: 2,
                    settlementToken: "USDC",
                    settlementAmount: 1241,
                    nonce: 43,
                    expiry: Math.floor(now / 1000) + 45,
                    signer: "0xD87A27143199F9F3659630A1385521Bc597AeE5f"
                },
                signature: "0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
                isValid: true
            },
            status: "executed",
            timestamp: now - 300_000,
            txHash: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        },
        {
            id: "swap-003",
            sender: "0x3333333333333333333333333333333333333333",
            pool: "ETH-USDC",
            tokenIn: "ETH",
            tokenOut: "USDC",
            amountIn: 2,
            minAmountOut: 4964.34,
            settlementId: "0x7f8e9d0c1b2a3d4e5f6a7b8c9d0e1f1122334455",
            signature: {
                payload: {
                    poolId: "0x0f1e2d3c4b5a697887766554433221100ffeeddccbb99887766554433221100",
                    expectedLpLoss: 40,
                    expectedLeakage: 8,
                    toxicityScore: 3200,
                    recommendedSpread: 3,
                    settlementToken: "USDC",
                    settlementAmount: 4964,
                    nonce: 44,
                    expiry: Math.floor(now / 1000) + 60,
                    signer: "0xD87A27143199F9F3659630A1385521Bc597AeE5f"
                },
                signature: "0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321",
                isValid: false
            },
            status: "verified",
            timestamp: now - 600_000,
            txHash: "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
        }
    ];

    res.json({
        success: true,
        data: swapEvents,
        timestamp: Date.now()
    });
});

app.post("/api/swaps/:id/verify", (req, res) => {
    const { id } = req.params;
    res.json({
        success: true,
        data: {
            valid: true,
            swapId: id
        },
        timestamp: Date.now()
    });
});

app.get("/settlements", (_, res) => {
    res.json(settlementService.listAll());
});

app.get("/settlements/:id", (req, res) => {
    const settlement = settlementService.get(req.params.id);
    if (!settlement) {
        return res.status(404).json({ error: "Settlement not found" });
    }

    res.json(settlement);
});

app.post("/hook/policy", async (req, res) => {
    try {
        if (!hookClient) {
            return res.status(500).json({
                error: "Hook client not initialized. Set HOOK_ADDRESS and PRIVATE_KEY environment variables."
            });
        }

        const normalizedPolicy = normalizeHookPolicy(req.body ?? {});
        const txHashes = await hookClient.configurePolicy(normalizedPolicy);

        res.json({
            status: "updated",
            policy: serializeHookPolicy(normalizedPolicy),
            txHashes
        });
    } catch (error) {
        res.status(500).json({
            error: error instanceof Error ? error.message : "Hook policy update failed"
        });
    }
});

app.post("/api/analyze", async (req, res) => {
    try {
        const payload = req.body ?? {};
        const context = buildSwapContext(payload);
        const result = await riskEngine.analyzeSwap(context);

        res.json({
            riskScore: Math.min(99, Math.round(result.finalRiskScore / 100)),
            toxicity: result.toxicityScore > 0.75 ? "HIGH" : result.toxicityScore > 0.5 ? "MEDIUM" : "LOW",
            recommendedSpread: result.recommendedSpread,
            feePercent: `${(result.recommendedSpread / 10000).toFixed(2)}%`,
            verified: true,
            pool: context.poolId,
            confidence: result.confidence,
            riskLevel: result.riskLevel,
            expectedLpLossUSD: result.expectedLpLossUSD,
            expectedLeakageUSD: result.expectedLeakageUSD,
            expectedPriceImpact: result.expectedPriceImpact
        });
    } catch (error) {
        res.status(500).json({
            error: error instanceof Error ? error.message : "Risk analysis failed"
        });
    }
});

app.post("/api/execution-intent", async (req, res) => {
    try {

        if (!payloadSigner || !signatureService) {
            return res.status(500).json({
                error: "Signer not configured"
            });
        }

        const payload = req.body ?? {};

        const context = buildSwapContext(payload);

        // 1. Run risk engine
        const riskResult = await riskEngine.analyzeSwap(context);


                // 2. Build payload
        const derivedPoolId = buildPoolId(
            context.token0,
            context.token1
        );

        // 2. Build payload
        const riskPayload = payloadBuilder.build(
            riskResult,
            derivedPoolId,
            signerAddress!
        );

        riskPayload.settlementToken = env.USDC;

        // 3. Sign payload
        const signature = await payloadSigner.sign(riskPayload);


        res.json({
            success:true,
            payload:riskPayload,
            signature
        });


    } catch(error){

        res.status(500).json({
            error:error instanceof Error 
              ? error.message 
              : "Execution intent failed"
        });

    }
});
/**
 * POST /swap/analyze
 * Analyzes a swap, builds a signed payload, and creates a settlement tracking record
 * 
 * Request body:
 * {
 *   "userWallet": "0x...",
 *   "poolId": "0x...",
 *   "tokenIn": "0x...",
 *   "tokenOut": "0x...",
 *   "amountIn": "1000000",
 *   "recipient": "0x...",
 *   "destinationDomain": 0
 * }
 */
app.post("/swap/analyze", async (req, res) => {
    try {
        if (!signatureService || !signerAddress) {
            return res.status(500).json({
                error: "Signature service not initialized. Set PRIVATE_KEY environment variable."
            });
        }

        const {
            userWallet,
            poolId,
            tokenIn,
            tokenOut,
            amountIn,
            recipient,
            destinationDomain = 0
        } = req.body;

        if (!userWallet || !poolId || !tokenIn || !tokenOut || !amountIn || !recipient) {
            return res.status(400).json({
                error: "Missing required fields: userWallet, poolId, tokenIn, tokenOut, amountIn, recipient"
            });
        }

        // Build swap context for analysis
        const context = buildSwapContext({ pool: poolId, amount: Number(amountIn) });

        // Run risk analysis
        const result = await riskEngine.analyzeSwap(context);

        const derivedPoolId = buildPoolId(tokenIn, tokenOut);

        // Build payload with settlement info
        const payload = payloadBuilder.build(result, derivedPoolId, signerAddress);

        // Add settlement fields
        const settlementToken = env.USDC;
        const normalizedSettlementAmount = normalizeSettlementAmount(result.expectedLpLossUSD);
        const payloadWithSettlement = {
            ...payload,
            settlementToken,
            settlementAmount: normalizedSettlementAmount,
            destinationDomain,
            recipient: toRecipientBytes32(recipient)
        };

        // Create a quorum-style attestation set from the local signer
        const signature = await signatureService.sign(payloadWithSettlement);
        const attestations = [{ operator: signerAddress, signature }];

        // Create settlement tracking record
        const settlementId = buildSettlementId(derivedPoolId, payload.nonce);

        const settlementAmount = normalizeSettlementAmount(result.expectedLpLossUSD);
        let settlement = settlementService.create(
            settlementId,
            derivedPoolId,
            payload.nonce,
            settlementToken,
            settlementAmount,
            destinationDomain,
            recipient,
            {
                asset: "USDC",
                executionMode: destinationDomain > 0 ? "conditional" : "direct",
                cctpEnabled: true,
                paymasterEnabled: true,
                crossChainEnabled: destinationDomain > 0
            }
        );

        let txHash: string | null = null;
        let submissionStatus = "signed";

        if (hookClient) {
            try {
                const tx = await hookClient.submitPayload({
                    key: buildPoolKey(tokenIn, tokenOut),
                    payload: payloadWithSettlement,
                    attestations
                });

                txHash = tx;
                const updated = settlementService.updateStatus(settlement.settlementId, SettlementStatus.Submitted, txHash);
                if (updated) settlement = updated;
                await settlementEngine.processSettlement(settlement.settlementId, txHash);
                submissionStatus = "submitted";
            } catch (error) {
                const errorMessage = error instanceof Error ? error.message : "Unknown error";
                const updated = settlementService.updateStatus(
                    settlement.settlementId,
                    SettlementStatus.Failed,
                    undefined,
                    { lastError: errorMessage }
                );
                if (updated) settlement = updated;
                submissionStatus = "failed";
                logger.error({
                    msg: "Hook submission failed",
                    settlementId,
                    error: errorMessage
                });
            }
        } else {
            const updated = settlementService.updateStatus(settlement.settlementId, SettlementStatus.Pending);
            if (updated) settlement = updated;
        }

        logger.info({
            msg: "Swap analyzed and signed",
            settlementId,
            poolId,
            riskScore: result.finalRiskScore
        });

        res.json({
            status: submissionStatus,
            settlementId,
            payload: payloadWithSettlement,
            signature,
            txHash,
            settlementStatus: settlement.status
        });
    } catch (error) {
        logger.error({
            msg: "Failed to analyze swap",
            error: error instanceof Error ? error.message : "Unknown error"
        });
        res.status(500).json({
            error: error instanceof Error ? error.message : "Swap analysis failed"
        });
    }
});

/**
 * GET /settlement/status/:id
 * Get the status of a settlement by its ID
 */
app.get("/settlement/status/:id", (req, res) => {
    try {
        const { id } = req.params;
        const settlement = settlementService.get(id);

        if (!settlement) {
            return res.status(404).json({
                error: "Settlement not found"
            });
        }

        res.json({
            settlementId: settlement.settlementId,
            poolId: settlement.poolId,
            status: settlement.status,
            amount: settlement.amount,
            token: settlement.token,
            destinationDomain: settlement.destinationDomain,
            recipient: settlement.recipient,
            txHash: settlement.txHash || null,
            retryCount: settlement.retryCount,
            lastError: settlement.lastError || null,
            createdAt: settlement.createdAt,
            updatedAt: settlement.updatedAt
        });
    } catch (error) {
        res.status(500).json({
            error: error instanceof Error ? error.message : "Failed to get settlement status"
        });
    }
});

/**
 * POST /settlement/submit/:id
 * Manually submit a settlement that is pending (for testing)
 */
app.post("/settlement/submit/:id", (req, res) => {
    try {
        const { id } = req.params;
        const settlement = settlementService.updateStatus(id, SettlementStatus.Submitted);

        if (!settlement) {
            return res.status(404).json({
                error: "Settlement not found"
            });
        }

        res.json({
            status: "updated",
            settlement
        });
    } catch (error) {
        res.status(500).json({
            error: error instanceof Error ? error.message : "Failed to submit settlement"
        });
    }
});

/**
 * GET /settlement/list
 * List all settlements (for debugging)
 */
app.get("/settlement/list", (_, res) => {
    try {
        const settlements = settlementService.listAll();
        res.json({
            count: settlements.length,
            settlements
        });
    } catch (error) {
        res.status(500).json({
            error: error instanceof Error ? error.message : "Failed to list settlements"
        });
    }
});