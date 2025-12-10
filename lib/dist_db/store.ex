defmodule DistDb.Store do
  @moduledoc """
  Public key-value store API.

  This GenServer owns the in-memory key-value state on each node.
  """

  @behaviour Raft.StateMachine
  use GenServer
  require Logger

  ## Client API

  @doc """
  Starts the Store GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  Puts a key-value pair into the store.
  Creates new entry or updates existing one.
  """
  def put(key, value) do
    command = {:put, key, value} |> :erlang.term_to_binary()
    Raft.propose(command)
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
  """
  def delete(key) do
    command = {:delete, key} |> :erlang.term_to_binary()
    Raft.propose(command)
    GenServer.call(__MODULE__, {:delete, key})
  end

  @impl true
  def apply(command) do
    case :erlang.binary_to_term(command) do
      {:put, key, value} ->
        GenServer.call(__MODULE__, {:put, key, value})

      {:delete, key} ->
        GenServer.call(__MODULE__, {:delete, key})
    end
  end

  ## Server callbacks

  @impl true
  def init(:ok) do
    Logger.info("Starting DistDb.Store on node #{Node.self()}")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    new_state = Map.put(state, key, value)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    new_state = Map.delete(state, key)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
