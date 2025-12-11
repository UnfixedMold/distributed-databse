defmodule DistDb.MultiNodeClusterTest do
  use ExUnit.Case, async: false
  import DistDb.TestSupport

  @node_count 3

  setup do
    {cluster, nodes} = start_cluster(@node_count)
    on_exit(fn -> File.rm_rf!("app_data") end)

    {:ok, cluster: cluster, nodes: nodes}
  end

  test "replicates across three worker nodes (manager excluded)", %{
    cluster: cluster,
    nodes: nodes
  } do
    {leader, followers} = get_leader_and_followers(hd(nodes))

    assert :ok = :rpc.call(leader, DistDb.Store, :put, [:k1, "v1"])
    assert_replication([leader | followers], %{:k1 => "v1"})

    remaining = kill_leader(cluster, leader, nodes)

    {new_leader, new_followers} = get_leader_and_followers(hd(remaining))

    assert :ok = :rpc.call(new_leader, DistDb.Store, :put, [:k2, "v2"])
    assert_replication([new_leader | new_followers], %{:k1 => "v1", :k2 => "v2"})

    updated_nodes = add_node(cluster)
    assert_replication(updated_nodes, %{:k1 => "v1", :k2 => "v2"})
  end

  defp get_leader_and_followers(node) do
    roles =
      eventually(fn ->
        r = :rpc.call(node, DistDb.Raft, :roles, [])
        assert Enum.count(Map.get(r, :leaders, [])) == 1
        r
      end)

    leader = hd(Map.get(roles, :leaders, []))
    followers = Map.get(roles, :followers, [])
    {leader, followers}
  end

  defp kill_leader(cluster, leader, all_nodes) do
    :ok = LocalCluster.stop(cluster, leader)
    Enum.reject(all_nodes, &(&1 == leader))
  end

  defp assert_replication(nodes, expected_map) do
    Enum.each(nodes, fn node ->
      eventually(fn -> assert :rpc.call(node, DistDb.Store, :get, []) == expected_map end)
    end)
  end

  defp add_node(cluster) do
    {:ok, _} = LocalCluster.start(cluster, 1)
    {:ok, nodes} = LocalCluster.nodes(cluster)
    nodes
  end
end
