# Distributed Database

A distributed key-value database system built with Elixir for distributed systems coursework at VU. This is an educational project developed incrementally across three labs to learn distributed systems concepts.

## Lab Progress

### Lab-1 Recap: Naive Broadcast (completed)
The first lab wired the database API to a plain broadcast fan-out with no delivery guarantees

### Lab-2: Communication Abstractions (current)
Lab-2 swaps the naive fan-out for Bracha Reliable Broadcast (RBC), delivering Byzantine tolerance up to ⌊(n - 1) / 3⌋ faulty nodes while keeping the same client API. Messages progress through SEND/ECHO/READY phases with thresholds computed from the live cluster, and once READY quorum is met each node applies the write locally.

### Lab-3: Consensus-Based Replication (planned)
Will implement:
- Leader election using Raft or other algorithm (to be decided)
- ...

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

# Get a value (or the whole map with no args)
DistDb.Store.get("name")  # => "alice"
DistDb.Store.get()        # => %{...}  (no arg returns the whole state)

# Delete a key
DistDb.Store.delete("name")

# Inspect Raft roles for debugging
DistDb.Raft.roles()  # => %{leaders: [...], followers: [...], candidates: [...]}
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

The TLA+ model lives under `tla/` and captures the Bracha Reliable Broadcast protocol we ship in Lab-2:
- `DistributedDb.tla` models SEND/ECHO/READY phases, per-node message state machines, quorum thresholds (`n - 2f`, `f + 1`, `2f + 1`), and the replicated key-value state.
- `DistributedDb.cfg` configures the TLC model checker with representative constants and invariants (e.g., `TypeOK`, at-most-once delivery).
- `states/` stores sample TLC checkpoints for longer runs.

Run the checker from inside the `tla/` directory:

```bash
cd tla
tlc DistributedDb.tla -config DistributedDb.cfg
```

See [TLA_README.md](tla/TLA_README.md) for deeper walkthroughs and modeling notes.
