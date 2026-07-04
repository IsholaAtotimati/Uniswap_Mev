import { MAX_FEE, MIN_CONFIDENCE } from "../config/constants.js";
export class PolicyValidator {
    validate(fee, confidence) {
        if (fee > MAX_FEE)
            return false;
        if (confidence < MIN_CONFIDENCE)
            return false;
        return true;
    }
}
