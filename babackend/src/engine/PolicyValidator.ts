import {
    MAX_FEE,
    MIN_CONFIDENCE
} from "../config/constants.js";

export class PolicyValidator {

    validate(
        fee: number,
        confidence: number
    ) {

        if (fee > MAX_FEE)
            return false;

        if (confidence < MIN_CONFIDENCE)
            return false;

        return true;

    }

}