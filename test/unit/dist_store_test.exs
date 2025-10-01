defmodule DistDb.ReplicationTest do
  use ExUnit.Case, async: false

  defp start_cluster(node_count) do
    {:ok, cluster} = LocalCluster.start_link(node_count, applications: [:dist_db])
    {:ok, nodes} = LocalCluster.nodes(cluster)
    {cluster, nodes}
  end

  defp stop_cluster(cluster) do
    LocalCluster.stop(cluster)
  end

  describe "distributed put replication" do
    test "put replicates to all nodes in cluster" do
      {cluster, [node1, node2, node3]} = start_cluster(3)

      # Put a value on node1
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["key1", "value1"])

      # Give replication time to propagate
      Process.sleep(100)

      # Verify all nodes have the value
      assert "value1" = :rpc.call(node1, DistDb.Store, :get, ["key1"])
      assert "value1" = :rpc.call(node2, DistDb.Store, :get, ["key1"])
      assert "value1" = :rpc.call(node3, DistDb.Store, :get, ["key1"])

      stop_cluster(cluster)
    end

    test "multiple puts from different nodes all replicate" do
      {cluster, [node1, node2, node3]} = start_cluster(3)

      # Put different values from different nodes
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["key1", "from_node1"])
      assert :ok = :rpc.call(node2, DistDb.Store, :put, ["key2", "from_node2"])
      assert :ok = :rpc.call(node3, DistDb.Store, :put, ["key3", "from_node3"])

      Process.sleep(100)

      # All nodes should have all three keys
      for node <- [node1, node2, node3] do
        assert "from_node1" = :rpc.call(node, DistDb.Store, :get, ["key1"])
        assert "from_node2" = :rpc.call(node, DistDb.Store, :get, ["key2"])
        assert "from_node3" = :rpc.call(node, DistDb.Store, :get, ["key3"])
      end

      stop_cluster(cluster)
    end

    test "put updates existing value across all nodes" do
      {cluster, [node1, node2]} = start_cluster(2)

      # Initial put
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["counter", 1])
      Process.sleep(100)

      # Update from a different node
      assert :ok = :rpc.call(node2, DistDb.Store, :put, ["counter", 2])
      Process.sleep(100)

      # Both nodes should have the updated value
      assert 2 = :rpc.call(node1, DistDb.Store, :get, ["counter"])
      assert 2 = :rpc.call(node2, DistDb.Store, :get, ["counter"])

      stop_cluster(cluster)
    end
  end

  describe "distributed delete replication" do
    test "delete replicates to all nodes in cluster" do
      {cluster, [node1, node2, node3]} = start_cluster(3)

      # Put a value on node1
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["key1", "value1"])
      Process.sleep(100)

      # Verify all nodes have it
      assert "value1" = :rpc.call(node1, DistDb.Store, :get, ["key1"])
      assert "value1" = :rpc.call(node2, DistDb.Store, :get, ["key1"])
      assert "value1" = :rpc.call(node3, DistDb.Store, :get, ["key1"])

      # Delete from node2
      assert :ok = :rpc.call(node2, DistDb.Store, :delete, ["key1"])
      Process.sleep(100)

      # Verify all nodes have it deleted
      assert nil == :rpc.call(node1, DistDb.Store, :get, ["key1"])
      assert nil == :rpc.call(node2, DistDb.Store, :get, ["key1"])
      assert nil == :rpc.call(node3, DistDb.Store, :get, ["key1"])

      stop_cluster(cluster)
    end

    test "multiple deletes from different nodes" do
      {cluster, [node1, node2]} = start_cluster(2)

      # Create some data
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["key1", "value1"])
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["key2", "value2"])
      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["key3", "value3"])
      Process.sleep(100)

      # Delete from different nodes
      assert :ok = :rpc.call(node1, DistDb.Store, :delete, ["key1"])
      assert :ok = :rpc.call(node2, DistDb.Store, :delete, ["key2"])
      Process.sleep(100)

      # Both nodes should have the same state (only key3 remains)
      state1 = :rpc.call(node1, DistDb.Store, :list_all, [])
      state2 = :rpc.call(node2, DistDb.Store, :list_all, [])

      assert %{"key3" => "value3"} = state1
      assert %{"key3" => "value3"} = state2
      refute Map.has_key?(state1, "key1")
      refute Map.has_key?(state1, "key2")

      stop_cluster(cluster)
    end
  end
end
