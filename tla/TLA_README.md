# TLA+ Formal Specification - Lab 1

**Goal:** Design a formal specification for the broadcast replication protocol.

## What's Modeled

### CONSTANTS
- `Nodes` - Set of node identifiers (e.g., {n1, n2})
- `Keys` - Set of possible keys (e.g., {k1, k2})
- `Values` - Set of possible values (e.g., {v1, v2})

### VARIABLES
- `store[node][key]` - Per-node local key-value store
- `messages` - Set of broadcast messages in-transit

### Init State
- All nodes start with empty stores
- No messages in channel

### Actions

**Client Operations:**

1. **Put(node, key, value)** - Client calls `put` on a node
   - Updates local: `store[node][key] := value`
   - Broadcasts to others: adds messages to channel for all peers

2. **Delete(node, key)** - Client deletes from a node
   - Updates local: `store[node][key] := NoValue`
   - Broadcasts to others: adds messages to channel for all peers

3. **Get(node, key)** - Client reads from a node
   - Returns: `store[node][key]`
   - No state change (optional to model)

**Replication (message delivery):**

4. **LocalPut(msg)** - Node receives and applies `local_put`
   - Target applies: `store[target][key] := value`
   - Message removed from channel

5. **LocalDelete(msg)** - Node receives and applies `local_delete`
   - Target applies: `store[target][key] := NoValue`
   - Message removed from channel

### Spec
```tla
Spec == Init /\ [][Next]_vars
```

Where `Next` = Put | Delete | LocalPut | LocalDelete (Get optional).

### TypeOK Invariant
- `store` domain: `[Nodes -> [Keys -> Values \cup {NoValue}]]`
- `messages` structure: {type, target, key, value}

## Simplifications

- All nodes start simultaneously with empty state
- No node joining after startup
- Reliable network (messages always delivered)
- No crashes or recovery
- Fire-and-forget (no acks/retries)

## Running TLC

```bash
cd tla/
tlc DistributedDb.tla -config DistributedDb.cfg
```

Expected: Explores states, TypeOK holds.

## Files

- `DistributedDb.tla` - The specification
- `DistributedDb.cfg` - TLC configuration
