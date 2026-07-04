import { RiskResult } from "../models/RiskResult.js";
import { logger } from "../config/logger.js";

export type HookDecision = {
    action: "ALLOW" | "WARN" | "BLOCK";
    fee: number;
};

export class HookSimulator {

    beforeSwap(result: RiskResult): HookDecision {

        const spread = result.recommendedSpread;

        let decision: HookDecision;

        if (spread < 50) {
            decision = {
                action: "ALLOW",
                fee: spread
            };
        } 
        else if (spread < 200) {
            decision = {
                action: "WARN",
                fee: spread
            };
        } 
        else {
            decision = {
                action: "BLOCK",
                fee: spread
            };
        }

        logger.info({
            msg: "Hook simulation decision",
            action: decision.action,
            fee: decision.fee,
            risk: result.finalRiskScore
        });

        return decision;
    }
}