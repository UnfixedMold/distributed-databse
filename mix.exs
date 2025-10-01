defmodule DistDb.MixProject do
  use Mix.Project

  def project do
    [
      app: :dist_db,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {DistDb.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:local_cluster, "~> 2.0", only: :test},
      {:libcluster, "~> 3.4"}
    ]
  end
end
