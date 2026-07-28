import dotenv from "dotenv";
import { z } from "zod";

dotenv.config();

const schema = z.object({
    PORT: z.string().default("4000"),
    RPC_URL: z.string().optional().default(""),
    PRIVATE_KEY: z.string().optional().default(""),
    LOG_LEVEL: z.string().default("info"),
    CHAIN_ID: z.coerce.number().optional().default(1),
    VERIFYING_CONTRACT: z.string().optional().default("0x0000000000000000000000000000000000000000"),
    HOOK_ADDRESS: z.string().optional().default(""),
    HOOK_ABI_PATH: z.string().optional().default(""),
    USDC: z.string().optional().default("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"),
    SETTLEMENT_MODE: z.string().optional().default("direct"),
    SETTLEMENT_MAX_RETRIES: z.coerce.number().optional().default(3),
    SETTLEMENT_RETRY_DELAY_MS: z.coerce.number().optional().default(1000),
});

export const env = schema.parse(process.env);