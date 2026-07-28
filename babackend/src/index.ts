import { app, settlementService } from "./app.js";
import { RiskEngine } from "./engine/RiskEngine.js";
import { PoolListener } from "./listeners/PoolListener.js";
import { SettlementEventListener, loadHookAbi } from "./listeners/SettlementEventListener.js";
import { SettlementService, SettlementStatus } from "./services/SettlementService.js";
import { logger } from "./config/logger.js";
import { env } from "./config/env.js";
import { settlementEngine } from "./app.js";

async function bootstrap() {

    logger.info("MEVShield starting...");

    const riskEngine = new RiskEngine();
    const listener = new PoolListener(riskEngine);

    listener.start();

    // Start settlement event listener if hook is configured
    if (env.HOOK_ADDRESS && env.HOOK_ADDRESS !== "0x") {
        const hookAbi = loadHookAbi(env.HOOK_ABI_PATH || "src/abi/MEVShieldHook.json");
        const settlementListener = new SettlementEventListener(env.HOOK_ADDRESS, hookAbi);

        // Register callback to update settlement status when event is detected
        settlementListener.onSettlementAuthorized(async (event) => {
            const existing = settlementService.get(event.settlementId);

            if (existing) {
                settlementService.updateStatus(
                    event.settlementId,
                    SettlementStatus.Submitted,
                    event.transactionHash
                );
            } else {
                settlementService.create(
                    event.settlementId,
                    "unknown",
                    0,
                    event.token,
                    Number(event.amount),
                    event.destinationDomain,
                    "0x0000000000000000000000000000000000000000"
                );
                settlementService.updateStatus(
                    event.settlementId,
                    SettlementStatus.Submitted,
                    event.transactionHash
                );
            }

            await settlementEngine.processSettlement(event.settlementId, event.transactionHash);

            logger.info({
                msg: "Settlement event received",
                settlementId: event.settlementId,
                txHash: event.transactionHash
            });
        });

        await settlementListener.start();
    } else {
        logger.warn("HOOK_ADDRESS not configured; settlement event listener disabled");
    }

    app.listen(Number(env.PORT), "0.0.0.0", () => {
        logger.info(`HTTP API available at http://0.0.0.0:${env.PORT}`);
    });

    logger.info("MEVShield is LIVE (simulation mode)");
}

bootstrap();