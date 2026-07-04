import { app } from "./app.js";
import { RiskEngine } from "./engine/RiskEngine.js";
import { PoolListener } from "./listeners/PoolListener.js";
import { logger } from "./config/logger.js";
import { env } from "./config/env.js";
async function bootstrap() {
    logger.info("MEVShield starting...");
    const riskEngine = new RiskEngine();
    const listener = new PoolListener(riskEngine);
    listener.start();
    app.listen(Number(env.PORT), "0.0.0.0", () => {
        logger.info(`HTTP API available at http://0.0.0.0:${env.PORT}`);
    });
    logger.info("MEVShield is LIVE (simulation mode)");
}
bootstrap();
