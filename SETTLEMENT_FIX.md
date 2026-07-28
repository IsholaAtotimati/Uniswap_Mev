# Settlement Status Failed - Root Cause & Fix

## Problem Summary

The settlement is failing with status "failed" because:

1. **Settlement Relayer Not Configured** - The `settlementRelayer` address is not set on-chain, so the backend cannot progress settlement state transitions
2. **Missing State Progression** - The backend was not advancing settlements through their state machine (Pending → BurnSubmitted → AwaitingAttestation → MintSubmitted → Completed)
3. **Signature Verification Issues** - Environment configuration mismatches (CHAIN_ID, VERIFYING_CONTRACT) could cause signature verification failures

## Settlement State Machine

The on-chain settlement follows this flow:

```
Pending (initial)
  ↓
  recordCCTPMessage() → BurnSubmitted
  ↓
  markAwaitingAttestation() → AwaitingAttestation
  ↓
  markMintSubmitted() → MintSubmitted
  ↓
  completeSettlement() → Completed (final)

Or at any stage:
  → markSettlementFailed() → Failed (final)
```

## Solution

### 1. **Set Settlement Relayer Address On-Chain**

The `settlementRelayer` must be configured before settlements can progress:

```bash
# Set environment variables
export HOOK_ADDRESS="0x..." # Your deployed MEVShieldHook
export SETTLEMENT_RELAYER="0x..." # Address that will relay settlements
export TRUSTED_SIGNER="0x..." # Address signing loss payloads
export PRIVATE_KEY="0x..." # Deployer/multisig private key
export RPC_URL="http://localhost:8545"

# Run the settlement setup script
cd /home/lukman12/MEV-SHIELD
forge script script/SettlementSetup.s.sol \
  --rpc-url $RPC_URL \
  --broadcast
```

This script will:
- Set the `settlementRelayer` address on-chain
- Mark the off-chain signer as a trusted signer
- Configure risk policy thresholds
- Set quorum requirements

### 2. **Update Backend Configuration**

Ensure your backend `.env` includes:

```bash
# Hook & Settlement
HOOK_ADDRESS=0x... # Deployed MEVShieldHook
SETTLEMENT_RELAYER=0x... # Same address as on-chain configuration
RPC_URL=http://localhost:8545

# EIP-712 Domain (CRITICAL for signature verification)
CHAIN_ID=5042002 # Must match RPC network
VERIFYING_CONTRACT=0x... # Must equal HOOK_ADDRESS

# Off-chain Signer
PRIVATE_KEY=0x... # Must be marked as trusted signer on-chain

# Settlement Mode
SETTLEMENT_MODE=cctp # Options: "cctp" | "direct" | "disabled"
```

### 3. **Backend Settlement Relayer**

A new `SettlementRelayer` service handles on-chain state progression:

```typescript
import { SettlementRelayer } from "./services/SettlementRelayer.js";

const relayer = new SettlementRelayer(
    settlementService,
    {
        hookAddress: env.HOOK_ADDRESS,
        hookAbi: MEVShieldHookABI,
        enableCCTP: true
    }
);

// Verify configuration
const warnings = await relayer.verifyConfiguration();
if (warnings.length > 0) {
    console.warn("Configuration warnings:", warnings);
}

// Process settlement through CCTP flow
await relayer.recordCCTPMessage(settlementId, messageId, nonce);
await relayer.markAwaitingAttestation(settlementId);
await relayer.markMintSubmitted(settlementId);
await relayer.completeSettlement(settlementId);
```

### 4. **Updated Settlement Executor**

The `SettlementExecutor` now supports CCTP flow:

```typescript
const executor = new SettlementExecutor(
    settlementService,
    undefined, // transferExecutorImpl
    settlementRelayer, // NEW: relayer for CCTP
    { settlementMode: "cctp" } // NEW: settlement mode
);

// Automatically progresses through CCTP state machine
await executor.processSettlement(settlementId);
```

