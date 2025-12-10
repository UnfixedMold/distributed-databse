defmodule DistDb.Application do
  @moduledoc """
  The DistDb Application supervisor.

  Starts the Store GenServer when the application boots.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting DistDb application on node #{Node.self()}")

    topologies = [
      gossip: [strategy: Cluster.Strategy.Gossip]
    ]

    children = [
      {Cluster.Supervisor, [topologies, [name: DistDb.ClusterSupervisor]]},
      DistDb.Raft,
      DistDb.Store
    ]

    opts = [strategy: :one_for_one, name: DistDb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
