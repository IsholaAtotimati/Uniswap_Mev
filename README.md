
 # Project OverView demo link: https://youtu.be/1tF_3mIDi_0?si=BF_c9XLA2riw8jig
 #Author jouney: https://drive.google.com/file/d/1qh03G51sx23QIDyK0h2KxJika-gjGBFy/view?usp=sharing
 # 🛡️ MEVShield
## Programmable Execution Infrastructure for USDC

> **MEVShield is an intelligent execution layer for programmable money that analyzes USDC transactions, generates cryptographically signed Execution Policies, and enforces those policies on-chain before settlement.**

### The idea in one sentence

**Circle makes money programmable. MEVShield makes its execution programmable.**

Traditional DeFi asks:

> **"Can this transaction execute?"**

MEVShield asks:

> **"Should this transaction execute under these conditions?"**

Before a transaction reaches liquidity, MEVShield evaluates execution risk, generates an explicit policy describing the conditions under which the transaction is allowed to execute, and uses a Uniswap v4 Hook to verify and enforce that policy on-chain.

```text
                    MEVShield

User Intent
     │
     ▼
Circle Wallet / AppKit
     │
     ▼
Risk & MEV Analysis
     │
     ▼
Execution Policy
     │
     ▼
EIP-712 Authorization
     │
     ▼
Uniswap v4 Hook
     │
     ▼
On-Chain Policy Enforcement
     │
     ▼
USDC Execution & Settlement
     │
     ▼
Arc Testnet
```

🌐 **Live Demo Documentation:** https://mevshield.netlify.app/

---

# 1. 🔴 The Problem

## Stablecoin transactions are programmable — but execution is often not.

USDC enables programmable money, but when that money interacts with DeFi liquidity, the transaction is still exposed to changing execution conditions.

A transaction can encounter:

* Sandwich attacks
* MEV extraction
* Toxic order flow
* Adverse selection
* Poor liquidity
* Excessive price impact
* Market volatility
* Stale execution assumptions
* Unexpected execution conditions

Most transaction systems answer one fundamental question:

> **Can the transaction execute?**

But that is not necessarily the right question.

A transaction can be technically valid while being economically unfavorable.

### Traditional execution

```text
User
  │
  ▼
Transaction
  │
  ▼
Liquidity Pool
  │
  ▼
Settlement
```

The transaction is submitted and the market determines the outcome.

### The missing layer

There is often no intelligent, explicit policy between **user intent** and **execution** that says:

> "This transaction may execute only if these conditions remain valid."

That's the problem MEVShield addresses.

---

# 2. 🟢 The Solution — MEVShield

## Turn transaction intent into policy-controlled execution.

MEVShield introduces an **Execution Policy Layer** between the user's intent and blockchain settlement.

Instead of blindly submitting a transaction, MEVShield:

1. Understands the intended transaction.
2. Analyzes current execution conditions.
3. Evaluates MEV and market risk.
4. Estimates potential execution loss.
5. Generates an explicit Execution Policy.
6. Cryptographically signs the policy.
7. Sends the policy to the on-chain enforcement layer.
8. Lets the Uniswap v4 Hook verify and enforce the policy.

```text
User Intent
     │
     ▼
┌──────────────────────┐
│  MEVShield Engine    │
│                      │
│ Risk Analysis        │
│ MEV Detection        │
│ Liquidity Analysis   │
│ Toxic Flow Detection │
│ Loss Estimation      │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ Execution Policy     │
│                      │
│ Max Slippage         │
│ Risk Threshold       │
│ Pool                  │
│ Expiration            │
│ Nonce                 │
│ Execution Constraints │
└──────────┬───────────┘
           │
           │ EIP-712 Signature
           ▼
┌──────────────────────┐
│ Uniswap v4 Hook      │
│                      │
│ Verify Signature     │
│ Validate Policy      │
│ Check Nonce          │
│ Check Expiration     │
│ Enforce Constraints  │
└──────────┬───────────┘
           │
           ▼
       Execution
```

### The architectural principle

MEVShield separates:

**Intelligence** from **Enforcement**.

The expensive and evolving risk analysis happens off-chain.

The final authorization and execution constraints are verified deterministically on-chain.

This creates a system where the intelligence layer can evolve without requiring the blockchain to reproduce complex analytics.

---

# 3. 🎬 The Demo

## One transaction. One policy. One enforcement layer.

The MEVShield demo is designed around a simple flow:

```text
I clicked
    ↓
MEVShield analyzed the transaction
    ↓
Risk was evaluated
    ↓
An Execution Policy was generated
    ↓
The policy was cryptographically authorized
    ↓
The Uniswap v4 Hook verified the policy
    ↓
The execution path was policy-controlled
```

