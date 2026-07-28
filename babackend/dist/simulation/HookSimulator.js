import { logger } from "../config/logger.js";
export class HookSimulator {
    beforeSwap(result, deadline) {
        const spread = result.recommendedSpread;
        let decision;
        if (deadline !== undefined && Date.now() >= deadline) {
            decision = {
                action: "BLOCK",
                fee: 0,
                reason: "deadline exceeded",
                reject: true
            };
        }
        else if (result.sandwichScore > 0.7) {
            decision = {
                action: "BLOCK",
                fee: 0,
                reason: "sandwich attack detected",
                reject: true
            };
        }
        else if (spread < 50) {
            decision = {
                action: "ALLOW",
                fee: spread,
                reject: false
            };
        }
        else if (spread < 200) {
            decision = {
                action: "WARN",
                fee: spread,
                reject: false
            };
        }
        else {
            decision = {
                action: "BLOCK",
                fee: spread,
                reject: true
            };
        }
        logger.info({
            msg: "Hook simulation decision",
            action: decision.action,
            fee: decision.fee,
            risk: result.finalRiskScore,
            reject: decision.reject,
            reason: decision.reason
        });
        return decision;
    }
}
