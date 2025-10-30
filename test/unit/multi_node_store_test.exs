defmodule DistDb.MultiNodeStoreTest do
  use ExUnit.Case, async: false
  import DistDb.TestSupport

  describe "multi-node replication" do
    test "put replicates to all" do
      {cluster, nodes = [node1, node2, node3]} = start_cluster(3)
      wait_until_connected(nodes)

      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["k", 1])

      eventually(fn ->
        assert 1 = :rpc.call(node1, DistDb.Store, :get, ["k"])
        assert 1 = :rpc.call(node2, DistDb.Store, :get, ["k"])
        assert 1 = :rpc.call(node3, DistDb.Store, :get, ["k"])
      end, 200, 20)

      stop_cluster(cluster)
    end

    test "delete replicates" do
      {cluster, nodes = [node1, node2]} = start_cluster(2)
      wait_until_connected(nodes)

      assert :ok = :rpc.call(node1, DistDb.Store, :put, ["temp", "x"])
      eventually(fn -> assert "x" = :rpc.call(node2, DistDb.Store, :get, ["temp"]) end, 200, 20)

      assert :ok = :rpc.call(node2, DistDb.Store, :delete, ["temp"])

      eventually(fn ->
        assert nil == :rpc.call(node1, DistDb.Store, :get, ["temp"])
        assert nil == :rpc.call(node2, DistDb.Store, :get, ["temp"])
      end, 200, 20)

      stop_cluster(cluster)
    end
  end
end
