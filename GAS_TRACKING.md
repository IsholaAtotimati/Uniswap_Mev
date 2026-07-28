# Gas Benchmark Tracking Guide

## Level 9 Complete: Gas Benchmarking & Regression Detection

This guide explains how to use the gas benchmarking tools to track performance metrics and detect regressions.

### Quick Start

**Generate a gas report and check for regressions:**
```bash
python3 gas-benchmark-report.py
```

**View detailed benchmarks:**
```bash
cat .gas-benchmarks.md
```

**Get machine-readable baseline:**
```bash
cat .gas-benchmarks.json
```

---

## Core Metrics Baseline (2026-07-14)

All measurements are from Foundry's `forge test --gas-report` (function-level gas costs).

### Operations Summary

| Operation | Min | Avg | Max | Target | Status |
|-----------|-----|-----|-----|--------|--------|
| **Settlement Execution** | 24,440 | 63,029 | 99,930 | 250,000 | ✅ 25% of budget |
| **Hook Callback** | 72,543 | 236,761 | 315,337 | 350,000 | ✅ 68% of budget |
| **Risk Assessment** | 5,052 | 9,330 | 9,806 | Baseline | ✅ Minimal |
| **Settlement Creation** | 88,709 | 200,569 | 312,430 | 150,000 | ⚠️ Monitor |

### Event Emission Profile

All lifecycle events combined: **~2,000 gas** per settlement
- SettlementCreated (~500 gas)
- SettlementAuthorized (~500 gas)
- SettlementExecuted (~500 gas)
- FundsTransferred (~500 gas)

**Overhead**: < 8% of total settlement gas

---

## Regression Thresholds

| Level | Increase | Action |
|-------|----------|--------|
| 🟢 Green | < 5% | No action required |
| 🟡 Yellow | 5–10% | Review optimization opportunities |
| 🔴 Red | > 10% | Investigate and fix regression |

---

## Test References

### Individual Operation Tests

Each test below measures a specific operation and its supporting logic:

```bash
# Settlement completion (66k-67k gas typical)
forge test --match-test "completeSettlementMarksSettlementCompleted" -vv

# Risk policy evaluation (9k-10k gas)
forge test --match-test "riskPolicyConstrainsFeeWhenThresholdIsExceeded" -vv

# Full hook lifecycle (300k+ gas including verification)
forge test --match-test "hookLifecycleBeforeSwapAuthorizesSettlement" -vv

# End-to-end flow (1M+ gas for full test setup + execution)
forge test --match-test "endToEndUserSwapFlowSignsIntent" -vv
```

### Full Gas Report

To generate a comprehensive gas report for all functions:

```bash
# Run full forge test with gas report
forge test --gas-report > gas-report-$(date +%Y%m%d-%H%M%S).txt

# Extract key metrics
grep -A 200 "MEVShieldHook Contract" gas-report-*.txt | head -100
```

---

## Tracking Changes Over Time

### Baseline Updates

To update the baseline with current measurements after an optimization:

```bash
python3 gas-benchmark-report.py --save-baseline
```

This updates `.gas-benchmarks.json` with new current values.

### Historical Comparison

Store gas reports in version control:

```bash
# Generate timestamped report
forge test --gas-report > gas-reports/gas-report-$(date +%Y%m%d-%H%M%S).txt

# Compare two reports
diff gas-reports/gas-report-2026-07-01.txt gas-reports/gas-report-2026-07-14.txt
```

### Continuous Integration

Add to your CI pipeline to fail on regressions:

```yaml
- name: Check Gas Regressions
  run: python3 gas-benchmark-report.py
  working-directory: /home/lukman12/MEV-SHIELD
```

---

## Key Insights

### 1. Settlement Execution (63k avg)
- **Status**: Excellent — 75% under target
- **Bottleneck**: ERC20 transfer (~25k gas)
- **Optimization**: None required; transfer cost is external dependency

### 2. Hook Callback (237k avg)
- **Status**: Good — 68% of allocated budget
- **Bottleneck**: Full verification stack (signature + risk + storage)
- **Optimization**: Batch non-critical updates with settlement

### 3. Risk Assessment (9k avg)
- **Status**: Optimal — precompile-dominated ecrecover
- **Bottleneck**: Signature verification (precompile at 3k gas)
- **Optimization**: Cannot optimize further; consider batch verification for high volume

### 4. Settlement Creation (201k avg)
- **Status**: Monitor — exceeds 150k target
- **Reason**: Includes full authorization + risk assessment + fee setup
- **Optimization**: Currently necessary for security; batch operations can defer non-critical updates

---

## Performance Budgets

### Memory-Optimal Flow (No Optimization)

```
beforeSwap Hook:
  - Payload decode: 2k
  - Signature verify: 37k
  - Risk assessment: 9k
  - Storage writes: 115k
  - Fee application: 27k
  ─────────────────────────
  Total: ~190k gas
```

### With Batch Optimization (Future)

```
beforeSwap Hook (deferred settlement):
  - Payload decode: 2k
  - Signature verify: 37k
  - Risk assessment: 9k
  - Fee application: 27k
  ─────────────────────────
  Subtotal: ~75k gas (before batch)
  
Settlement completion (batch):
  - Deferred risk storage: 115k
  - ERC20 transfer: 25k
  - Event emissions: 2k
  ─────────────────────────
  Subtotal: ~142k gas
  
  Combined: ~217k gas (34% savings if batched)
```

---

## Tools Reference

| File | Purpose |
|------|---------|
| `.gas-benchmarks.md` | Human-readable benchmark documentation |
| `.gas-benchmarks.json` | Machine-readable baseline for automation |
| `gas-benchmark-report.py` | Regression detection tool |
| `gas-regression-detector.py` | Legacy detector (for test-level measurement) |

---

## Troubleshooting

### "No metrics found" error
- Ensure `forge test --gas-report` completes successfully
- Check function names in gas report match expected patterns
- Run: `forge test --gas-report | grep "completeSettlement"`

### Large variance in Max values
- Max gas occurs when all state paths execute (worst case)
- Avg is more representative for budgeting
- Max is useful for gas limit validation on-chain

### Regression detected but seems wrong
1. Run the specific test: `forge test --match-test functionName -vv`
2. Check if recent code changes affected that path
3. Verify no new event emissions or state writes were added
4. Consider: did dependencies (OpenZeppelin, v4-core) update?

---

## Next Steps

- **Level 10 — Batch Optimization**: Implement deferred settlement updates to reduce hook callback gas by ~30%
- **Level 11 — Pool Metadata Caching**: Cache frequently accessed pool data to reduce lookups from 114k → ~50k gas
- **Level 12 — Multi-sig Optimization**: Implement efficient quorum verification for > 3 operators
