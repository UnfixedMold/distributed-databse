# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a distributed key-value database system built with Elixir, inspired by etcd. The project is developed incrementally across three labs for distributed systems coursework at VU:

- **Lab-1 (Current)**: Simple distributed system with broadcast replication
- **Lab-2 (Planned)**: Communication abstractions, distributed clocks, fault detection
- **Lab-3 (Planned)**: Consensus-based replication with leader election (Raft)

Optional TLA+ formal specification for verifying core behaviors.

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
   - When a new node joins, it syncs full state from any existing node
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

### Key Implementation Notes

**Module naming:** The mix project is `:vu_dist_sys_devcontainer` for historical reasons, but the main application logic is under the `DistDb` namespace.

**Operations:** Standard key-value store operations following etcd/Redis conventions:
- `put(key, value)` - Upsert (create or update)
- `get(key)` - Retrieve value
- `delete(key)` - Remove key
- `list_all()` - Get all key-value pairs (useful for sync/debugging)
