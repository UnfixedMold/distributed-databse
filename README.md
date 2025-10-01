# Distributed Database

A distributed key-value database system built with Elixir, inspired by etcd. This project is developed incrementally across three labs, progressively building toward a production-grade distributed system.

## Current Status: Lab-1 (Simple Distributed System)

Currently implementing a basic distributed key-value store with:
- **Replicated storage**: Each node maintains its own copy of the data
- **Broadcast replication**: Write operations are broadcast to all connected nodes
- **Sync-on-startup**: New nodes sync from existing nodes when joining
- **Automated distributed testing**: Using `LocalCluster` to spawn and test multi-node clusters

## Architecture

### Lab-1: Broadcast Replication (Current)
Each node runs its own `DistDb.Store` GenServer with an in-memory map. When a write occurs:
1. Node stores locally
2. Broadcasts operation to all other nodes via `:rpc.call()`
3. All nodes apply the same operation

**Characteristics:**
- Simple peer-to-peer architecture (no leader)
- Best-effort consistency (assumes reliable network)
- New nodes sync full state from any existing node on startup

### Lab-2: Communication Abstractions (Planned)
Will add:
- Acknowledgments and retry logic for failed writes
- Vector/Lamport clocks for causality tracking
- Fault detectors to identify dead nodes
- Basic conflict resolution

### Lab-3: Consensus-Based Replication (Planned)
Will implement:
- Leader election using Raft algorithm
- Log-based replication with majority consensus
- Strong consistency guarantees
- Proper recovery and catch-up for failed nodes

## Usage

### Running Multiple Nodes

```bash
# Terminal 1 - Start first node
iex --sname node1@localhost -S mix

# Terminal 2 - Start second node
iex --sname node2@localhost -S mix

# Terminal 3 - Start third node
iex --sname node3@localhost -S mix
```

### Connecting Nodes

```elixir
# In node2 or node3
Node.connect(:"node1@localhost")
Node.connect(:"node2@localhost")  # if on node3

# Verify connections
Node.list()
```

### Basic Operations

```elixir
# Put a key-value pair (creates or updates)
DistDb.Store.put("name", "alice")

# Get a value
DistDb.Store.get("name")  # => "alice"

# Delete a key
DistDb.Store.delete("name")

# List all data
DistDb.Store.list_all()  # => %{...}
```

## Testing

```bash
# Run all tests (including distributed tests)
mix test

# Run specific test file
mix test test/dist_db/store_test.exs
```

Distributed tests use `LocalCluster` to programmatically spawn multiple nodes and verify replication behavior.

