defmodule DistDb.Application do
  @moduledoc """
  The DistDb Application supervisor.

  Starts the Raft and Store processes.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting DistDb application on node #{Node.self()}")

    children = [
      {DistDb.Store, []},
      {DistDb.Raft, [apply_fun: &DistDb.Store.apply/1]}
    ]

    opts = [strategy: :one_for_one, name: DistDb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
