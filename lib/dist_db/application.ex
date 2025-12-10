defmodule DistDb.Application do
  @moduledoc """
  The DistDb Application supervisor.

  Starts the Raft and Store processes plus clustering when the application boots.
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
      {DistDb.Store, []},
      {Raft, [apply_fun: &DistDb.Store.apply/1]}
    ]

    opts = [strategy: :one_for_one, name: DistDb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