The demo demonstrates the core MEVShield concept:

> **Execution is not merely authorized. It is authorized under explicit conditions.**

### Example Risk Analysis

A transaction can be evaluated using signals such as:

```text
Risk Score          → 46
Risk Level          → MEDIUM
MEV Probability     → Evaluated
Price Impact        → Evaluated
Liquidity Risk      → Evaluated
Expected Loss       → Estimated
Execution Confidence→ Evaluated
```

The result is transformed into a machine-readable Execution Policy.

### Example policy lifecycle

```text
Transaction Intent
        │
        ▼
Risk Evaluation
        │
        ▼
Policy Generated
        │
        ▼
EIP-712 Signed
        │
        ▼
Submitted On-Chain
        │
        ▼
Hook Verification
        │
        ▼
Policy Enforcement
```

The objective is to make the execution decision **explicit, cryptographically authorized, and enforceable**.

---

# 4. 🔵 Arc + USDC + Circle

## Built for programmable money

MEVShield is designed around the idea that programmable money becomes significantly more powerful when its **execution conditions are programmable too**.

### Circle provides the money layer.

### MEVShield adds the execution-policy layer.

```text
                 CIRCLE
                   │
       ┌───────────┼───────────┐
       │           │           │
      USDC       Wallets      Arc
       │           │           │
       └───────────┼───────────┘
                   │
                   ▼
              MEVShield
                   │
        ┌──────────┼──────────┐
        │          │          │
   Intelligence  Policy   Enforcement
        │          │          │
        └──────────┼──────────┘
                   │
                   ▼
            Programmable
               Execution
```

---

## 💵 USDC

**USDC is the primary settlement asset for MEVShield.**

MEVShield is designed around USDC-native execution flows where transactions can be analyzed and constrained before settlement.

USDC provides the stable digital-dollar primitive.

MEVShield provides the policy and execution intelligence.

---

## 👛 Circle Wallets & AppKit

Circle Wallet infrastructure provides the wallet layer through which users can interact with protected USDC flows.

The intended user journey is:

```text
User
 ↓
Circle Wallet / AppKit
 ↓
USDC
 ↓
Payment / Swap Intent
 ↓
MEVShield Analysis
 ↓
Execution Policy
 ↓
Authorization
 ↓
Protected Execution
```

This makes wallet infrastructure part of the application flow rather than simply an external dependency.

---

## ⛓️ Arc Testnet

MEVShield's smart-contract infrastructure is deployed on Arc Testnet.

Arc serves as the initial blockchain execution environment for the project's policy enforcement and USDC execution infrastructure.

Deployment Addresses
Component	Address
MEVShield Hook	0x695333A0Ad0C1412057ee66F9C9a492aa45Cc080
Hook Address	0x695333A0Ad0C1412057ee66F9C9a492aa45Cc080
Settlement Relayer	0x2e988A386a799F506693793c6A5AF6B54dfAaBfB
EURC	0x89B50855Aa3bE2F677cD6303Cec089B5F319D72a
Arc Testnet RPC
https://rpc.testnet.arc.network

These addresses correspond to the current Arc Testnet deployment used by MEVShield.

Security: Never publish private keys, API keys, Circle Entity Secrets, wallet secrets, or other credentials in the README or repository.

## 🌉 CCTP

MEVShield's architecture can extend to cross-chain USDC execution through Circle's Cross-Chain Transfer Protocol.

The roles remain separate:

**CCTP → moves native USDC between supported chains.**

**MEVShield → determines the execution conditions surrounding the transaction.**

This creates a path toward:

* Cross-chain USDC execution
* Treasury management
* Policy-controlled payments
* Institutional settlement
* Autonomous financial workflows

---

# 5. ⚙️ Technology

## Execution Policy Engine

The **Execution Policy Engine (EPE)** is the intelligence layer behind MEVShield.

It evaluates the intended transaction against current execution conditions.

### Risk pipeline

```text
Transaction Intent
       │
       ▼
Feature Extraction
       │
       ▼
┌────────────────────────┐
│ Risk Analysis          │
│                        │
│ Market Risk            │
│ Liquidity Risk         │
│ MEV Risk               │
│ Toxic Flow Detection   │
│ Price Impact           │
│ Execution Quality      │
└───────────┬────────────┘
            │
            ▼
      Loss Estimation
            │
            ▼
 Protection / Fee Analysis
            │
            ▼
     Policy Generation
            │
            ▼
       EIP-712 Signing
            │
            ▼
   Signed Execution Policy
```

---

# 🔐 Execution Policies

An Execution Policy is a cryptographically signed description of the conditions under which an execution is authorized.

A policy can contain:

