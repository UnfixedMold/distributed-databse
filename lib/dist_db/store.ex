defmodule DistDb.Store do
  @moduledoc """
  Public key-value store API and Raft apply callback.

  The actual key-value data lives in a DETS table; Raft stays
  generic and only calls `apply/1` that is passed in as a
  callback.
  """

  @dets_table :dist_db_store
  @data_root "app_data"

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
  end

  ## Raft apply callback

  def apply(command) do
    case :erlang.binary_to_term(command) do
      {:put, key, value} ->
        :ok = :dets.insert(@dets_table, {key, value})
        :ok

      {:delete, key} ->
        :ok = :dets.delete(@dets_table, key)
        :ok
    end
  end

  ## Server callbacks

  @impl true
  def init(:ok) do
    Logger.info("Starting DistDb.Store on node #{Node.self()}")
    dets_file = open_dets_for_current_node()
    {:ok, %{file: dets_file}}
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
  def terminate(_reason, _state) do
    :dets.close(@dets_table)
    :ok
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Internal helpers

  defp open_dets_for_current_node do
    node_dir = node_data_dir(Node.self())
    :ok = File.mkdir_p(node_dir)

    dets_file =
      node_dir
      |> Path.join("dist_db_store.dets")
      |> String.to_charlist()

    {:ok, _} = :dets.open_file(@dets_table, type: :set, file: dets_file)
    dets_file
  end

  defp node_data_dir(node) do
    node
    |> Atom.to_string()
    |> then(&Path.join(@data_root, &1))
  end
end
