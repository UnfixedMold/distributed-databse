defmodule DistDb.Storage do
  @moduledoc """
  Helpers for node-local storage paths.

  Provides utilities to place DETS files under `app_data/<node>/...`.
  Shared by DistDb.Store and DistDb.Raft.
  """

  @data_root "app_data"

  @doc """
  Returns the directory for this node's data under app_data.
  """
  def get_node_data_dir(node) do
    Path.join(@data_root, Atom.to_string(node))
  end

  @doc """
  Ensures the node's data directory exists and returns its path.
  """
  def ensure_node_dir(node) do
    dir = get_node_data_dir(node)
    :ok = File.mkdir_p(dir)
    dir
  end

  @doc """
  Returns a charlist path to a DETS file for this node and basename,
  ensuring the directory exists.
  """
  def get_node_dets_file(node, basename) do
    node
    |> ensure_node_dir()
    |> Path.join(basename)
    |> String.to_charlist()
  end

  @doc """
  Opens a DETS table for the current node under app_data and returns the file path.
  """
  def open_node_dets(table, basename) do
    dets_file = get_node_dets_file(Node.self(), basename)
    {:ok, _} = :dets.open_file(table, type: :set, file: dets_file)
    dets_file
  end
end
