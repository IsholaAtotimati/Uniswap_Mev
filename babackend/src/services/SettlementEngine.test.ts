import test from "node:test";
import assert from "node:assert/strict";
import { SettlementService, SettlementStatus } from "./SettlementService.js";
import { SettlementEngine } from "./SettlementEngine.js";

test("SettlementEngine completes settlement through a completion client", async () => {
    const settlementService = new SettlementService();
    const settlementId = "0x1234";

    settlementService.create(
        settlementId,
        "0xpool",
        1,
        "0xtoken",
        42,
        0,
        "0xrecipient"
    );

    let completedSettlementId: string | undefined;
    const engine = new SettlementEngine(settlementService, {
        async completeSettlement(id: string) {
            completedSettlementId = id;
            return "0xabc";
        }
    }, {
        cctpDelayMs: 0
    });

    const completed = await engine.processSettlement(settlementId, "0xdef");
    const record = settlementService.get(settlementId);

    assert.equal(completed, true);
    assert.equal(completedSettlementId, settlementId);
    assert.equal(record?.status, SettlementStatus.Completed);
    assert.equal(record?.txHash, "0xabc");
});

test("SettlementEngine blocks conditional execution without an attestation", async () => {
    const settlementService = new SettlementService();
    const settlementId = "0xconditional";

    settlementService.create(
        settlementId,
        "0xpool",
        2,
        "0xUSDC",
        10,
        3,
        "0xrecipient",
        {
            asset: "USDC",
            executionMode: "conditional",
            cctpEnabled: true,
            paymasterEnabled: true,
            crossChainEnabled: true
        }
    );

    const engine = new SettlementEngine(settlementService, {
        async completeSettlement() {
            return "0xabc";
        }
    }, {
        cctpDelayMs: 0,
        requireAttestation: true
    });

    const completed = await engine.processSettlement(settlementId);
    const record = settlementService.get(settlementId);

    assert.equal(completed, false);
    assert.equal(record?.status, SettlementStatus.Failed);
    assert.match(record?.lastError ?? "", /attestation/i);
});
