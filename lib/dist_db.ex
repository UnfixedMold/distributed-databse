defmodule DistDb do
  @moduledoc """
  A distributed key-value database system built with Elixir.

  DistDb provides a simple replicated key-value store where each node
  maintains its own copy of the data. Write operations are broadcast
  to all connected nodes using a fire-and-forget approach.

  ## Usage

      # Basic operations
      DistDb.Store.put("key", "value")
      DistDb.Store.get("key")
      DistDb.Store.delete("key")
      DistDb.Store.list_all()

  ## Architecture

  Lab-1 implements broadcast replication where:
  - Each node maintains a complete copy of the data
  - Write operations replicate to all connected nodes
  - No leader election (peer-to-peer)
  - Best-effort consistency (assumes reliable network)
  """
end
