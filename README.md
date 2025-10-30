# Distributed Database

A distributed key-value database system built with Elixir for distributed systems coursework at VU. This is an educational project developed incrementally across three labs to learn distributed systems concepts.

## Current Status: Lab-2 (Communication Abstractions)

Lab-2 introduces Bracha Reliable Broadcast (RBC), which gives the store Byzantine fault tolerance up to ⌊(n - 1) / 3⌋ malicious or crashed nodes:
- **Replicated storage**: Each node maintains its own copy of the data.
- **Bracha RBC replication**: Writes flow through SEND → ECHO → READY with quorum thresholds derived from the current cluster size.
- **Sync-on-startup**: Empty nodes fetch the full state from any peer when joining.
- **Cluster management**: `libcluster` keeps all nodes connected automatically.
- **Automated distributed testing**: `local_cluster` spins up in-process BEAM nodes to exercise the protocol.
- **TLA+ formal specification**: Models the broadcast layer (`DistributedDb.tla`).

## Architecture

### Lab-1 Recap: Naive Broadcast
The first lab wired the database API to a plain broadcast fan-out with no delivery guarantees or Byzantine resilience.

### Lab-2: Communication Abstractions (Current)
Lab-2 replaces the unreliable broadcast with Bracha RBC while keeping the same public API:
1. A client issues `DistDb.Store.put/2` or `delete/1`.
2. The store hands a delivery callback to `DistDb.Broadcast.broadcast/1`.
3. Broadcast assigns a message id `{origin_node, monotonic_seq}` and enters the Bracha phases (SEND, ECHO, READY).
4. Thresholds (`n - 2f`, `f + 1`, `2f + 1`) are calculated at runtime by `DistDb.Broadcast.Thresholds`.
5. Once `READY` quorum is met, the delivery callback executes on every correct node and mutates its local store.

**Characteristics:**
- Peer-to-peer: no distinguished leader or coordinator.
- Byzantine resilience up to `f = ⌊(n - 1)/3⌋` faulty nodes.
- New nodes still sync their entire key set from the first healthy peer they see.

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

### Manual App Test

Start a couple of interactive nodes from the project root:

```bash
iex --sname node1@localhost -S mix
iex --sname node2@localhost -S mix
```

In any node shell you can raise the log level to see the SEND/ECHO/READY flow:

```elixir
Logger.configure(level: :debug)
```

Trigger a replicated write on one node and observe it propagate:

```elixir
DistDb.Store.put("demo", "value")
```

On another node, confirm the value was delivered:

```elixir
DistDb.Store.get("demo")
```

You should see matching debug lines on every node showing the Bracha phases followed by `Delivering ...`.

### Bracha RBC Pseudocode

```
types: SEND(m), ECHO(m), READY(m)

state:
  n                               // total number of nodes
  f = floor((n - 1) / 3)
  T_ECHO  = n - 2*f
  T_READY = f + 1
  T_DELIV = 2*f + 1

  seen_send[m]   = false
  sent_echo[m]   = false
  sent_ready[m]  = false
  delivered[m]   = false
  echo_from[m]   = set()
  ready_from[m]  = set()

// -----------------------------------------------------

send(m):
  broadcast_incl_self(SEND(m))

// -----------------------------------------------------

receive(SEND(m), from):
  if not seen_send[m]:
    seen_send[m] = true
    if not sent_echo[m]:
      sent_echo[m] = true
      broadcast_incl_self(ECHO(m))

// -----------------------------------------------------

receive(ECHO(m), from):
  if from not in echo_from[m]:
    echo_from[m].add(from)
    if |echo_from[m]| >= T_ECHO and not sent_ready[m]:
      sent_ready[m] = true
      broadcast_incl_self(READY(m))

// -----------------------------------------------------

receive(READY(m), from):
  if from not in ready_from[m]:
    ready_from[m].add(from)

    if |ready_from[m]| >= T_READY and not sent_ready[m]:
      sent_ready[m] = true
      broadcast_incl_self(READY(m))

    if |ready_from[m]| >= T_DELIV and not delivered[m]:
      delivered[m] = true
      deliver(m)
```

### Connecting Nodes

Nodes automatically discover and connect to each other using `libcluster`:

```elixir
# Verify connections
Node.list()  # Should show other nodes automatically
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
mix test test/unit/single_node_store_test.exs
mix test test/unit/multi_node_store_test.exs
mix test test/integration/broadcast_bracha_test.exs
mix test test/integration/dist_store_test.exs
```

Distributed tests use `local_cluster` to programmatically spawn multiple Elixir nodes in the same BEAM VM and verify replication behavior across them. Shared helpers live in `test/support/test_support.ex`.

## Formal Specification

TLA+ specification for verifying protocol correctness:

```bash
# Check the specification with TLC model checker
tlc DistributedDb.tla -config DistributedDb.cfg
```

See [TLA_README.md](TLA_README.md) for detailed documentation on the formal specification.
