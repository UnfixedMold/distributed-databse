defmodule DistDb.Broadcast do
  @moduledoc """
  Simple Uniform Reliable Broadcast (URB) implementation.

  Algorithm:
    URB_Broadcast(m):
      send MSG(m) to self

    When MSG(m) is received from sender:
      if first reception of m:
        relay MSG(m) to all nodes except self and sender
        URB_deliver(m)

  This provides uniform agreement: if any process delivers m,
  all correct processes eventually deliver m.
  """

  use GenServer
  require Logger

  ## ========== CLIENT API ==========

  @doc """
  Starts the Broadcast GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  URB-broadcast a zero-arity function that performs the delivery side-effect.
  """
  def urb_broadcast(deliver_callback) when is_function(deliver_callback, 0) do
    # Call myself to initialize the broadcast
    GenServer.cast(__MODULE__, {:urb_broadcast, deliver_callback})
  end

  ## ========== SERVER CALLBACKS ==========

  @impl true
  def init(:ok) do
    Logger.info("Starting DistDb.Broadcast on node #{Node.self()}")
    {:ok, %{delivered: []}}
  end

  @impl true
  def handle_cast({:urb_broadcast, deliver_callback}, state) do
    # Generate unique message ID
    msg_id = {Node.self(), :erlang.unique_integer([:monotonic])}
    msg = {msg_id, deliver_callback, Node.self()}

    Logger.debug("URB broadcasting: #{inspect(msg_id)}")

    # Send MSG(m) to self
    GenServer.cast({__MODULE__, Node.self()}, {:msg, msg})

    {:noreply, state}
  end

  @impl true
  def handle_cast({:msg, {msg_id, deliver_callback, sender} = msg}, state) do
    if msg_id in state.delivered do
      # Not first reception - ignore duplicate
      Logger.debug("Ignoring duplicate message: #{inspect(msg_id)}")
      {:noreply, state}
    else
      # First reception of m
      Logger.debug("First reception of #{inspect(msg_id)} from #{sender}")

      # 1. Relay to all nodes except self and sender
      relay_nodes = Node.list() -- [sender]

      Logger.debug("Relaying #{inspect(msg_id)} to #{inspect(relay_nodes)}")

      Enum.each(relay_nodes, fn node ->
        GenServer.cast({__MODULE__, node}, {:msg, msg})
      end)

      # 2. URB_deliver(m) - invoke delivery callback
      Logger.debug("URB delivering #{inspect(msg_id)} via provided function")
      deliver_callback.()

      # 3. Mark as delivered (prepend to list)
      new_state = %{state | delivered: [msg_id | state.delivered]}

      {:noreply, new_state}
    end
  end
end
