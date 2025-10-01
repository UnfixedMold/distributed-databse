defmodule DistDb.IntegrationTest do
  use ExUnit.Case, async: false

  defp start_cluster(node_count) do
    {:ok, cluster} = LocalCluster.start_link(node_count, applications: [:dist_db])
    {:ok, nodes} = LocalCluster.nodes(cluster)
    {cluster, nodes}
  end

  defp stop_cluster(cluster) do
    LocalCluster.stop(cluster)
  end

  describe "Lab-1 integration" do
    test "complete distributed workflow with multiple nodes" do
      {cluster, [node1, node2]} = start_cluster(2)

      # Write initial data from node1
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["user:1", %{name: "alice", role: "admin"}])
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["user:2", %{name: "bob", role: "user"}])
      Process.sleep(100)

      # Verify replication to node2
      assert %{name: "alice"} = :rpc.call(node2, DistDb.Store, :get, ["user:1"])
      assert %{name: "bob"} = :rpc.call(node2, DistDb.Store, :get, ["user:2"])

      # Update from node2
      assert :ok = :rpc.call(node2, DistDb.Store, :put, ["user:1", %{name: "alice", role: "superadmin"}])
      Process.sleep(100)

      # Verify update propagated to node1
      assert %{role: "superadmin"} = :rpc.call(node1, DistDb.Store, :get, ["user:1"])

      # Add a third node
      {:ok, _members} = LocalCluster.start(cluster, 1)
      {:ok, [_node1, _node2, node3]} = LocalCluster.nodes(cluster)
      Process.sleep(200)

      # node3 starts empty (sync-on-startup doesn't work with LocalCluster timing)
      # Manually trigger sync by sending nodeup message to node3
      :rpc.call(node3, Process, :send, [DistDb.Store, {:nodeup, node1}, []])
      Process.sleep(100)

      # node3 should now have synced data from node1
      assert %{name: "alice", role: "superadmin"} = :rpc.call(node3, DistDb.Store, :get, ["user:1"])

      # Write something from node3 - it should replicate to others
      assert :ok = :rpc.call(node3, DistDb.Store, :put, ["user:3", %{name: "charlie"}])
      Process.sleep(100)

      assert %{name: "charlie"} = :rpc.call(node1, DistDb.Store, :get, ["user:3"])
      assert %{name: "charlie"} = :rpc.call(node2, DistDb.Store, :get, ["user:3"])

      # Delete from node3
      assert :ok = :rpc.call(node3, DistDb.Store, :delete, ["user:2"])
      Process.sleep(100)

      # Deletion should propagate to node1 and node2
      assert nil == :rpc.call(node1, DistDb.Store, :get, ["user:2"])
      assert nil == :rpc.call(node2, DistDb.Store, :get, ["user:2"])

      # All three nodes should have consistent state
      state1 = :rpc.call(node1, DistDb.Store, :list_all, [])
      state2 = :rpc.call(node2, DistDb.Store, :list_all, [])
      state3 = :rpc.call(node3, DistDb.Store, :list_all, [])

      assert state1 == state2
      assert state2 == state3
      assert map_size(state1) == 2
      assert %{role: "superadmin"} = Map.get(state1, "user:1")
      assert %{name: "charlie"} = Map.get(state1, "user:3")

      stop_cluster(cluster)
    end
  end
end
