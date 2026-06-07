defmodule Symphony.Orchestrator do
  use GenServer
  alias Symphony.{Run, Prompt}
  alias Symphony.Orchestrator.State
  alias Symphony.Workspace.Manager

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)

  def enqueue_issue(issue, attempt \\ nil, server \\ __MODULE__),
    do: GenServer.call(server, {:enqueue_issue, issue, attempt}, 30_000)

  def refresh(server \\ __MODULE__), do: GenServer.cast(server, :tick)
  def cancel(issue_id, server \\ __MODULE__), do: GenServer.call(server, {:cancel, issue_id})

  @impl true
  def init(opts) do
    c = Keyword.fetch!(opts, :config)

    state = %State{
      config: c,
      poll_interval_ms: c.poll_interval_ms,
      max_concurrent_agents: c.max_concurrent_agents
    }

    {:ok, schedule_poll(state)}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, to_snapshot(state), state}

  def handle_call({:enqueue_issue, issue, attempt}, _from, state),
    do: dispatch(issue, attempt, state)

  def handle_call({:cancel, id}, _from, state) do
    if e = state.running[id], do: Process.exit(e.pid, :kill)
    {:reply, :ok, release(state, id)}
  end

  @impl true
  def handle_cast(:tick, state), do: {:noreply, poll_linear(state)}

  @impl true
  def handle_info(:poll_tick, state), do: {:noreply, state |> poll_linear() |> schedule_poll()}

  @impl true
  def handle_info({:agent_event, id, event}, state) do
    now = DateTime.utc_now()

    running =
      update_in(state.running, [id], fn
        nil ->
          nil

        e ->
          run = e.run
          usage = event[:usage] || %{}
          ev = event[:event]
          msg = event[:message]

          tokens = %{
            input_tokens: usage[:input_tokens] || run.tokens.input_tokens,
            output_tokens: usage[:output_tokens] || run.tokens.output_tokens,
            total_tokens: usage[:total_tokens] || run.tokens.total_tokens
          }

          sid =
            if event[:thread_id],
              do: "#{event[:thread_id]}-#{event[:turn_id]}",
              else: run.session_id

          nr = %{
            run
            | last_event: ev,
              last_message: msg,
              last_event_at: now,
              tokens: tokens,
              session_id: sid,
              turn_count:
                if(ev == "turn_completed", do: run.turn_count + 1, else: run.turn_count),
              events: [%{at: now, event: ev, message: msg} | Enum.take(run.events, 20)]
          }

          %{e | run: nr}
      end)

    {:noreply, %{state | running: running}}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    {id, refs} = Map.pop(state.worker_refs, ref)
    state = %{state | worker_refs: refs}

    if id do
      Process.demonitor(ref, [:flush])
      reason = if result == :ok, do: :normal, else: result
      {:noreply, finish(state, id, reason)}
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {id, refs} = Map.pop(state.worker_refs, ref)
    state = %{state | worker_refs: refs}
    if id, do: {:noreply, finish(state, id, reason)}, else: {:noreply, state}
  end

  defp poll_linear(state) do
    now = DateTime.utc_now()
    client = Application.get_env(:symphony_elixir, :linear_client, Symphony.Linear.GraphQLClient)

    case client.fetch_candidate_issues(state.config) do
      {:ok, issues} ->
        {state, accepted} =
          issues
          |> Enum.reduce({state, 0}, fn issue, {acc, count} ->
            case dispatch_result(issue, nil, acc) do
              {{:ok, _run}, next} -> {next, count + 1}
              {{:error, :already_claimed}, next} -> {next, count}
              {{:error, :no_available_orchestrator_slots}, next} -> {next, count}
              {{:error, _reason}, next} -> {next, count}
            end
          end)

        %{state | last_poll_at: now, last_poll_count: accepted, last_poll_error: nil}

      {:error, reason} ->
        %{state | last_poll_at: now, last_poll_count: 0, last_poll_error: inspect(reason)}
    end
  end

  defp schedule_poll(%{poll_interval_ms: ms} = state) when is_integer(ms) and ms > 0 do
    if state.poll_timer_ref, do: Process.cancel_timer(state.poll_timer_ref)
    %{state | poll_timer_ref: Process.send_after(self(), :poll_tick, ms)}
  end

  defp schedule_poll(state), do: state

  defp dispatch(issue, attempt, state) do
    {result, state} = dispatch_result(issue, attempt, state)
    {:reply, result, state}
  end

  defp dispatch_result(issue, attempt, state) do
    id = issue.id

    cond do
      Map.has_key?(state.running, id) or MapSet.member?(state.claimed, id) ->
        {{:error, :already_claimed}, state}

      map_size(state.running) >= state.max_concurrent_agents ->
        {{:error, :no_available_orchestrator_slots},
         retry_issue(state, issue, attempt, "no available orchestrator slots")}

      true ->
        do_dispatch_result(issue, attempt, state)
    end
  end

  defp do_dispatch_result(issue, attempt, state) do
    with {:ok, ws} <- Manager.create_for_issue(issue.identifier, state.config),
         :ok <-
           Symphony.Hooks.Executor.run(
             get_in(state.config.hooks, ["before_run"]),
             ws.path,
             state.config.hook_timeout_ms
           ),
         {:ok, prompt} <-
           Prompt.render(blank_prompt(state.config.workflow.prompt_template), issue, attempt) do
      run = %Run{
        issue_id: issue.id,
        issue_identifier: issue.identifier,
        issue: issue,
        attempt: attempt,
        workspace_path: ws.path,
        status: :running,
        started_at: DateTime.utc_now(),
        last_message: String.slice(prompt, 0, 160),
        prompt: prompt
      }

      parent = self()
      runner = Application.get_env(:symphony_elixir, :agent_runner, Symphony.AgentRunner.Codex)

      task =
        Task.Supervisor.async_nolink(Symphony.AgentSupervisor, fn ->
          runner.run(run, ws, state.config, parent)
        end)

      ref = task.ref

      entry = %{
        run: run,
        pid: task.pid,
        ref: ref,
        started_at: DateTime.utc_now(),
        identifier: issue.identifier
      }

      ns = %{
        state
        | running: Map.put(state.running, issue.id, entry),
          claimed: MapSet.put(state.claimed, issue.id),
          worker_refs: Map.put(state.worker_refs, ref, issue.id)
      }

      {{:ok, run}, ns}
    else
      {:error, r} -> {{:error, r}, retry_issue(state, issue, attempt, inspect(r))}
    end
  end

  defp finish(state, id, :normal), do: state |> add_runtime(id) |> complete(id)
  defp finish(state, id, reason), do: state |> add_runtime(id) |> retry_id(id, inspect(reason))

  defp add_runtime(state, id) do
    case state.running[id] do
      nil ->
        state

      e ->
        put_in(
          state.codex_totals.seconds_running,
          state.codex_totals.seconds_running +
            DateTime.diff(DateTime.utc_now(), e.started_at, :millisecond) / 1000
        )
    end
  end

  defp release(state, id),
    do: %{
      state
      | running: Map.delete(state.running, id),
        claimed: MapSet.delete(state.claimed, id)
    }

  defp complete(state, id),
    do:
      %{release(state, id) | completed: MapSet.put(state.completed, id)}
      |> retry_id(id, "continuation")

  defp retry_id(state, id, error),
    do: retry_issue(release(state, id), %{id: id, identifier: id}, 0, error)

  defp retry_issue(state, issue, attempt, error) do
    next = (attempt || 0) + 1

    delay =
      if error == "continuation",
        do: 1_000,
        else:
          min(10_000 * trunc(:math.pow(2, max(next - 1, 0))), state.config.max_retry_backoff_ms)

    retry = %{
      issue_id: issue.id,
      issue_identifier: issue.identifier,
      attempt: next,
      due_at: DateTime.add(DateTime.utc_now(), delay, :millisecond),
      error: error
    }

    %{
      state
      | retry_attempts: Map.put(state.retry_attempts, issue.id, retry),
        claimed: MapSet.put(state.claimed, issue.id)
    }
  end

  defp blank_prompt(""), do: "You are working on an issue from Linear."
  defp blank_prompt(nil), do: "You are working on an issue from Linear."
  defp blank_prompt(p), do: p

  defp to_snapshot(state) do
    %{
      generated_at: DateTime.utc_now(),
      counts: %{
        running: map_size(state.running),
        retrying: map_size(state.retry_attempts),
        completed: MapSet.size(state.completed)
      },
      running: Enum.map(state.running, fn {_id, e} -> e.run end),
      retrying: Map.values(state.retry_attempts),
      codex_totals: state.codex_totals,
      rate_limits: state.codex_rate_limits,
      polling: %{
        interval_ms: state.poll_interval_ms,
        last_poll_at: state.last_poll_at,
        last_poll_count: state.last_poll_count,
        last_poll_error: state.last_poll_error
      }
    }
  end
end
