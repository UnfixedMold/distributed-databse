defmodule DistDb.Raft do
  @moduledoc """
  Stub Raft API scoped to DistDb.

  The full consensus implementation will be added later.
  For now, `propose/1` simply executes a zero-arity callback
  that applies the operation locally. Later, Raft will own
  the log and call this callback on commit.
  """

  @type command :: (() -> term())

  @spec propose(command()) :: :ok
  def propose(fun) when is_function(fun, 0), do: fun.()
end

