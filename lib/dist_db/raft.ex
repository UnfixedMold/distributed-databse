defmodule DistDb.Raft do
  @moduledoc """
  Minimal Raft placeholder.

  Currently runs as a single-node leader that immediately
  commits and applies commands on this node. Multi-node
  consensus will be added in later steps.
  """

  use GenServer

  @type command ::
          {:put, key :: term(), value :: term()}
          | {:delete, key :: term()}

  ## Client API

  @doc """
  Starts the Raft GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  Submit a command to the Raft log.

  For now this is single-node and immediately applies the
  command on this node only.
  """
  @spec submit(command()) :: :ok
  def submit(command) do
    GenServer.cast(__MODULE__, {:submit, command})
  end

  ## Server callbacks

  @impl true
  def init(:ok) do
    {:ok, %{log: [], last_index: 0}}
  end

  @impl true
  def handle_cast({:submit, command}, state) do
    index = state.last_index + 1
    entry = %{index: index, command: command}
    new_state = %{state | log: [entry | state.log], last_index: index}

    apply_entry(command)

    {:noreply, new_state}
  end

  defp apply_entry({:put, key, value}) do
    DistDb.Store.deliver_put(key, value)
    :ok
  end

  defp apply_entry({:delete, key}) do
    DistDb.Store.deliver_delete(key)
    :ok
  end
end

