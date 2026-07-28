import assert from "assert";
import { normalizeHookPolicy, serializeHookPolicy } from "../src/services/HookClient.js";

const policy = normalizeHookPolicy({
    quorumThreshold: "3",
    maxExpectedLpLoss: "100",
    maxRecommendedSpread: "25000",
    rejectOnThreshold: false
});

assert.strictEqual(policy.quorumThreshold.toString(), "3");
assert.strictEqual(policy.maxExpectedLpLoss.toString(), "100");
assert.strictEqual(policy.maxRecommendedSpread.toString(), "20000");
assert.strictEqual(policy.rejectOnThreshold, false);

const serialized = serializeHookPolicy(policy);
assert.strictEqual(serialized.quorumThreshold, "3");
assert.strictEqual(serialized.maxRecommendedSpread, "20000");

console.log("HookClient policy normalization test passed");
