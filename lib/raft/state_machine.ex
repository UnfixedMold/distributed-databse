defmodule Raft.StateMachine do
  @moduledoc """
  Behaviour for Raft-managed state machines.

  Raft is independent of application state. It invokes `apply/1`
  with an opaque binary command whenever a committed log entry
  should be applied. The callback is responsible for updating
  its own state and returning a reply.
  """

  @callback apply(command :: binary()) :: term()
end
