defmodule DistDb.BroadcastBrachaTest do
  use ExUnit.Case, async: false
  import DistDb.TestSupport

  @replica_count 3
  @total_nodes @replica_count + 1

  setup do
    {cluster, nodes} = start_cluster(@replica_count)
    on_exit(fn -> stop_cluster(cluster) end)
    wait_until_connected(nodes)
    {:ok, nodes: nodes}
  end

  describe "bracha broadcast" do
    test "reaches quorum thresholds on every node", %{nodes: [node1 | _] = nodes} do
      assert get_broadcast_state(node1).messages == %{}

      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["quorum", "value"])

      msg_id = wait_for_single_message_id(node1)
      thresholds = DistDb.Broadcast.Thresholds.for_node_count(@total_nodes)

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
      delivered_entry =
        eventually(fn ->
          entry = get_message_entry(node2, msg_id)

          assert entry.delivered
          assert MapSet.size(entry.echo_from) == @total_nodes
          entry
        end)

      :rpc.call(node2, GenServer, :cast, [
        {DistDb.Broadcast, node2},
        {:protocol, :echo, %{deliver: nil, id: msg_id}, node1}
      ])

      Process.sleep(50)

      post_duplicate_entry = get_message_entry(node2, msg_id)

      assert MapSet.size(post_duplicate_entry.echo_from) == @total_nodes
      assert MapSet.equal?(post_duplicate_entry.echo_from, delivered_entry.echo_from)
    end

    test "correct nodes deliver even if sender crashes", %{nodes: [node1 | other_nodes]} do
      assert get_broadcast_state(node1).messages == %{}
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["crash", "value"])

      msg_id = wait_for_single_message_id(node1)

      # Give the SEND a moment to propagate before killing the broadcaster.
      Process.sleep(50)

      if pid = :rpc.call(node1, Process, :whereis, [DistDb.Broadcast]) do
        :rpc.call(node1, Process, :exit, [pid, :kill])
      end

      for node <- other_nodes do
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
