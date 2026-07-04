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
});
export const env = schema.parse(process.env);
