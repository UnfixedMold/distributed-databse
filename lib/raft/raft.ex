defmodule Raft do
  @moduledoc """
  Stub Raft API.

  The full consensus implementation will be added later.
  For now, `propose/1` is a no-op placeholder used by the
  DistDb.Store interface.
  """

  @type command :: binary()

  @spec propose(command()) :: :ok
  def propose(_command), do: :ok
end
