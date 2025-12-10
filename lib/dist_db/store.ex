defmodule DistDb.Store do
  @moduledoc """
  Public key-value store API.

  This GenServer owns the in-memory key-value state on each node.
  """

  @dets_table :dist_db_store
  @dets_file  ~c"dist_db_store.dets"

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
    :ok
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
    :ok
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
    {:ok, _} = :dets.open_file(@dets_table, type: :set, file: @dets_file)
    {:ok, %{file: @dets_file}}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    value =
      case :dets.lookup(@dets_table, key) do
        [{^key, v}] -> v
        [] -> nil
      end

    {:reply, value, state}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    :ok = :dets.insert(@dets_table, {key, value})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:delete, key}, _from, state) do
    :ok = :dets.delete(@dets_table, key)
    {:reply, :ok, state}
  end

  @impl true
  def terminate(_reason, _state) do
    :dets.close(@dets_table)
    :ok
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