## Verification Steps

### 1. Check On-Chain Configuration

```bash
# Use the HookClient validator
cd /home/lukman12/MEV-SHIELD/babackend

npx tsx --eval "
const { HookClient } = await import('./dist/services/HookClient.js');
const abi = await import('./src/abi/MEVShieldHook.json', { assert: { type: 'json' } });

const client = new HookClient(process.env.HOOK_ADDRESS, abi.default);
const warnings = await client.validateOnchainSetup();

if (warnings.length === 0) {
  console.log('✓ On-chain configuration is valid');
} else {
  console.warn('⚠ Configuration issues:');
  warnings.forEach(w => console.warn('  -', w));
}
"
```

### 2. Test Settlement Flow

```bash
# Start the settlement relayer service
cd /home/lukman12/MEV-SHIELD/babackend

npx tsx --eval "
import { SettlementService } from './dist/services/SettlementService.js';
import { SettlementRelayer } from './dist/services/SettlementRelayer.js';
import abi from './src/abi/MEVShieldHook.json' assert { type: 'json' };

const settlementService = new SettlementService();
const relayer = new SettlementRelayer(
    settlementService,
    {
        hookAddress: process.env.HOOK_ADDRESS,
        hookAbi: abi
    }
);

const warnings = await relayer.verifyConfiguration();
if (warnings.length > 0) {
    console.warn('Relayer config issues:');
    warnings.forEach(w => console.warn('  -', w));
    process.exit(1);
}

console.log('✓ Settlement relayer properly configured');
console.log('Relayer address:', relayer.getRelayerAddress());
"
```

### 3. Submit a Test Payload

```bash
# Build and submit a test loss payload
cd /home/lukman12/MEV-SHIELD/babackend

npx tsx scripts/test-settlement.ts
```

## Common Issues & Fixes

| Issue | Cause | Fix |
|-------|-------|-----|
| **settlementRelayer is not set on-chain** | `setSettlementRelayer()` not called | Run SettlementSetup.s.sol script |
| **Wallet is not a trusted signer** | `setTrustedSigner()` not called | Run SettlementSetup.s.sol or call multisig |
| **Signature verification fails** | CHAIN_ID or VERIFYING_CONTRACT mismatch | Update .env to match on-chain values |
| **Settlement stuck in Pending** | Backend not progressing state | Check backend logs, relayer configuration |
| **Insufficient USDC balance** | Relayer doesn't have funds | Fund relayer address with USDC |
| **quorumThreshold is 0** | Signatures won't be accepted | Set quorum to ≥1 via setQuorumThreshold() |

## Files Modified

1. **New Service**: `babackend/src/services/SettlementRelayer.ts`
   - Handles on-chain settlement state progression
   - Implements CCTP flow orchestration
   - Verifies relayer configuration

2. **Updated Service**: `babackend/src/services/SettlementExecutor.ts`
   - Now accepts SettlementRelayer instance
   - Supports CCTP settlement mode
   - Progresses settlements through state machine

3. **New Script**: `script/SettlementSetup.s.sol`
   - Forge script for on-chain configuration
   - Sets relayer, signer, and risk policy
   - Uses environment variables for addresses/thresholds

## Next Steps

1. **Deploy settlement configuration**: Run SettlementSetup.s.sol with correct addresses
2. **Update backend .env**: Set SETTLEMENT_MODE=cctp and ensure CHAIN_ID/VERIFYING_CONTRACT match
3. **Start backend relayer service**: Initialize SettlementRelayer in your backend startup
4. **Test end-to-end flow**: Submit a test payload and verify settlement completes
5. **Monitor settlement status**: Check backend logs and on-chain settlement state

## Additional Resources

- Contract flow diagram: See ExecutionCoordinator and SettlementCoordinator
- CCTP integration: Implement CCTPAdapter for production cross-chain transfers
- Error handling: Settlements can retry, fail, or be cancelled based on on-chain status
