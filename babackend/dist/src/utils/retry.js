"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.retry = retry;
async function retry(fn, attempts = 3) {
    let lastError;
    for (let index = 0; index < attempts; index += 1) {
        try {
            return await fn();
        }
        catch (error) {
            lastError = error;
        }
    }
    throw lastError;
}
