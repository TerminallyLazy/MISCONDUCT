defmodule Symphony.Events do
  use GenServer

  @max_events 250
  @max_string 2_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def publish(event, server \\ __MODULE__) when is_map(event) do
    case event_server(server) do
      nil -> :ok
      target -> GenServer.cast(target, {:publish, event})
    end
  end

  def list(limit \\ 100, server \\ __MODULE__) when is_integer(limit),
    do: GenServer.call(server, {:list, max(limit, 0)})

  def subscribe(server \\ __MODULE__),
    do: GenServer.call(server, {:subscribe, self()})

  def unsubscribe(server \\ __MODULE__),
    do: GenServer.cast(server, {:unsubscribe, self()})

  def reset(server \\ __MODULE__), do: GenServer.call(server, :reset)

  @impl true
  def init(opts) do
    {:ok,
     %{
       events: [],
       max_events: Keyword.get(opts, :max_events, @max_events),
       sequence: 0,
       subscribers: %{}
     }}
  end

  @impl true
  def handle_call({:list, limit}, _from, state) do
    {:reply, state.events |> Enum.take(limit) |> Enum.reverse(), state}
  end

  def handle_call({:subscribe, pid}, _from, state) when is_pid(pid) do
    subscribers =
      Map.put_new_lazy(state.subscribers, pid, fn ->
        Process.monitor(pid)
      end)

    {:reply, :ok, %{state | subscribers: subscribers}}
  end

  def handle_call(:reset, _from, state),
    do: {:reply, :ok, %{state | events: [], sequence: 0}}

  @impl true
  def handle_cast({:publish, raw}, state) do
    sequence = state.sequence + 1
    event = normalize(raw, sequence)

    Enum.each(Map.keys(state.subscribers), fn pid ->
      send(pid, {:symphony_event, event})
    end)

    {:noreply,
     %{
       state
       | events: [event | Enum.take(state.events, state.max_events - 1)],
         sequence: sequence
     }}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    {ref, subscribers} = Map.pop(state.subscribers, pid)
    if ref, do: Process.demonitor(ref, [:flush])
    {:noreply, %{state | subscribers: subscribers}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    subscribers =
      case Map.fetch(state.subscribers, pid) do
        {:ok, ^ref} -> Map.delete(state.subscribers, pid)
        _ -> state.subscribers
      end

    {:noreply, %{state | subscribers: subscribers}}
  end

  defp normalize(raw, sequence) do
    now = DateTime.utc_now()

    %{
      id: value(raw, :id) || "#{DateTime.to_unix(now, :millisecond)}-#{sequence}",
      sequence: sequence,
      type: value(raw, :type, "event") |> to_string(),
      provider: value(raw, :provider, "direct_codex") |> to_string(),
      source: value(raw, :source, "misconduct") |> to_string(),
      occurred_at: now,
      issue_id: value(raw, :issue_id),
      issue_identifier: value(raw, :issue_identifier),
      stage: value(raw, :stage),
      status: value(raw, :status),
      action: value(raw, :action),
      message: value(raw, :message),
      data: raw |> value(:data, %{}) |> safe()
    }
    |> Enum.reject(fn {_key, val} -> is_nil(val) end)
    |> Map.new(fn {key, val} -> {key, safe(val)} end)
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))

  defp safe(value) when is_binary(value),
    do: value |> Symphony.Codex.Auth.redact() |> String.slice(0, @max_string)

  defp safe(value) when is_atom(value), do: to_string(value)
  defp safe(value) when is_number(value) or is_boolean(value) or is_nil(value), do: value

  defp safe(%DateTime{} = value), do: value

  defp safe(value) when is_list(value),
    do: value |> Enum.take(25) |> Enum.map(&safe/1)

  defp safe(value) when is_map(value) do
    value
    |> Enum.take(50)
    |> Map.new(fn {key, val} -> {safe_key(key), safe(val)} end)
  end

  defp safe(value), do: value |> inspect() |> String.slice(0, @max_string)

  defp safe_key(key) when is_atom(key), do: Atom.to_string(key)
  defp safe_key(key), do: to_string(key)

  defp event_server(server) when is_atom(server), do: Process.whereis(server)
  defp event_server(server), do: server
end
