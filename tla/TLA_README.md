# TLA+ Formal Specification

## Overview

This directory contains the TLA+ formal specification for the distributed key-value store. The specification models the core behavior of the system across all three lab stages.

### Lab-1: Basic Specification (Current)

Models the **broadcast replication** protocol with intentional simplifications matching Lab-1's implementation.

## What's Modeled

### Core Operations
- **Put(n, k, v)**: Node `n` writes key `k` with value `v`
  - Updates local store immediately
  - Broadcasts message to all other nodes

- **Delete(n, k)**: Node `n` deletes key `k`
  - Removes key locally (sets to Null)
  - Broadcasts delete message

- **ReceivePut/ReceiveDelete**: Nodes receive and apply replicated operations
  - Apply messages from other nodes
  - Messages are consumed after processing

### Assumptions (matching Lab-1 implementation)
✅ **Reliable network** - messages don't get lost
✅ **No node failures** - all nodes stay up
✅ **Fire-and-forget** - no acknowledgments or retries
✅ **Best-effort consistency** - eventual consistency only when all messages delivered

### NOT Modeled (future labs)
❌ Network partitions or message loss
❌ Node crashes and recovery
❌ Message reordering
❌ Retry logic
❌ Strong consistency guarantees
❌ Vector clocks or causal ordering

## Properties Checked

### Type Invariant (`TypeOK`)
✅ **Always holds** - Verifies the state structure is correct

### Eventual Consistency (`EventualConsistency`)
⚠️ **Conditionally holds** - All nodes converge when message queue is empty
- In Lab-1: Only guaranteed if all messages are delivered
- Future labs will strengthen this

### Propagation Liveness (`PropagationLiveness`)
❌ **NOT guaranteed in Lab-1** - A write may not propagate to all nodes
- Requires retries (Lab-2)
- Or consensus protocol (Lab-3)

## Running the Model Checker

### Prerequisites
```bash
# TLA+ Toolbox is installed in the devcontainer
# TLAPM (TLA+ Proof Manager) is also available
```

### Check the specification
```bash
# From project root
tlc DistributedDb.tla -config DistributedDb.cfg
```

### Expected Results
- ✅ `TypeOK` - should pass
- ✅ `EventualConsistency` - passes in ideal conditions (no message loss)
- ❌ `PropagationLiveness` - may fail (intentional - shows Lab-1 limitations)

## Model Parameters

### Current Configuration (small model)
- **Nodes**: `{n1, n2, n3}` - 3 nodes
- **Keys**: `{k1, k2}` - 2 keys
- **Values**: `{v1, v2, Null}` - 2 values plus Null

### State Space
- Symmetry reduction on nodes reduces equivalent states
- Message queue bounded to 10 messages (prevents infinite exploration)

### Scaling Up
To check larger models, edit `DistributedDb.cfg`:
```
Nodes = {n1, n2, n3, n4}
Keys = {k1, k2, k3}
Values = {v1, v2, v3, Null}
```
⚠️ State space grows exponentially!

## Lab Progression

### Lab-1: Specify Core Behavior (Current)
**Requirement:** "Design a formal specification for its core behaviour"

✅ **What we have:**
- Basic protocol operations (Put, Delete, Replication)
- State structure and transitions
- Type invariant

**Goal:** Describe HOW the system works

### Lab-2: Define Properties Formally (Future)
**Requirement:** "Update the formal specification and define properties formally"

**What to add:**
- Extend spec with vector clocks, retries, fault detectors
- Write temporal logic properties (safety and liveness)
- Run TLC model checker to verify properties

**Goal:** State what properties the system SHOULD have and verify them

### Lab-3: Prove Properties (Future)
**Requirement:** "Define properties formally, and prove one of those properties"

**What to add:**
- Use TLAPM (TLA+ Proof Manager) to write mathematical proofs
- Prove at least one property holds for ALL executions (not just model check)

**Goal:** Mathematical proof, not just finite-state verification

---

## Interpretation

### What This Tells Us (Lab-1)

1. **Lab-1 protocol is sound** under ideal conditions (TypeOK passes)
2. **Eventual consistency requires** all messages to be delivered
3. **No strong guarantees** without retries or consensus

### Limitations We Accept (for now)

This spec **intentionally does not model**:
- Sync-on-startup behavior (nodeup handling)
- RPC timeouts and failures
- Network unreliability

These will be addressed in future labs.

## Relationship to Implementation

| TLA+ Construct | Elixir Code |
|----------------|-------------|
| `Put(n, k, v)` | `DistDb.Store.put/2` |
| `Delete(n, k)` | `DistDb.Store.delete/1` |
| `ReceivePut` | `handle_call({:local_put, ...})` |
| `messages` | Fire-and-forget RPC calls in `replicate_to_peers/2` |
| `store[n]` | GenServer state (map) on each node |

---

**Note**: This is a pedagogical specification for understanding Lab-1's behavior, not a complete verification. The TLA+ model helps us reason about what guarantees we DO and DON'T have.
