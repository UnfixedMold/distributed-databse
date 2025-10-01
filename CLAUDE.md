# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a distributed key-value database system built with Elixir, inspired by etcd. The project is developed incrementally across three labs for distributed systems coursework at VU:

- **Lab-1 (Current)**: Simple distributed system with broadcast replication
- **Lab-2 (Planned)**: Communication abstractions, distributed clocks, fault detection
- **Lab-3 (Planned)**: Consensus-based replication with leader election (Raft)

Each lab includes:
- Elixir implementation (`lib/dist_db/`)
- Automated distributed tests (`test/`)
- TLA+ formal specification (`DistributedDb.tla`, `DistributedDb.cfg`)

## Development Environment

This project uses a devcontainer based on Ubuntu 24.04 with:
- **ASDF version manager**: Uses `.tool-versions-devcontainer` instead of `.tool-versions` to avoid interference with workspace files
- **Erlang 27.3.4.3 / Elixir 1.18.4-otp-27**: Erlang 28 is not currently supported by Elixir 1.18 or Lexical LSP
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
tlc DistributedDb.tla -config DistributedDb.cfg

# See TLA_README.md for detailed documentation
```

### Devcontainer
```bash
# Build the devcontainer image (from .devcontainer directory)
make build

# Run the devcontainer
make run
```

## Architecture

### Lab-1: Replicated Store with Broadcast Replication (Current Implementation)

**Core Concept:** Each node maintains its own complete copy of the data (replicated store). There is no shared storage or single source of truth.

**Components:**
- **DistDb.Store**: GenServer on each node holding an in-memory map of key-value pairs
- **DistDb.Application**: Supervisor that starts Store on application boot

**Replication Strategy:**

1. **Write Operations (put/delete):**
   - Store locally in the node's GenServer state
   - Broadcast the operation to all connected nodes using `:rpc.call(Node.list(), ...)`
   - Fire-and-forget: no acknowledgments or retries (Lab-1 assumes reliable network)

2. **Startup Synchronization:**
   - Nodes subscribe to `:net_kernel.monitor_nodes(true)` to receive `{:nodeup, node}` events
   - When a new node with empty state receives `nodeup`, it tries to sync from the connected node
   - If RPC fails (timeout, node not ready), keeps empty state
   - If no other nodes exist, starts with empty state `%{}`

3. **Read Operations (get/list_all):**
   - Served directly from local node's state (fast, no network calls)

**Key Characteristics:**
- Peer-to-peer: All nodes are equal (no leader/follower)
- Best-effort consistency: Works perfectly if network is reliable
- Simple: Easy to reason about and test

**Evolution Path:**
- **Lab-2**: Add acknowledgments, retry logic, vector clocks for causality, fault detectors
- **Lab-3**: Replace with leader-based Raft consensus for strong consistency guarantees

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
- `test/unit/local_store_test.exs` - Tests single-node operations on test runner
- `test/unit/dist_store_test.exs` - Tests replication across LocalCluster nodes
- `test/integration/dist_store_test.exs` - End-to-end distributed workflow tests

**Important:** Test runner node participates in the cluster! Cluster nodes automatically connect to the test runner and trigger `nodeup` events on its Store.

### Key Implementation Notes

**Module naming:** The mix project is `:vu_dist_sys_devcontainer` for historical reasons, but the main application logic is under the `DistDb` namespace.

**Operations:** Standard key-value store operations following etcd/Redis conventions:
- `put(key, value)` - Upsert (create or update)
- `get(key)` - Retrieve value
- `delete(key)` - Remove key
- `list_all()` - Get all key-value pairs (useful for sync/debugging)

### TLA+ Formal Specification

**Lab-1 Specification (`DistributedDb.tla`):**
- Models broadcast replication protocol
- Defines type invariants and basic properties
- Intentionally simplified to match Lab-1's assumptions (reliable network, no failures)

**Lab Requirements:**
- **Lab-1**: Specify core behavior (DONE)
- **Lab-2**: Define properties formally, verify with TLC model checker
- **Lab-3**: Prove at least one property using TLAPM

See `TLA_README.md` for detailed documentation.
