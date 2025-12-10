defmodule Raft do
  @moduledoc """
  Stub Raft API.

  The full consensus implementation will be added later.
  For now, `propose/1` simply forwards the opaque command
  to the configured state machine callback.
  """

  @type command :: binary()

  @spec propose(command()) :: :ok
  def propose(command) do
    DistDb.Store.apply(command)
    :ok
  end
end
