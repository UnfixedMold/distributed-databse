defmodule Raft do
  @moduledoc """
  Generic Raft core (single-node stub).

  This module knows nothing about DistDb. It maintains a log
  of opaque binary commands and, for each committed entry,
  calls a user-provided apply function.

  For now this is a single-node implementation that appends
  commands to an in-memory log and immediately applies them
  via that apply function. Consensus and persistence will be
  added incrementally on top.
  """

  use GenServer

  @type command :: binary()

  ## Client API

  @doc """
  Starts a Raft server.

  Options:
    * `:apply_fun` - function `fn (command :: binary()) -> reply end`
  """
  def start_link(opts) do
    apply_fun = Keyword.fetch!(opts, :apply_fun)

    GenServer.start_link(__MODULE__, apply_fun, name: __MODULE__)
  end

  @doc """
  Propose a command to be replicated.

  For now this just appends the command to a local log and
  applies it immediately to the state machine.
  """
  @spec propose(command()) :: reply :: term()
  def propose(command) when is_binary(command) do
    GenServer.call(__MODULE__, {:propose, command})
  end

  ## Server callbacks

  @impl true
  def init(apply_fun) do
    state = %{
      id: Node.self(),
      role: :leader,
      current_term: 0,
      voted_for: nil,
      log: [],
      last_index: 0,
      commit_index: 0,
      last_applied: 0,
      apply_fun: apply_fun
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:propose, command}, _from, state) do
    {entry, state} = append_entry(command, state)
    {state, reply} = advance_commit_index(entry.index, state)
    {:reply, reply, state}
  end

  ## Internal helpers

  defp append_entry(command, state) do
    index = state.last_index + 1

    entry = %{
      index: index,
      term: state.current_term,
      command: command
    }

    new_state = %{state | log: [entry | state.log], last_index: index}
    {entry, new_state}
  end

  defp advance_commit_index(target_index, state) do
    state = %{state | commit_index: max(state.commit_index, target_index)}
    apply_committed_entries(state)
  end

  defp apply_committed_entries(state) do
    entries_by_index =
      state.log
      |> Enum.map(&{&1.index, &1})
      |> Map.new()

    apply_from = state.last_applied + 1

    {last_applied, last_reply} =
      Enum.reduce(apply_from..state.commit_index, {state.last_applied, nil}, fn
        idx, {_last_idx, _last_reply} ->
          case Map.fetch(entries_by_index, idx) do
            {:ok, %{command: command}} ->
              reply = state.apply_fun.(command)
              {idx, reply}

            :error ->
              {idx, nil}
          end
      end)

    {%{state | last_applied: last_applied}, last_reply}
  end
end
