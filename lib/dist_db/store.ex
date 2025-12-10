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
  In Lab-3 this is replicated via Raft.
  """
  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
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
  In Lab-3 this is replicated via Raft.
  """
  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
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

  @doc """
  Deliver a put operation (called by Broadcast layer).
  Applies put locally without triggering another broadcast.
  """
  def deliver_put(key, value) do
    GenServer.call(__MODULE__, {:deliver_put, key, value})
  end

  @doc """
  Deliver a delete operation (called by Broadcast layer).
  Applies delete locally without triggering another broadcast.
  """
  def deliver_delete(key) do
    GenServer.call(__MODULE__, {:deliver_delete, key})
  end

  # Server Callbacks

  @impl true
  def init(:ok) do
    Logger.info("Starting DistDb.Store on node #{Node.self()}")

    {:ok, %{}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    DistDb.Raft.submit({:put, key, value})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    DistDb.Raft.submit({:delete, key})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:list_all, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{}}
  end

  @impl true
  def handle_call({:deliver_put, key, value}, _from, state) do
    new_state = Map.put(state, key, value)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:deliver_delete, key}, _from, state) do
    new_state = Map.delete(state, key)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
