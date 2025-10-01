defmodule DistDb.Store do
  @moduledoc """
  A GenServer that maintains an in-memory key-value store.

  This is the core storage component for Lab-1, providing basic
  key-value operations without replication (added in later steps).
  """

  use GenServer
  require Logger

  # Client API

  @doc """
  Starts the Store GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  Puts a key-value pair into the store.
  Creates new entry or updates existing one.
  Replicates to all connected nodes.
  """
  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  @doc """
  Internal function to apply a put operation locally without replication.
  Used when receiving replicated operations from other nodes.
  """
  def local_put(key, value) do
    GenServer.call(__MODULE__, {:local_put, key, value})
  end

  @doc """
  Gets the value associated with a key.
  Returns nil if key doesn't exist.
  """
  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  @doc """
  Deletes a key from the store.
  Returns :ok whether key existed or not.
  Replicates to all connected nodes.
  """
  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
  end

  @doc """
  Internal function to apply a delete operation locally without replication.
  Used when receiving replicated operations from other nodes.
  """
  def local_delete(key) do
    GenServer.call(__MODULE__, {:local_delete, key})
  end

  @doc """
  Returns all key-value pairs in the store.
  """
  def list_all do
    GenServer.call(__MODULE__, :list_all)
  end

  @doc """
  Clears all data from the store (for testing purposes).
  """
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("Starting DistDb.Store on node #{Node.self()}")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    # Apply locally
    new_state = Map.put(state, key, value)

    # Replicate to all other nodes (fire-and-forget)
    replicate_to_peers(:local_put, [key, value])

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:local_put, key, value}, _from, state) do
    # Apply locally without further replication
    new_state = Map.put(state, key, value)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    # Apply locally
    new_state = Map.delete(state, key)

    # Replicate to all other nodes (fire-and-forget)
    replicate_to_peers(:local_delete, [key])

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:local_delete, key}, _from, state) do
    # Apply locally without further replication
    new_state = Map.delete(state, key)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{}}
  end

  # When I'm empty and connect to a node, pull their state
  @impl true
  def handle_info({:nodeup, node}, state) when map_size(state) == 0 do
    Logger.info("Empty node syncing from #{node}")

    case :rpc.call(node, __MODULE__, :list_all, [], 5_000) do
      synced_state when is_map(synced_state) -> {:noreply, synced_state}
      _error -> {:noreply, state}
    end
  end

  # When I already have data, just log the connection
  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info("Connected to #{node}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.info("Node #{node} disconnected")
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Helpers

  defp replicate_to_peers(function, args) do
    nodes = Node.list()

    if nodes != [] do
      Logger.debug("Replicating #{function} to nodes: #{inspect(nodes)}")

      Enum.each(nodes, fn node ->
        # Fire-and-forget: spawn async task to avoid blocking
        Task.start(fn ->
          try do
            :rpc.call(node, __MODULE__, function, args)
          rescue
            e ->
              Logger.warning(
                "Failed to replicate #{function} to #{node}: #{inspect(e)}"
              )
          end
        end)
      end)
    end
  end
end
