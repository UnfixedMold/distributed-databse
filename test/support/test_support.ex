defmodule DistDb.TestSupport do
  @moduledoc false

  import ExUnit.Assertions

  def eventually(fun, attempts \\ 50, delay \\ 20)

  def eventually(fun, attempts, _delay) when attempts <= 0 do
    fun.()
  end

  def eventually(fun, attempts, delay) do
    try do
      fun.()
    rescue
      _error ->
        Process.sleep(delay)
        eventually(fun, attempts - 1, delay)
    end
  end

  def start_cluster(node_count) do
    {:ok, cluster} = LocalCluster.start_link(node_count, applications: [:dist_db])
    {:ok, nodes} = LocalCluster.nodes(cluster)
    {cluster, nodes}
  end

  def stop_cluster(cluster) do
    try do
      LocalCluster.stop(cluster)
    catch
      :exit, {:noproc, _} -> :ok
      :exit, {:shutdown, _} -> :ok
      :exit, _ -> :ok
    end
  end

  def wait_until_connected(nodes) do
    Enum.each(nodes, fn node ->
      others = List.delete(nodes, node)

      eventually(fn ->
        listed = :rpc.call(node, Node, :list, [])
        Enum.each(others, fn other -> assert other in listed end)
      end)
    end)
  end
end