| Parameter        | Purpose                                     |
| ---------------- | ------------------------------------------- |
| Pool Identifier  | Identifies the target liquidity pool        |
| Settlement Asset | Defines the settlement asset                |
| Risk Score       | Represents assessed execution risk          |
| Maximum Slippage | Defines acceptable execution slippage       |
| Recommended Fee  | Represents recommended protection economics |
| Expiration       | Prevents stale policies                     |
| Nonce            | Prevents replay                             |
| Signature        | Authenticates the policy issuer             |

MEVShield uses **EIP-712 Typed Data** so the on-chain enforcement layer can verify the policy deterministically.

---

# 🛡️ On-Chain Policy Enforcement

This is the critical difference between MEVShield and a conventional risk dashboard.

A risk engine can tell a user:

> "This transaction looks risky."

MEVShield is designed to take the next step:

> **"This transaction is authorized only if the required execution policy is satisfied."**

The Uniswap v4 Hook acts as the enforcement boundary.

```text
                 OFF-CHAIN
┌──────────────────────────────────┐
│                                  │
│ Risk Intelligence                │
│ MEV Analysis                     │
│ Liquidity Analysis               │
│ Loss Estimation                  │
│ Policy Generation                │
│                                  │
└───────────────┬──────────────────┘
                │
                │ Signed Policy
                ▼
                 ON-CHAIN
┌──────────────────────────────────┐
│                                  │
│ Uniswap v4 Hook                  │
│                                  │
│ Signature Verification           │
│ Policy Validation                │
│ Nonce Validation                 │
│ Expiration Validation             │
│ Execution Constraints             │
│                                  │
└───────────────┬──────────────────┘
                │
                ▼
           USDC Execution
```

This creates a clean boundary:

**Off-chain intelligence decides what should be allowed.**

**On-chain enforcement determines whether the conditions are satisfied.**

---

# 🦄 Why Uniswap v4 Hooks?

Uniswap v4 Hooks provide programmable control points around pool operations.

MEVShield uses this capability to introduce an execution-policy enforcement layer around liquidity execution.

The result is:

```text
User Intent
     ↓
MEVShield Intelligence
     ↓
Execution Policy
     ↓
Uniswap v4 Hook
     ↓
Policy Enforcement
     ↓
PoolManager
     ↓
USDC Execution
```

This is what turns MEVShield from a monitoring system into an **execution infrastructure concept**.

---

# 🏗️ System Architecture

```text
                         ┌──────────────────────┐
                         │  Circle Wallet/AppKit│
                         └──────────┬───────────┘
                                    │
                                    ▼
                         ┌──────────────────────┐
                         │     User Intent      │
                         │    USDC Payment/Swap │
                         └──────────┬───────────┘
                                    │
                                    ▼
                  ┌────────────────────────────────┐
                  │      MEVShield Engine           │
                  │                                │
                  │ Feature Extraction             │
                  │ Risk Analysis                  │
                  │ MEV Detection                  │
                  │ Toxic Flow Detection           │
                  │ Loss Estimation                │
                  │ Policy Generation              │
                  │ EIP-712 Signing                │
                  └───────────────┬────────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────┐
                    │ Signed Execution Policy  │
                    └────────────┬─────────────┘
                                 │
                                 ▼
                    ┌──────────────────────────┐
                    │     MEVShield Hook       │
                    │                          │
                    │ Signature Verification   │
                    │ Policy Validation        │
                    │ Nonce Validation         │
                    │ Expiration Checks        │
                    │ Execution Constraints    │
                    └────────────┬─────────────┘
                                 │
                                 ▼
                    ┌──────────────────────────┐
                    │      Uniswap v4           │
                    │       PoolManager         │
                    └────────────┬─────────────┘
                                 │
                                 ▼
                    ┌──────────────────────────┐
                    │      USDC Execution       │
                    │        on Arc             │
                    └──────────────────────────┘
```

---

# 🌍 Why This Matters

MEVShield is not trying to replace Circle or Uniswap.

It connects their capabilities with a new execution-policy layer.

### Circle

**Programmable money**

### Uniswap

**Programmable liquidity**

### MEVShield

**Programmable execution**

Together:

```text
Programmable Money
        +
Programmable Liquidity
        +
Programmable Execution
        ↓
Policy-Controlled Financial Infrastructure
```

This architecture can support applications where financial transactions are:

**Analyzed → Authorized → Verified → Enforced → Settled**

---

# 🚀 Beyond MEV Protection

MEV protection is the first use case.

The underlying infrastructure is broader.

### Stablecoin Payments

Payments that execute only when predefined conditions are satisfied.

### Treasury Management

USDC deployment constrained by policy, risk, and authorization rules.

### Institutional Execution

