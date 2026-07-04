import { SwapSimulator } from "../simulation/SwapSimulator.js";
import { RiskEngine } from "../engine/RiskEngine.js";
import { PayloadBuilder } from "../engine/PayloadBuilder.js";
import { SignatureService } from "../services/SignatureService.js";
import { logger } from "../config/logger.js";
import { env } from "../config/env.js";
import { ethers } from "ethers";

export class PoolListener {

    private simulator = new SwapSimulator();
    private payloadBuilder = new PayloadBuilder();
    private signatureService?: SignatureService;
    private signer?: string;

    constructor(
        private riskEngine: RiskEngine
    ) {
        if (env.PRIVATE_KEY) {
            this.signatureService = new SignatureService(env.PRIVATE_KEY);
            this.signer = new ethers.Wallet(env.PRIVATE_KEY).address;
        } else {
            logger.warn("PRIVATE_KEY not defined; payload signing disabled");
        }
    }

    start() {

        logger.info("PoolListener started (SIMULATION MODE)");

        setInterval(async () => {

            const swap = this.simulator.generate();

            logger.info({
                msg: "New simulated swap",
                pool: swap.poolId,
                tx: swap.txHash
            });

            const result =
                await this.riskEngine.analyzeSwap(swap);

            logger.info({
                risk: result.finalRiskScore,
                fee: result.recommendedSpread,
                lpLoss: result.expectedLpLossUSD
            });

            if (!this.signatureService || !this.signer) {
                logger.info("Skipping payload signing because PRIVATE_KEY is not configured.");
                return;
            }

            const poolKey = {
                currency0: "0x0000000000000000000000000000000000001000",
                currency1: "0x0000000000000000000000000000000000002000",
                fee: 3000,
                tickSpacing: 60,
                hooks: "0x0000000000000000000000000000000000000000"
            };

            const abiCoder = new ethers.AbiCoder();
            const poolId = ethers.keccak256(
                abiCoder.encode(
                    ["address", "address", "uint24", "int24", "address"],
                    [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]
                )
            );

            const payloadPoolId = ethers.keccak256(poolId);

            const payload = this.payloadBuilder.build(
                result,
                payloadPoolId,
                this.signer
            );

            const signature = await this.signatureService.sign(payload);

            logger.info({
                msg: "Signed payload generated",
                payload,
                signature
            });

        }, 2000);
    }
}
