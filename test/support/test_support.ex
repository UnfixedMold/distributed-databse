defmodule DistDb.TestSupport do
  @moduledoc false

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

  def start_cluster(count) do
    {:ok, cluster} = LocalCluster.start_link(count)
    {:ok, nodes} = LocalCluster.nodes(cluster)

    Enum.each(nodes, fn n ->
      :rpc.call(n, Application, :ensure_all_started, [:dist_db])
    end)

    {cluster, nodes}
  end

  def stop_cluster(cluster) do
    LocalCluster.stop(cluster)
  end
end
