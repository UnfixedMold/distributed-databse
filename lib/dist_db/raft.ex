defmodule DistDb.Raft do
  @moduledoc """
  Generic Raft core (single-node stub).

  This module knows nothing about DistDb.Store. It maintains a
  log of opaque binary commands and, for each committed entry,
  calls a user-provided apply function.

  For now this is a single-node implementation that appends
  commands to an in-memory log and immediately applies them
  via that apply function. Consensus and persistence will be
  added incrementally on top.
  """

  use GenServer

  require Logger

  @type command :: binary()
  @dets_table :dist_db_raft
  @dets_file "raft_log.dets"
  @election_timeout_min 150
  @election_timeout_max 300

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
    DistDb.Storage.open_node_dets(@dets_table, @dets_file)
    {persisted_meta, persisted_log} = load_persistent_state()

    log =
      persisted_log
      |> Enum.sort_by(& &1.index, :desc)

    last_index =
      case log do
        [%{index: idx} | _] -> idx
        [] -> 0
      end

    peers =
      Node.list()
      |> Enum.reject(&(&1 == Node.self()))

    state = %{
      id: Node.self(),
      role: :follower,
      leader_id: nil,
      current_term: persisted_meta.current_term,
      voted_for: persisted_meta.voted_for,
      log: log,
      last_index: last_index,
      commit_index: 0,
      last_applied: 0,
      apply_fun: apply_fun,
      peers: peers,
      votes_received: 0,
      election_timeout_ref: nil
    }

    state = reset_election_timeout(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:propose, command}, _from, state) do
    {entry, state} = append_entry(command, state)
    {state, reply} = advance_commit_index(entry.index, state)
    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:request_vote, rpc}, state) do
    Logger.debug(
      "[#{inspect(Node.self())}] received RequestVote from #{inspect(rpc.candidate_id)} in term #{rpc.term}"
    )

    state = maybe_step_down(state, rpc.term)

    state =
      if rpc.term < state.current_term do
        send_request_vote_response(state, rpc.candidate_id, false)
        state
      else
        can_vote = state.voted_for in [nil, rpc.candidate_id]
        up_to_date = candidate_log_up_to_date?(rpc, state)

        if can_vote and up_to_date do
          state1 = %{state | voted_for: rpc.candidate_id}
          persist_meta(state1)
          state2 = reset_election_timeout(state1)
          send_request_vote_response(state2, rpc.candidate_id, true)
          state2
        else
          send_request_vote_response(state, rpc.candidate_id, false)
          state
        end
      end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:append_entries, rpc}, state) do
    Logger.debug(
      "[#{inspect(Node.self())}] received AppendEntries from #{inspect(rpc.leader_id)} in term #{rpc.term}"
    )

    # Log replication / heartbeat handling will be implemented in the next step.
    {:noreply, state}
  end

  @impl true
  def handle_cast({:request_vote_response, rpc}, state) do
    state = maybe_step_down(state, rpc.term)

    state =
      if state.role == :candidate and rpc.term == state.current_term and rpc.vote_granted do
        total_nodes = 1 + length(state.peers)
        majority = div(total_nodes, 2) + 1
        votes = state.votes_received + 1
        state1 = %{state | votes_received: votes}

        if votes >= majority do
          become_leader(state1)
        else
          state1
        end
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:election_timeout, state) do
    Logger.debug("[#{inspect(Node.self())}] election timeout in role #{state.role}")

    state =
      case state.role do
        :leader -> state
        _ -> start_election(state)
      end

    {:noreply, state}
  end

  ## Internal helpers

  defp append_entry(command, state) do
    index = state.last_index + 1

    entry = %{
      index: index,
      term: state.current_term,
      command: command
    }

    persist_entry(entry, %{state | last_index: index})
    new_state = %{state | log: [entry | state.log], last_index: index}
    {entry, new_state}
  end

  defp advance_commit_index(target_index, state) do
    state = %{state | commit_index: max(state.commit_index, target_index)}
    apply_committed_entries(state)
  end

  defp start_election(state) do
    Logger.info("[#{inspect(Node.self())}] starting election in term #{state.current_term + 1}")

    state1 = %{
      state
      | role: :candidate,
        current_term: state.current_term + 1,
        voted_for: state.id,
        leader_id: nil,
        votes_received: 1
    }

    persist_meta(state1)
    state2 = reset_election_timeout(state1)
    broadcast_request_vote(state2)
    state2
  end

  defp become_follower(state, new_term, leader_id) do
    state1 = %{
      state
      | role: :follower,
        leader_id: leader_id,
        current_term: new_term,
        voted_for: nil,
        votes_received: 0
    }

    persist_meta(state1)
    reset_election_timeout(state1)
  end

  defp become_leader(state) do
    Logger.info("[#{inspect(Node.self())}] became leader in term #{state.current_term}")

    state
    |> cancel_election_timeout()
    |> Map.put(:role, :leader)
    |> Map.put(:leader_id, state.id)
    |> Map.put(:votes_received, 0)
  end

  defp reset_election_timeout(state) do
    state = cancel_election_timeout(state)

    timeout = Enum.random(@election_timeout_min..@election_timeout_max)
    ref = Process.send_after(self(), :election_timeout, timeout)
    %{state | election_timeout_ref: ref}
  end

  defp cancel_election_timeout(state) do
    if state.election_timeout_ref do
      Process.cancel_timer(state.election_timeout_ref)
    end

    %{state | election_timeout_ref: nil}
  end

  defp maybe_step_down(state, rpc_term) do
    if rpc_term > state.current_term do
      become_follower(state, rpc_term, nil)
    else
      state
    end
  end

  defp last_log_term(%{log: []}), do: 0

  defp last_log_term(%{log: [%{term: term} | _]}), do: term

  defp broadcast_request_vote(state) do
    rpc = %{
      term: state.current_term,
      candidate_id: state.id,
      last_log_index: state.last_index,
      last_log_term: last_log_term(state)
    }

    Enum.each(state.peers, fn peer ->
      GenServer.cast({__MODULE__, peer}, {:request_vote, rpc})
    end)
  end

  defp broadcast_append_entries(state, entries, leader_commit) do
    rpc = %{
      term: state.current_term,
      leader_id: state.id,
      prev_log_index: state.last_index,
      prev_log_term: last_log_term(state),
      entries: entries,
      leader_commit: leader_commit
    }

    Enum.each(state.peers, fn peer ->
      GenServer.cast({__MODULE__, peer}, {:append_entries, rpc})
    end)
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

  @impl true
  def terminate(_reason, _state) do
    :dets.close(@dets_table)
    :ok
  end

  ## DETS helpers

  defp load_persistent_state do
    meta =
      case :dets.lookup(@dets_table, :meta) do
        [{:meta, value}] -> value
        [] -> %{current_term: 0, voted_for: nil}
      end

    log =
      :dets.foldl(
        fn
          {index, %{index: _, term: _, command: _} = entry}, acc when is_integer(index) ->
            [entry | acc]

          _, acc ->
            acc
        end,
        [],
        @dets_table
      )

    {meta, log}
  end

  defp persist_entry(entry, state) do
    :ok = :dets.insert(@dets_table, {entry.index, entry})
    persist_meta(state)
  end

  defp persist_meta(state) do
    meta = %{
      current_term: state.current_term,
      voted_for: state.voted_for
    }

    :ok = :dets.insert(@dets_table, {:meta, meta})
  end

  defp send_request_vote_response(state, candidate_id, granted) do
    rpc = %{
      term: state.current_term,
      vote_granted: granted,
      voter_id: state.id
    }

    GenServer.cast({__MODULE__, candidate_id}, {:request_vote_response, rpc})
  end

  defp candidate_log_up_to_date?(rpc, state) do
    local_last_term = last_log_term(state)

    if rpc.last_log_term > local_last_term do
      true
    else
      if rpc.last_log_term < local_last_term do
        false
      else
        rpc.last_log_index >= state.last_index
      end
    end
  end
end
