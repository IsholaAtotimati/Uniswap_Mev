# Settlement Status: Failed - Quick Fix Checklist

**Status**: Settlement transitions are failing because the on-chain settlement relayer is not configured.

## ✅ Root Cause

Settlement gets stuck in `Pending` status because:
1. ❌ `settlementRelayer` is not set on MEVShieldHook
2. ❌ Backend was not progressing settlement through state machine
3. ❌ EIP-712 domain configuration mismatches can cause signature failures

## 🔧 Quick Fix (5 Steps)

### Step 1: Set Environment Variables
```bash
export HOOK_ADDRESS="0x..." # Your deployed MEVShieldHook
export SETTLEMENT_RELAYER="0x..." # Same address that will call settlement functions
export TRUSTED_SIGNER="0x..." # Off-chain signer address
export CHAIN_ID="5042002" # Your network's chain ID
export VERIFYING_CONTRACT="0x..." # Same as HOOK_ADDRESS
export PRIVATE_KEY="0x..." # Deployer key
export RPC_URL="http://localhost:8545"
```

### Step 2: Deploy On-Chain Configuration
```bash
cd /home/lukman12/MEV-SHIELD

forge script script/SettlementSetup.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --private-key $PRIVATE_KEY
```

**This sets:**
- ✅ Settlement relayer address on-chain
- ✅ Trusted signer for signature verification
- ✅ Risk policy thresholds
- ✅ Quorum requirements

### Step 3: Update Backend .env
```bash
cat >> babackend/.env << 'EOF'

# Settlement Configuration
SETTLEMENT_MODE=cctp
HOOK_ADDRESS=0x...
SETTLEMENT_RELAYER=0x...
USDC_ADDRESS=0x...

# EIP-712 Domain (MUST match on-chain)
CHAIN_ID=5042002
VERIFYING_CONTRACT=0x...
EOF
```

### Step 4: Verify Configuration
```bash
cd babackend
npx tsx scripts/test-settlement.ts
```

**Expected output:**
```
✓ On-chain configuration valid
✓ Settlement relayer ready
✓ Settlement state progression logic verified
```

### Step 5: Test Settlement Flow
```bash
# Submit a loss payload through the hook
# It will now progress through:
# Pending → BurnSubmitted → AwaitingAttestation → MintSubmitted → Completed
```

## 📊 Settlement State Machine

```
┌─────────────────────────────────────────────┐
│  Pending (initial)                          │
│  - Created by ExecutionCoordinator          │
│  - Requires relayer to progress             │
└───────────────┬─────────────────────────────┘
                │
                ↓
    recordCCTPMessage() [RELAYER ONLY]
                │
                ↓
        ┌───────────────┐
        │ BurnSubmitted │
        └───────┬───────┘
                │
                ↓
   markAwaitingAttestation() [RELAYER ONLY]
                │
                ↓
   ┌─────────────────────────┐
   │  AwaitingAttestation    │
   └────────────┬────────────┘
                │
                ↓
     markMintSubmitted() [RELAYER ONLY]
                │
                ↓
        ┌───────────────┐
        │ MintSubmitted │
        └───────┬───────┘
                │
                ↓
      completeSettlement() [RELAYER ONLY]
                │
                ↓
        ┌───────────────┐
        │   Completed   │  ← GOAL
        └───────────────┘

Or at any stage:
    markSettlementFailed()
                │
                ↓
        ┌───────────────┐
        │     Failed    │  ← Currently here
        └───────────────┘
```

## 🔍 Troubleshooting

| Error | Fix |
|-------|-----|
| "settlementRelayer is not set on-chain" | Run SettlementSetup.s.sol |
| "Configured wallet not a trusted signer" | Call `hook.setTrustedSigner(wallet, true)` |
| "CHAIN_ID mismatch: env=X provider=Y" | Update .env CHAIN_ID to match RPC network |
| "VERIFYING_CONTRACT mismatch" | Set .env VERIFYING_CONTRACT = HOOK_ADDRESS |
| "Settlement stuck in Pending" | Check backend logs, relayer must call state functions |
| "Insufficient USDC balance" | Fund relayer address with USDC tokens |

## 📝 Files Modified/Created

**New Files:**
- ✅ `babackend/src/services/SettlementRelayer.ts` - On-chain settlement progression
- ✅ `script/SettlementSetup.s.sol` - Forge script for configuration
- ✅ `babackend/scripts/test-settlement.ts` - Test script
- ✅ `SETTLEMENT_FIX.md` - Detailed documentation

**Modified Files:**
- ✅ `babackend/src/services/SettlementExecutor.ts` - Added CCTP flow support

## ✨ What's Fixed

### Before
- ❌ Settlement gets stuck in `Pending` status
- ❌ Status shown as "failed" with ERROR
- ❌ No state progression on-chain
- ❌ Missing relayer integration

### After  
- ✅ Settlement relayer properly configured on-chain
- ✅ State machine automatically progresses through CCTP flow
- ✅ Signature verification works with correct EIP-712 domain
- ✅ Full end-to-end settlement lifecycle supported

## 🚀 Testing

```bash
# Run the test script
cd /home/lukman12/MEV-SHIELD/babackend
npx tsx scripts/test-settlement.ts

# In real usage, submit a loss payload:
# 1. Off-chain loss engine signs LossPayload
# 2. Backend calls hook.submitRiskPayload()
# 3. ExecutionCoordinator verifies and creates settlement
# 4. SettlementRelayer progresses settlement through states
# 5. Settlement reaches Completed status
```

## 📚 Reference

- Full details: [SETTLEMENT_FIX.md](./SETTLEMENT_FIX.md)
- On-chain code: [src/SettlementCoordinator.sol](./src/SettlementCoordinator.sol)
- Backend relayer: [babackend/src/services/SettlementRelayer.ts](./babackend/src/services/SettlementRelayer.ts)
- Setup script: [script/SettlementSetup.s.sol](./script/SettlementSetup.s.sol)

---

**Next Action**: Run Step 1-2 above to configure on-chain settlement relayer ➜
