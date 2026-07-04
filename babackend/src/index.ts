import { RiskEngine } from "./engine/RiskEngine.js";
import { PoolListener } from "./listeners/PoolListener.js";
import { logger } from "./config/logger.js";

async function bootstrap() {

    logger.info("MEVShield starting...");

    const riskEngine = new RiskEngine();

    const listener =
        new PoolListener(riskEngine);

    listener.start();

    logger.info("MEVShield is LIVE (simulation mode)");
}

bootstrap();