# 🛡️ ElderGuard

**A social recovery wallet for senior citizens, built on the Stacks blockchain in Clarity.**

ElderGuard lets a senior citizen hold their own STX assets on-chain while giving their adult children — registered as *guardians* — the ability to collectively recover wallet access if the owner ever loses their private key. No custodian. No single point of trust. Full self-sovereignty with a family safety net.

---

## Table of Contents

- [Why ElderGuard?](#why-elderguard)
- [How It Works](#how-it-works)
- [Roles](#roles)
- [Features](#features)
- [Recovery Flow](#recovery-flow)
- [Contract Constants](#contract-constants)
- [Public Functions](#public-functions)
- [Read-Only Functions](#read-only-functions)
- [Error Codes](#error-codes)
- [Security Considerations](#security-considerations)
- [Deployment](#deployment)

---

## Why ElderGuard?

Senior citizens face a unique challenge in crypto: the private key model assumes the user will always have reliable access. Lost keys mean permanently lost funds, yet handing custody to a family member or institution introduces trust problems of its own.

ElderGuard solves this with **social recovery** — a well-known pattern in wallet design where a group of trusted contacts can collectively authorize a new owner address, without any single person being able to act alone or drain funds unilaterally.

---

## How It Works

The wallet has two layers of protection:

**1. Spending protection** — Everyday transfers execute instantly. Large transfers are queued with a 1-day timelock, giving the owner time to cancel if something looks suspicious.

**2. Social recovery** — If the owner loses access, their registered adult children (guardians) vote to transfer ownership to a new address. At least **2 guardian votes** are required within a **10-day window**. The owner can veto any recovery attempt at any time.

---

## Roles

| Role | Who | Capabilities |
|---|---|---|
| **Owner** | The senior citizen | Deposit, transfer, manage guardians, veto recovery |
| **Guardian** | Adult child / trusted contact | Initiate, vote on, and execute recovery |

---

## Features

### Guardian Management
The owner registers up to **5** adult children as guardians. Guardians can be added or removed at any time, as long as no recovery is currently active.

### Deposits
Anyone can deposit STX into the wallet by calling `deposit`.

### Instant Transfers
The owner can send STX to any address immediately via `transfer`. Suitable for everyday spending.

### Timelocked Large Transfers
For larger amounts, the owner queues a transfer with `queue-large-transfer`. The funds only move after `execute-pending-transfer` is called at least **144 Bitcoin blocks (~1 day)** later. The owner can cancel the queued transfer at any time before it executes.

### Social Recovery
If the owner loses their key, guardians coordinate a 3-step recovery process to assign a new owner. The owner retains the right to cancel any fraudulent recovery attempt while they still have access.

---

## Recovery Flow

```
Guardian A calls initiate-recovery(new-owner-address)
    → Recovery opens. Guardian A's vote is automatically cast.

Guardian B calls approve-recovery()
    → Second vote cast. Threshold (2) is now reached.

Guardian A or B calls execute-recovery()
    → Ownership transferred to new-owner-address. Recovery closed.
```

**Key constraints:**
- Only registered guardians can participate.
- Each guardian can vote only once per recovery.
- The entire process must complete within **1,440 Bitcoin blocks (~10 days)**.
- The current owner can call `cancel-recovery` at any time to block the attempt.
- If the window expires without execution, anyone can call `expire-recovery` to clean up.

---

## Contract Constants

| Constant | Value | Meaning |
|---|---|---|
| `MAX-GUARDIANS` | 5 | Maximum number of registered guardians |
| `RECOVERY-THRESHOLD` | 2 | Guardian votes required to complete recovery |
| `RECOVERY-WINDOW` | 1,440 blocks | ~10 days for guardians to complete recovery |
| `SPEND-TIMELOCK` | 144 blocks | ~1 day delay on large queued transfers |

> All block timings reference `burn-block-height` (Bitcoin block height), giving predictable, ~10-minute block cadence.

---

## Public Functions

### Guardian Management

#### `add-guardian (guardian principal)`
Registers a new guardian. Only callable by the owner. Fails if a recovery is active, the guardian is already registered, or the 5-guardian cap is reached.

#### `remove-guardian (guardian principal)`
Removes a registered guardian. Only callable by the owner. Fails if a recovery is active.

---

### Deposits & Transfers

#### `deposit (amount uint)`
Transfers STX from the caller into the contract. Anyone can call this.

#### `transfer (amount uint) (recipient principal)`
Instantly sends STX from the wallet to `recipient`. Owner only.

#### `queue-large-transfer (amount uint) (recipient principal)`
Queues a transfer with a 1-day timelock. Owner only. Only one transfer can be queued at a time.

#### `execute-pending-transfer`
Executes a queued transfer after the timelock has passed. Owner only.

#### `cancel-pending-transfer`
Cancels a queued transfer before it executes. Owner only.

---

### Social Recovery

#### `initiate-recovery (new-owner principal)`
Opens a recovery and proposes `new-owner` as the new wallet owner. Callable by any guardian. Counts as the initiating guardian's vote.

#### `approve-recovery`
Casts an approval vote for the active recovery. Callable by any guardian who hasn't voted yet. Fails if the recovery window has expired.

#### `execute-recovery`
Finalizes recovery and transfers ownership to the proposed address. Callable by any guardian once the vote threshold is met and the window hasn't expired.

#### `cancel-recovery`
Vetoes and cancels the active recovery. Owner only. This is the owner's primary defense against a fraudulent guardian recovery attempt.

#### `expire-recovery`
Clears a recovery that ran out of time without completing. Callable by anyone.

---

## Read-Only Functions

| Function | Returns |
|---|---|
| `get-owner` | Current wallet owner principal |
| `get-guardian-count` | Number of registered guardians |
| `is-guardian (addr)` | `true` / `false` |
| `has-voted (guardian)` | `true` / `false` — whether they voted in the active recovery |
| `get-recovery-status` | `{ active, target, votes, initiated-at, threshold }` |
| `get-pending-transfer` | `{ amount, to, queued-at }` |
| `get-balance` | Contract's current STX balance in microstacks |

---

## Error Codes

| Code | Constant | Meaning |
|---|---|---|
| `u100` | `ERR-NOT-OWNER` | Caller is not the wallet owner |
| `u101` | `ERR-NOT-GUARDIAN` | Caller is not a registered guardian |
| `u102` | `ERR-ALREADY-GUARDIAN` | Address is already a registered guardian |
| `u103` | `ERR-GUARDIAN-LIMIT` | Maximum of 5 guardians already registered |
| `u104` | `ERR-NO-RECOVERY-ACTIVE` | No recovery is currently in progress |
| `u105` | `ERR-RECOVERY-ACTIVE` | A recovery is already in progress |
| `u106` | `ERR-ALREADY-VOTED` | This guardian has already voted |
| `u107` | `ERR-INSUFFICIENT-VOTES` | Not enough guardian votes to execute |
| `u108` | `ERR-RECOVERY-EXPIRED` | Recovery window has passed |
| `u109` | `ERR-INVALID-AMOUNT` | Amount must be greater than zero |
| `u110` | `ERR-GUARDIAN-NOT-FOUND` | Guardian address is not registered |
| `u111` | `ERR-TIMELOCK-ACTIVE` | Transfer timelock has not yet expired |

---

## Security Considerations

**Collusion risk** — With a threshold of 2, any two guardians can initiate recovery. The owner should only register adult children or contacts they deeply trust. For higher security, increase `RECOVERY-THRESHOLD` before deployment.

**Owner veto** — The single strongest protection against guardian abuse is `cancel-recovery`. Owners should monitor the chain or use a wallet app that alerts on recovery events.

**Timelock safety** — The 1-day spend timelock is a second line of defense. If an attacker gains temporary access to the owner's key, they cannot immediately drain the wallet on large amounts.

**Single pending transfer** — Only one transfer can be queued at a time. Queueing a new one replaces the previous record, so owners should not use queue-based transfers in rapid succession.

**No upgradeability** — The contract has no admin backdoor or upgrade path. What is deployed is what runs. Review carefully before deploying to mainnet.

---

## Deployment

1. Install the [Clarinet](https://github.com/hirosystems/clarinet) development tool.
2. Clone your project and place `elder-guard.clar` in the `contracts/` directory.
3. Run the Clarinet check to verify the contract:
   ```bash
   clarinet check
   ```
4. Run tests in the local simnet:
   ```bash
   clarinet console
   ```
5. Deploy to Stacks mainnet or testnet using the [Hiro Platform](https://platform.hiro.so) or the Stacks CLI.

> **Recommended:** Have the contract independently audited before deploying with real funds.