# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a distributed key-value database system built with Elixir, inspired by etcd. The project is developed incrementally across three labs for distributed systems coursework at VU:

- **Lab-2 (Current)**: Communication abstractions with Bracha Byzantine Reliable Broadcast
- **Lab-3 (Planned)**: Consensus-based replication with leader election (Raft)
- **Lab-1 (Completed)**: Simple broadcast replication baseline (now superseded)

Each lab includes:
- Elixir implementation ([lib/dist_db/](lib/dist_db/))
- Automated distributed tests ([test/](test/))
- TLA+ formal specification ([tla/DistributedDb.tla](tla/DistributedDb.tla), [tla/DistributedDb.cfg](tla/DistributedDb.cfg))

## Development Environment

This project uses a devcontainer based on Ubuntu 24.04 with:
- **Erlang/Elixir**: Elixir 1.18 with OTP 27 (Erlang 28 not supported by Elixir 1.18 or Lexical LSP)
- **TLA+ toolchain**: Includes TLAPM (TLA+ Proof Manager) built from source with OCaml 5.3.0
- **Port 7000**: Forwarded for distributed node communication

## Common Commands

### Elixir Development
```bash
# Install dependencies
mix deps.get

# Compile the project
mix compile

# Run tests
mix test

# Run a specific test file
mix test test/path_to_test.exs

# Run a specific test by line number
mix test test/path_to_test.exs:42

# Format code
mix format

# Start interactive shell with project loaded
iex -S mix
```

### TLA+ Specification
```bash
# Check the specification with TLC model checker
cd tla/
tlc DistributedDb.tla -config DistributedDb.cfg

# See tla/TLA_README.md for detailed documentation
```

### Devcontainer
```bash
# Build the devcontainer image
cd .devcontainer && make build

# Run the devcontainer
cd .devcontainer && make run
```

## Architecture

### Lab-2: Communication Abstractions (Current Implementation)

**Core Concept:** Each node maintains its own complete copy of the data. Updates replicate through Bracha Byzantine Reliable Broadcast (RBC), providing safety despite up to ⌊(n - 1)/3⌋ Byzantine faults.

**Primary Components:**
- [DistDb.Store](lib/dist_db/store.ex) — GenServer per node that holds the key-value map and hands write intents to the broadcaster.
- [DistDb.Broadcast](lib/dist_db/broadcast.ex) — Implements Bracha SEND/ECHO/READY, tracks per-message state, and triggers delivery callbacks.
- [DistDb.Broadcast.Thresholds](lib/dist_db/broadcast/thresholds.ex) — Computes quorum thresholds (`n - 2f`, `f + 1`, `2f + 1`) based on current cluster size.
- [DistDb.Application](lib/dist_db/application.ex) — Supervises Store and Broadcast processes.

**Replication Strategy:**

1. **Write Operations (put/delete):**
   - Client calls `DistDb.Store.put/2` or `delete/1` (synchronous `GenServer.call/2`).
   - Store builds a zero-arity delivery callback and invokes `DistDb.Broadcast.broadcast/1`.
   - Broadcast assigns `{origin_node, unique_integer}` as message id and orchestrates SEND/ECHO/READY, broadcasting as needed until thresholds are satisfied.

2. **Startup Synchronization:**
   - Store subscribes to `:net_kernel.monitor_nodes(true)`.
   - The first time an empty node sees a `:nodeup`, it uses `:rpc.call/5` to fetch `list_all/0` from the peer and hydrates its state.

3. **Read Operations (get/list_all):**
   - Served directly from local GenServer state.

**Key Characteristics:**
- Peer-to-peer topology with no single coordinator.
- RBC ensures agreement even with faulty senders (within `f`).
- New nodes piggyback on existing state to catch up immediately.

**Evolution Path:**
- **Lab-1 Recap:** Simple unreliable broadcast replication (already replaced by Bracha RBC).
- **Lab-3:** Replace RBC with Raft-style consensus for stronger guarantees.

### Testing Strategy

Uses `LocalCluster` library to programmatically spawn multiple Elixir nodes in tests:

```elixir
{:ok, cluster} = LocalCluster.start_link(3, applications: [:dist_db])
{:ok, [node1, node2, node3]} = LocalCluster.nodes(cluster)

# Test operations across nodes
:rpc.call(node1, DistDb.Store, :put, ["key", "value"])
:rpc.call(node2, DistDb.Store, :get, ["key"])  # Should return "value"
```

This allows automated testing of distributed behavior without manual node setup.

**Test Structure:**
- [test/unit/single_node_store_test.exs](test/unit/single_node_store_test.exs) — Single-node Store behaviour.
- [test/unit/multi_node_store_test.exs](test/unit/multi_node_store_test.exs) — Replication sanity across multiple nodes.
- [test/integration/broadcast_bracha_test.exs](test/integration/broadcast_bracha_test.exs) — Direct RBC invariants (thresholds, duplication, crash resilience).
- [test/integration/dist_store_test.exs](test/integration/dist_store_test.exs) — End-to-end flows through Store + Broadcast.
- Shared helpers: [test/support/test_support.ex](test/support/test_support.ex) (compiled in dev/test environments).

**Important:** Test runner node participates in the cluster! Cluster nodes automatically connect to the test runner and trigger `nodeup` events on its Store.

### Key Implementation Notes

**Module naming:** The mix project is `:dist_db` and the main application logic is under the `DistDb` namespace.

**Operations:** Standard key-value store operations following etcd/Redis conventions:
- `put(key, value)` - Upsert (create or update)
- `get(key)` - Retrieve value
- `delete(key)` - Remove key
- `list_all()` - Get all key-value pairs (useful for sync/debugging)

### TLA+ Formal Specification

**Lab-1 Specification ([tla/DistributedDb.tla](tla/DistributedDb.tla)):**
- Models the Bracha RBC replication protocol
- Defines type invariants and basic properties
- Intentionally simplified to match Lab-1's assumptions (reliable network, no failures)

**Lab Requirements:**
- **Lab-1**: Specify core behavior (DONE)
- **Lab-2**: Define properties formally, verify with TLC model checker
- **Lab-3**: Prove at least one property using TLAPM

See [tla/TLA_README.md](tla/TLA_README.md) for detailed documentation.
