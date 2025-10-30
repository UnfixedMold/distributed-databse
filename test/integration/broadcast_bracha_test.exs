defmodule DistDb.BroadcastBrachaTest do
  use ExUnit.Case, async: false
  import DistDb.TestSupport

  setup do
    {cluster, nodes} = start_cluster(4)
    on_exit(fn -> stop_cluster(cluster) end)
    wait_until_connected(nodes)
    {:ok, nodes: nodes}
  end

  describe "bracha broadcast" do
    test "reaches quorum thresholds on every node", %{nodes: [node1 | _] = nodes} do
      assert get_broadcast_state(node1).messages == %{}

      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["quorum", "value"])

      msg_id = wait_for_single_message_id(node1)
      thresholds = DistDb.Broadcast.Thresholds.for_node_count(length(nodes))

      Enum.each(nodes, fn node ->
        eventually(fn ->
          entry = get_message_entry(node, msg_id)

          assert entry.seen_send
          assert entry.sent_echo
          assert entry.sent_ready
          assert entry.delivered
          assert MapSet.size(entry.echo_from) >= thresholds.echo
          assert MapSet.size(entry.ready_from) >= thresholds.deliver
        end)
      end)
    end

    test "ignores duplicate echoes", %{nodes: [node1, node2 | _]} do
      assert get_broadcast_state(node1).messages == %{}
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["dup", "value"])

      msg_id = wait_for_single_message_id(node1)

      {expected_count, entry_before} =
        eventually(fn ->
          entry = get_message_entry(node2, msg_id)
          expected = length(:rpc.call(node2, Node, :list, [])) + 1

          assert entry.delivered
          assert MapSet.size(entry.echo_from) == expected
          {expected, entry}
        end)

      duplicate_msg = %{id: msg_id, deliver: nil}

      :rpc.call(node2, GenServer, :cast, [
        {DistDb.Broadcast, node2},
        {:protocol, :echo, duplicate_msg, node1}
      ])

      Process.sleep(50)

      entry_after = get_message_entry(node2, msg_id)

      assert MapSet.size(entry_after.echo_from) == expected_count
      assert MapSet.equal?(entry_after.echo_from, entry_before.echo_from)
    end

    test "correct nodes deliver even if sender crashes", %{nodes: [node1, node2, node3, node4]} do
      assert get_broadcast_state(node1).messages == %{}
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["crash", "value"])

      msg_id = wait_for_single_message_id(node1)

      # Give the SEND a moment to propagate before killing the broadcaster.
      Process.sleep(50)

      if pid = :rpc.call(node1, Process, :whereis, [DistDb.Broadcast]) do
        :rpc.call(node1, Process, :exit, [pid, :kill])
      end

      for node <- [node2, node3, node4] do
        eventually(fn -> assert "value" = :rpc.call(node, DistDb.Store, :get, ["crash"]) end)
        eventually(fn -> assert get_message_entry(node, msg_id).delivered end)
      end
    end
  end

  defp wait_for_single_message_id(node) do
    eventually(fn ->
      messages =
        get_broadcast_state(node)
        |> Map.fetch!(:messages)

      case Map.keys(messages) do
        [msg_id] ->
          msg_id

        [] ->
          raise "no messages observed yet on #{inspect(node)}"

        many ->
          raise "unexpected messages already present on #{inspect(node)}: #{inspect(many)}"
      end
    end)
  end

  defp get_broadcast_state(node) do
    :rpc.call(node, :sys, :get_state, [DistDb.Broadcast])
  end

  defp get_message_entry(node, msg_id) do
    state = get_broadcast_state(node)
    Map.fetch!(state.messages, msg_id)
  end
end
