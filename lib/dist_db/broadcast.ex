defmodule DistDb.Broadcast do
  @moduledoc """
  Bracha Byzantine Reliable Broadcast (RBC) implementation.

  The algorithm progresses through SEND → ECHO → READY phases and
  relies on quorum thresholds derived from the cluster size to ensure
  agreement in the presence of up to *f* Byzantine processes.
  """

  use GenServer
  require Logger
  alias MapSet

  ## ========== CLIENT API ==========

  @doc """
  Starts the Broadcast GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts ++ [name: __MODULE__])
  end

  @doc """
  Broadcast a zero-arity function that performs the delivery side-effect.
  """
  def broadcast(deliver_callback) when is_function(deliver_callback, 0) do
    GenServer.cast(__MODULE__, {:broadcast, deliver_callback})
  end

  ## ========== SERVER CALLBACKS ==========

  @impl true
  def init(:ok) do
    Logger.info("Starting DistDb.Broadcast on node #{Node.self()}")
    {:ok, %{messages: %{}}}
  end

  @impl true
  def handle_cast({:broadcast, deliver_callback}, state) do
    msg_id = {Node.self(), :erlang.unique_integer([:monotonic, :positive])}
    msg = %{id: msg_id, deliver: deliver_callback}

    Logger.debug("Bracha SEND for #{inspect(msg_id)} from #{Node.self()}")

    broadcast_including_self(:send, msg)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:protocol, :send, msg, from}, state) do
    {new_state, _entry} = handle_send(state, msg, from)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:protocol, :echo, msg, from}, state) do
    {new_state, _entry} = handle_echo(state, msg, from)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:protocol, :ready, msg, from}, state) do
    {new_state, _entry} = handle_ready(state, msg, from)
    {:noreply, new_state}
  end

  ## ========== INTERNAL HELPERS ==========

  defp handle_send(state, msg, from) do
    {state, entry} = get_message_state(state, msg)

    if entry.seen_send do
      Logger.debug("Ignoring duplicate SEND for #{inspect(msg.id)} from #{from}")
      {state, entry}
    else
      Logger.debug("Processing SEND for #{inspect(msg.id)} from #{from}")

      entry = %{entry | seen_send: true}
      {state, entry} = put_message_state(state, msg.id, entry)

      maybe_send_echo(state, msg, entry)
    end
  end

  defp handle_echo(state, msg, from) do
    {state, entry} = get_message_state(state, msg)

    if MapSet.member?(entry.echo_from, from) do
      Logger.debug("Duplicate ECHO from #{from} for #{inspect(msg.id)}")
      {state, entry}
    else
      Logger.debug("Recording ECHO from #{from} for #{inspect(msg.id)}")

      entry = %{entry | echo_from: MapSet.put(entry.echo_from, from)}
      {state, entry} = put_message_state(state, msg.id, entry)

      thresholds = thresholds()

      maybe_send_ready(state, msg, entry, thresholds)
    end
  end

  defp handle_ready(state, msg, from) do
    {state, entry} = get_message_state(state, msg)

    if MapSet.member?(entry.ready_from, from) do
      Logger.debug("Duplicate READY from #{from} for #{inspect(msg.id)}")
      {state, entry}
    else
      Logger.debug("Recording READY from #{from} for #{inspect(msg.id)}")

      entry = %{entry | ready_from: MapSet.put(entry.ready_from, from)}
      {state, entry} = put_message_state(state, msg.id, entry)

      thresholds = thresholds()

      {state, entry} = maybe_send_ready(state, msg, entry, thresholds)
      maybe_deliver(state, msg, entry, thresholds)
    end
  end

  defp maybe_send_echo(state, msg, entry) do
    if entry.sent_echo do
      {state, entry}
    else
      Logger.debug("Broadcasting ECHO for #{inspect(msg.id)}")
      broadcast_including_self(:echo, msg)

      entry = %{entry | sent_echo: true}
      put_message_state(state, msg.id, entry)
    end
  end

  defp maybe_send_ready(state, msg, entry, thresholds) do
    ready_threshold_met? =
      MapSet.size(entry.echo_from) >= thresholds.echo or
        MapSet.size(entry.ready_from) >= thresholds.ready

    cond do
      entry.sent_ready ->
        {state, entry}

      ready_threshold_met? ->
        Logger.debug("Broadcasting READY for #{inspect(msg.id)}")
        broadcast_including_self(:ready, msg)
        entry = %{entry | sent_ready: true}
        put_message_state(state, msg.id, entry)

      true ->
        {state, entry}
    end
  end

  defp maybe_deliver(state, msg, entry, thresholds) do
    if entry.delivered do
      {state, entry}
    else
      if MapSet.size(entry.ready_from) >= thresholds.deliver do
        Logger.debug("Delivering #{inspect(msg.id)}")
        safe_deliver(entry.deliver)

        entry = %{entry | delivered: true}
        put_message_state(state, msg.id, entry)
      else
        {state, entry}
      end
    end
  end

  defp safe_deliver(nil), do: :ok

  defp safe_deliver(callback) when is_function(callback, 0) do
    try do
      callback.()
    rescue
      exception ->
        Logger.error("Delivery callback failed: #{inspect(exception)}")
        reraise(exception, __STACKTRACE__)
    end
  end

  defp broadcast_including_self(type, msg) do
    nodes = [Node.self() | Node.list()]

    Enum.each(nodes, fn node ->
      GenServer.cast({__MODULE__, node}, {:protocol, type, msg, Node.self()})
    end)
  end

  defp thresholds do
    (length(Node.list()) + 1)
    |> DistDb.Broadcast.Thresholds.for_node_count()
  end

  defp get_message_state(state, msg) do
    {entry, messages} =
      Map.get_and_update(state.messages, msg.id, fn current ->
        base_entry =
          current
          |> set_deliver_callback(msg.deliver)
          |> init_message_state(msg)

        {base_entry, base_entry}
      end)

    {%{state | messages: messages}, entry}
  end

  defp put_message_state(state, msg_id, entry) do
    {%{state | messages: Map.put(state.messages, msg_id, entry)}, entry}
  end

  defp set_deliver_callback(nil, deliver_callback),
    do: set_deliver_callback(%{}, deliver_callback)

  defp set_deliver_callback(entry, deliver_callback) do
    cond do
      Map.get(entry, :deliver) -> entry
      deliver_callback -> Map.put(entry, :deliver, deliver_callback)
      true -> entry
    end
  end

  defp init_message_state(entry, msg) do
    entry = entry || %{}
    deliver = Map.get(entry, :deliver) || Map.get(msg, :deliver)

    %{
      deliver: deliver,
      seen_send: Map.get(entry, :seen_send, false),
      sent_echo: Map.get(entry, :sent_echo, false),
      sent_ready: Map.get(entry, :sent_ready, false),
      delivered: Map.get(entry, :delivered, false),
      echo_from: Map.get(entry, :echo_from, MapSet.new()),
      ready_from: Map.get(entry, :ready_from, MapSet.new())
    }
  end
end
