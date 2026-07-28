import assert from "node:assert/strict";
import test from "node:test";
import { SettlementService, SettlementStatus } from "./SettlementService.js";
import { SettlementExecutor } from "./SettlementExecutor.js";
test("processSettlement marks a successful relayed transfer as completed", async () => {
    const settlementService = new SettlementService();
    const settlement = settlementService.create("0xsettlement", "0xpool", 7, "0x0000000000000000000000000000000000000001", 1000, 3, "0x1111111111111111111111111111111111111111");
    const executor = new SettlementExecutor(settlementService, {
        transferExecutor: async () => "0xrelaytx"
    });
    const result = await executor.processSettlement(settlement.settlementId);
    assert.equal(result, true);
    assert.equal(settlementService.get(settlement.settlementId)?.status, SettlementStatus.Completed);
    assert.equal(settlementService.get(settlement.settlementId)?.txHash, "0xrelaytx");
});
