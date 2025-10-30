defmodule DistDb.IntegrationTest do
  use ExUnit.Case, async: false
  import DistDb.TestSupport

  describe "distributed workflow" do
    test "complete multi-node flow" do
      {cluster, [node1, node2]} = start_cluster(2)
      wait_until_connected([node1, node2])

      # Write initial data from node1
      assert :ok =
               :rpc.call(node1, DistDb.Store, :put, ["user:1", %{name: "alice", role: "admin"}])

      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["user:2", %{name: "bob", role: "user"}])

      eventually(fn ->
        assert %{name: "alice"} = :rpc.call(node2, DistDb.Store, :get, ["user:1"])
        assert %{name: "bob"} = :rpc.call(node2, DistDb.Store, :get, ["user:2"])
      end)

      # Update from node2
      assert :ok =
               :rpc.call(node2, DistDb.Store, :put, [
                 "user:1",
                 %{name: "alice", role: "superadmin"}
               ])

      eventually(
        fn ->
          assert %{role: "superadmin"} = :rpc.call(node1, DistDb.Store, :get, ["user:1"])
        end,
        200,
        20
      )

      # Add a third node
      {:ok, _members} = LocalCluster.start(cluster, 1)
      {:ok, [_node1, _node2, node3]} = LocalCluster.nodes(cluster)

      wait_until_connected([node1, node2, node3])

      # node3 starts empty (sync-on-startup doesn't work with LocalCluster timing)
      # Manually trigger sync by sending nodeup message to node3
      :rpc.call(node3, Process, :send, [DistDb.Store, {:nodeup, node1}, []])

      eventually(fn ->
        assert %{name: "alice", role: "superadmin"} =
                 :rpc.call(node3, DistDb.Store, :get, ["user:1"])
      end)

      # Write something from node3 - it should replicate to others
      assert :ok = :rpc.call(node3, DistDb.Store, :put, ["user:3", %{name: "charlie"}])

      eventually(fn ->
        assert %{name: "charlie"} = :rpc.call(node1, DistDb.Store, :get, ["user:3"])
        assert %{name: "charlie"} = :rpc.call(node2, DistDb.Store, :get, ["user:3"])
      end)

      # Delete from node3
      assert :ok = :rpc.call(node3, DistDb.Store, :delete, ["user:2"])

      eventually(fn ->
        assert nil == :rpc.call(node1, DistDb.Store, :get, ["user:2"])
        assert nil == :rpc.call(node2, DistDb.Store, :get, ["user:2"])
      end)

      # All three nodes should have consistent state
      eventually(fn ->
        state1 = :rpc.call(node1, DistDb.Store, :list_all, [])
        state2 = :rpc.call(node2, DistDb.Store, :list_all, [])
        state3 = :rpc.call(node3, DistDb.Store, :list_all, [])

        assert state1 == state2
        assert state2 == state3
        assert map_size(state1) == 2
        assert %{role: "superadmin"} = Map.get(state1, "user:1")
        assert %{name: "charlie"} = Map.get(state1, "user:3")
      end)

      stop_cluster(cluster)
    end
  end
end