Policy-controlled execution for larger stablecoin transactions.

### Cross-Chain Settlement

USDC movement combined with explicit execution policies.

### Autonomous Agents

Agents that can transact within predefined financial boundaries.

For example:

```text
Agent
 ↓
Spending Policy
 ↓
Risk Analysis
 ↓
Execution Authorization
 ↓
On-Chain Enforcement
 ↓
USDC Settlement
```

This allows autonomous systems to interact with money without requiring unrestricted control over funds.

---

# 🗺️ Roadmap

## Phase I — Policy-Controlled USDC Execution

* [x] Execution Policy Engine
* [x] Risk analysis pipeline
* [x] EIP-712 policy signing
* [x] Uniswap v4 Hook
* [x] Policy verification
* [x] Replay protection
* [x] Arc Testnet deployment
* [x] Circle Wallet / AppKit integration

## Phase II — Programmable Stablecoin Infrastructure

* [ ] Harden end-to-end settlement
* [ ] CCTP-powered cross-chain execution
* [ ] Multi-pool MEV protection
* [ ] Stablecoin treasury automation
* [ ] Institutional execution APIs
* [ ] Payment policy templates
* [ ] Advanced execution analytics

## Phase III — Autonomous Finance

* [ ] AI-assisted execution policies
* [ ] Agent-to-agent programmable payments
* [ ] Autonomous treasury execution
* [ ] Institutional policy management
* [ ] Cross-chain autonomous execution
* [ ] Execution Policy API / SDK

---

# 🛠️ Technology Stack

| Layer                      | Technology              |
| -------------------------- | ----------------------- |
| Smart Contracts            | Solidity                |
| AMM                        | Uniswap v4              |
| Hook Framework             | Uniswap v4 Hooks        |
| Backend                    | Node.js + TypeScript    |
| Execution Intelligence     | Custom Risk Engine      |
| Blockchain Client          | viem                    |
| Frontend                   | React / Next.js         |
| Wallet Infrastructure      | Circle Wallets / AppKit |
| Authorization              | EIP-712                 |
| Settlement Asset           | USDC                    |
| Execution Environment      | Arc Testnet             |
| Cross-Chain Infrastructure | Circle CCTP             |
| Development                | Foundry                 |

---

# 📁 Project Structure

```text
MEV-SHIELD/
│
├── LiveDemo_Ui/
│   └── MEVUI/
│       └── Frontend application
│
├── babackend/
│   ├── API
│   ├── Risk Engine
│   ├── Execution Policy Engine
│   └── Settlement Services
│
├── src/
│   └── Smart contracts
│
├── script/
│   └── Deployment and interaction scripts
│
├── test/
│   └── Contract tests
│
└── README.md
```

---

# 🚀 Getting Started

## Prerequisites

* Node.js
* npm
* Git
* Foundry
* Arc Testnet wallet
* Required Circle credentials
* Required environment variables

## Clone

```bash
git clone https://github.com/IsholaAtotimati/MEVShield_EncodeClub
cd MEV-SHIELD
```

## Backend

```bash
cd babackend
npm install
npm run dev
```

## Frontend

Open another terminal:

```bash
cd LiveDemo_Ui/MEVUI
npm install
npm run dev
```

Then open the local development URL provided by the frontend.

---

# ⚠️ Prototype Status

MEVShield is a hackathon-stage prototype focused on demonstrating the architecture of **policy-controlled programmable USDC execution**.

The project combines:

* Arc Testnet
* USDC
* Circle Wallet / AppKit
* Risk intelligence
* Execution Policies
* EIP-712 authorization
* Uniswap v4 Hooks
* On-chain policy enforcement

The current implementation is undergoing continued hardening of the end-to-end settlement path before production deployment.

The architecture is intentionally designed so that the intelligence layer, policy layer, and blockchain enforcement layer can evolve independently.

---

# 🔭 Vision

The future of programmable finance is not only **programmable money**.

It is **programmable execution**.

USDC provides programmable digital dollars.

Arc provides the execution environment.

Circle Wallets and AppKit provide wallet infrastructure.

CCTP provides a path for native USDC movement across supported chains.

Uniswap v4 provides programmable liquidity.

**MEVShield adds the execution-policy layer that determines how and under what conditions those assets should move.**

The long-term vision is an execution infrastructure where financial transactions are not blindly submitted to markets.

Instead, they become:

```text
ANALYZED
   ↓
AUTHORIZED
   ↓
VERIFIED
   ↓
ENFORCED
   ↓
SETTLED
```

---

# 🛡️ MEVShield

## Programmable Money Needs Programmable Execution.

**USDC is programmable.**

**Liquidity is programmable.**

**Execution should be programmable too.**
