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
  @heartbeat_interval 75

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

  Only the current leader accepts proposals; followers return
  an error indicating who they believe the leader is.
  """
  @spec propose(command()) :: reply :: term()
  def propose(command) when is_binary(command) do
    GenServer.call(__MODULE__, {:propose, command})
  end

  @doc """
  Groups cluster nodes by their reported role.

  Returns `%{leaders: [...], followers: [...], candidates: [...]}`.
  """
  def roles do
    role_buckets =
      Enum.reduce([Node.self() | Node.list()], %{leaders: [], followers: [], candidates: []}, fn node, acc ->
        case rpc_role(node) do
          %{role: :leader} -> Map.update!(acc, :leaders, &[node | &1])
          %{role: :follower} -> Map.update!(acc, :followers, &[node | &1])
          %{role: :candidate} -> Map.update!(acc, :candidates, &[node | &1])
          _ -> acc
        end
      end)

    buckets =
      role_buckets
      |> Enum.map(fn {k, v} -> {k, Enum.reverse(v)} end)
      |> Map.new()
    buckets
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

    commit_index = Map.get(persisted_meta, :commit_index, 0)

    state = %{
      id: Node.self(),
      role: :follower,
      leader_id: nil,
      current_term: persisted_meta.current_term,
      voted_for: persisted_meta.voted_for,
      log: log,
      last_index: last_index,
      commit_index: commit_index,
      last_applied: commit_index,
      apply_fun: apply_fun,
      next_index: %{},
      match_index: %{},
      votes_received: 0,
      election_timeout_ref: nil,
      heartbeat_ref: nil
    }

    state =
      if peers() == [] do
        become_leader(state)
      else
        reset_election_timeout(state)
      end

    {:ok, state}
  end

  @impl true
  def handle_call(:role_snapshot, _from, state) do
    snapshot = %{
      role: state.role,
      leader_id: state.leader_id,
      current_term: state.current_term
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_call({:propose, command}, _from, state) do
    case state.role do
      :leader ->
        {_entry, state} = append_entry(command, state)
        state = replicate_entry_to_followers(state)
        state = maybe_advance_leader_commit(state)
        {:reply, :ok, state}

      _other ->
        {:reply, {:error, :not_leader, state.leader_id}, state}
    end
  end

  @impl true
  def handle_cast({:request_vote, rpc}, state) do
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

          Logger.info(
            "[#{inspect(Node.self())}] granted vote for #{inspect(rpc.candidate_id)} in term #{rpc.term}"
          )

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
    state = maybe_step_down(state, rpc.term)

    {state, success} =
      if rpc.term < state.current_term do
        {state, false}
      else
        state =
          state
          |> Map.put(:leader_id, rpc.leader_id)
          |> Map.put(:role, :follower)
          |> reset_election_timeout()

        apply_append_entries(state, rpc)
      end

    send_append_entries_response(state, rpc.leader_id, success)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:request_vote_response, rpc}, state) do
    state = maybe_step_down(state, rpc.term)

    state =
      if state.role == :candidate and rpc.term == state.current_term and rpc.vote_granted do
        total_nodes = 1 + length(peers())
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
  def handle_cast({:append_entries_response, rpc}, state) do
    state = maybe_step_down(state, rpc.term)

    state =
      if state.role == :leader and rpc.term == state.current_term do
        handle_append_entries_ack(rpc, state)
      else
        state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:election_timeout, state) do
    state =
      case state.role do
        :leader -> state
        _ -> start_election(state)
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    state =
      case state.role do
        :leader ->
          Enum.each(peers(), fn peer ->
            send_append_entries_to_peer(peer, state)
          end)

          schedule_heartbeat(state)

        _other ->
          cancel_heartbeat(state)
      end

    {:noreply, state}
  end

  ## Log and commit helpers

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

  defp maybe_advance_leader_commit(state) do
    if state.role != :leader do
      state
    else
      new_commit_index = compute_leader_commit_index(state)

      if new_commit_index > state.commit_index do
        {state, _reply} = advance_commit_index(new_commit_index, state)
        state
      else
        state
      end
    end
  end

  defp compute_leader_commit_index(state) do
    total_nodes = 1 + length(peers())
    majority = div(total_nodes, 2) + 1

    candidate_indices =
      state.log
      |> Enum.filter(fn entry ->
        entry.term == state.current_term and entry.index > state.commit_index
      end)
      |> Enum.map(& &1.index)

    Enum.reduce(candidate_indices, state.commit_index, fn index, acc ->
      count =
        1 +
          Enum.count(peers(), fn peer ->
            Map.get(state.match_index, peer, 0) >= index
          end)

      if count >= majority do
        max(acc, index)
      else
        acc
      end
    end)
  end

  defp replicate_entry_to_followers(state) do
    Enum.each(peers(), fn peer ->
      send_append_entries_to_peer(peer, state)
    end)

    state
  end

  defp apply_append_entries(state, rpc) do
    if not prev_log_matches?(state, rpc.prev_log_index, rpc.prev_log_term) do
      Logger.info(
        "[#{inspect(Node.self())}] rejected AppendEntries from #{inspect(rpc.leader_id)} in term #{rpc.term} due to log mismatch at index #{rpc.prev_log_index}"
      )

      {state, false}
    else
      state =
        state
        |> truncate_log_after(rpc.prev_log_index)
        |> append_entries(rpc.entries)

      if rpc.entries != [] do
        Logger.info(
          "[#{inspect(Node.self())}] appended #{length(rpc.entries)} entries from #{inspect(rpc.leader_id)} up to index #{state.last_index} in term #{rpc.term}"
        )
      end

      new_commit_index = min(rpc.leader_commit, state.last_index)
      {state, _reply} = advance_commit_index(new_commit_index, state)

      {state, true}
    end
  end

  defp apply_committed_entries(state) do
    if state.commit_index == state.last_applied do
      # Nothing new to apply
      {state, nil}
    else
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

  defp last_log_term(%{log: []}), do: 0
  defp last_log_term(%{log: [%{term: term} | _]}), do: term

  defp term_at_index(_state, 0), do: 0

  defp term_at_index(state, index) do
    case Enum.find(state.log, &(&1.index == index)) do
      nil -> 0
      %{term: term} -> term
    end
  end

  defp truncate_log_after(state, index) do
    new_log = Enum.reject(state.log, &(&1.index > index))
    %{state | log: new_log}
  end

  defp append_entries(state, entries) do
    Enum.reduce(entries, state, fn entry, st ->
      persist_entry(entry, st)

      %{
        st
        | log: [entry | st.log],
          last_index: max(st.last_index, entry.index)
      }
    end)
  end

  defp entries_from(state, from_index) do
    state.log
    |> Enum.filter(&(&1.index >= from_index))
    |> Enum.sort_by(& &1.index)
  end

  defp prev_log_matches?(_state, 0, _term), do: true

  defp prev_log_matches?(state, prev_index, prev_term) do
    case Enum.find(state.log, &(&1.index == prev_index)) do
      nil -> false
      %{term: term} -> term == prev_term
    end
  end

  ## Election, voting and role helpers

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
        votes_received: 0,
        next_index: %{},
        match_index: %{}
    }

    persist_meta(state1)
    reset_election_timeout(state1)
  end

  defp become_leader(state) do
    Logger.info("[#{inspect(Node.self())}] became leader in term #{state.current_term}")

    last_index = state.last_index

    next_index =
      peers()
      |> Enum.map(&{&1, last_index + 1})
      |> Map.new()

    match_index =
      peers()
      |> Enum.map(&{&1, 0})
      |> Map.new()

    state =
      state
      |> cancel_election_timeout()
      |> cancel_heartbeat()
      |> Map.put(:role, :leader)
      |> Map.put(:leader_id, state.id)
      |> Map.put(:votes_received, 0)
      |> Map.put(:next_index, next_index)
      |> Map.put(:match_index, match_index)

    schedule_heartbeat(state)
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

  defp schedule_heartbeat(state) do
    ref = Process.send_after(self(), :heartbeat, @heartbeat_interval)
    %{state | heartbeat_ref: ref}
  end

  defp cancel_heartbeat(state) do
    if state.heartbeat_ref do
      Process.cancel_timer(state.heartbeat_ref)
    end

    %{state | heartbeat_ref: nil}
  end

  defp maybe_step_down(state, rpc_term) do
    if rpc_term > state.current_term do
      become_follower(state, rpc_term, nil)
    else
      state
    end
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

  ## RPC helpers

  defp broadcast_request_vote(state) do
    rpc = %{
      term: state.current_term,
      candidate_id: state.id,
      last_log_index: state.last_index,
      last_log_term: last_log_term(state)
    }

    Enum.each(peers(), fn peer ->
      GenServer.cast({__MODULE__, peer}, {:request_vote, rpc})
    end)
  end

  defp send_append_entries_to_peer(peer, state) do
    next_index = Map.get(state.next_index, peer, state.last_index + 1)
    prev_index = max(next_index - 1, 0)
    prev_term = term_at_index(state, prev_index)
    entries = entries_from(state, next_index)

    rpc = %{
      term: state.current_term,
      leader_id: state.id,
      prev_log_index: prev_index,
      prev_log_term: prev_term,
      entries: entries,
      leader_commit: state.commit_index
    }

    GenServer.cast({__MODULE__, peer}, {:append_entries, rpc})
  end

  defp send_request_vote_response(state, candidate_id, granted) do
    rpc = %{
      term: state.current_term,
      vote_granted: granted,
      voter_id: state.id
    }

    GenServer.cast({__MODULE__, candidate_id}, {:request_vote_response, rpc})
  end

  defp send_append_entries_response(state, leader_id, success) do
    rpc = %{
      term: state.current_term,
      success: success,
      follower_id: state.id,
      match_index: state.last_index
    }

    GenServer.cast({__MODULE__, leader_id}, {:append_entries_response, rpc})
  end

  defp peers do
    Node.list()
    |> Enum.reject(&(&1 == Node.self()))
  end

  defp handle_append_entries_ack(rpc, state) do
    peer = rpc.follower_id

    state =
      if rpc.success do
        new_match = rpc.match_index

        new_next_index =
          Map.put(state.next_index, peer, new_match + 1)

        new_match_index =
          Map.put(state.match_index, peer, new_match)

        %{state | next_index: new_next_index, match_index: new_match_index}
      else
        current_next = Map.get(state.next_index, peer, state.last_index + 1)
        new_next = max(1, current_next - 1)
        %{state | next_index: Map.put(state.next_index, peer, new_next)}
      end

    maybe_advance_leader_commit(state)
  end

  ## Persistence (DETS) helpers

  defp load_persistent_state do
    meta =
      case :dets.lookup(@dets_table, :meta) do
        [{:meta, value}] -> value
        [] -> %{current_term: 0, voted_for: nil, commit_index: 0}
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
      voted_for: state.voted_for,
      commit_index: state.commit_index
    }

    :ok = :dets.insert(@dets_table, {:meta, meta})
  end

  @impl true
  def terminate(_reason, _state) do
    :dets.close(@dets_table)
    :ok
  end

  defp rpc_role(node) do
    if node == Node.self() do
      GenServer.call(__MODULE__, :role_snapshot)
    else
      case :rpc.call(node, GenServer, :call, [__MODULE__, :role_snapshot]) do
        {:badrpc, reason} -> {:error, reason}
        snapshot -> snapshot
      end
    end
  end
end
