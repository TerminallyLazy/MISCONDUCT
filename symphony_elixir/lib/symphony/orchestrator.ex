defmodule Symphony.Orchestrator do
  use GenServer
  alias Symphony.{Run, Prompt}
  alias Symphony.Orchestrator.State
  alias Symphony.Workspace.Manager

  @judge_verdict_relative_path ".symphony/judge-verdict.json"

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def snapshot(server \\ __MODULE__), do: GenServer.call(server, :snapshot)

  def enqueue_issue(issue, attempt \\ nil, server \\ __MODULE__),
    do: GenServer.call(server, {:enqueue_issue, issue, attempt}, 30_000)

  def reload_config(config, server \\ __MODULE__),
    do: GenServer.call(server, {:reload_config, config}, 30_000)

  def refresh(server \\ __MODULE__), do: GenServer.cast(server, :tick)
  def cancel(issue_id, server \\ __MODULE__), do: GenServer.call(server, {:cancel, issue_id})

  @impl true
  def init(opts) do
    c = Keyword.fetch!(opts, :config)
    provider_status = Symphony.Orchestration.Providers.status(c)

    state = %State{
      config: c,
      poll_interval_ms: c.poll_interval_ms,
      max_concurrent_agents: c.max_concurrent_agents
    }

    publish_event(state, "provider.selected", %{
      status: provider_status.status,
      stage: "orchestration",
      message: "#{provider_label(provider_status.active_provider)} provider selected.",
      data: %{
        active_provider: provider_status.active_provider,
        provider_contract: ["direct_codex", "agent_zero"],
        default_provider: "direct_codex"
      }
    })

    {:ok, schedule_poll(state)}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, to_snapshot(state), state}

  def handle_call({:reload_config, config}, _from, state) do
    if map_size(state.running) > 0 do
      {:reply,
       {:error, :active_runs, "Workflow reload is blocked while agent runs are active.",
        %{running: map_size(state.running)}}, state}
    else
      if state.poll_timer_ref, do: Process.cancel_timer(state.poll_timer_ref)

      next =
        %{
          state
          | config: config,
            poll_interval_ms: config.poll_interval_ms,
            max_concurrent_agents: config.max_concurrent_agents,
            poll_timer_ref: nil,
            last_poll_error: nil
        }

      publish_event(next, "workflow.reload.completed", %{
        stage: "workflow",
        status: "completed",
        message: "Runtime workflow configuration reloaded.",
        data: %{
          workflow_path: config.workflow_path,
          workspace_root: config.workspace_root,
          poll_interval_ms: config.poll_interval_ms,
          max_concurrent_agents: config.max_concurrent_agents
        }
      })

      scheduled = schedule_poll(next)
      {:reply, {:ok, to_snapshot(scheduled)}, scheduled}
    end
  end

  def handle_call({:enqueue_issue, issue, attempt}, _from, state),
    do: dispatch(issue, attempt, state)

  def handle_call({:cancel, id}, _from, state) do
    if e = state.running[id], do: Process.exit(e.pid, :kill)
    {:reply, :ok, release(state, id)}
  end

  @impl true
  def handle_cast(:tick, state) do
    publish_event(state, "tracker.poll.requested", %{
      stage: "intake",
      status: "queued",
      message: "Intake cue requested."
    })

    {:noreply, run_intake(state)}
  end

  @impl true
  def handle_info(:poll_tick, state) do
    publish_event(state, "tracker.poll.scheduled", %{
      stage: "intake",
      status: "queued",
      message: "Scheduled intake started."
    })

    {:noreply, state |> run_intake() |> schedule_poll()}
  end

  @impl true
  def handle_info({:agent_event, id, event}, state) do
    now = DateTime.utc_now()
    publish_agent_event(state, id, event)

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

  defp run_intake(state) do
    case Symphony.Config.tracker_kind(state.config) do
      "linear" ->
        poll_linear(state)

      kind when kind in ["none", "manual", "local"] ->
        skip_tracker_poll(state, kind)

      kind ->
        skip_tracker_poll(state, kind, {:unsupported_tracker_kind, kind})
    end
  end

  defp poll_linear(state) do
    now = DateTime.utc_now()
    client = Application.get_env(:symphony_elixir, :linear_client, Symphony.Linear.GraphQLClient)

    case Symphony.Config.tracker_poll_errors(state.config) do
      [] ->
        publish_event(state, "tracker.poll.started", %{
          stage: "intake",
          status: "running",
          message: "Fetching candidate issues.",
          data: %{
            tracker_kind: state.config.tracker_kind,
            project_slug: state.config.tracker_project_slug
          }
        })

        fetch_tracker_candidates(client, state, now)

      errors ->
        skip_tracker_poll(state, "linear", errors)
    end
  end

  defp fetch_tracker_candidates(client, state, now) do
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

        publish_event(state, "tracker.poll.completed", %{
          stage: "intake",
          status: "completed",
          message: "Poll completed.",
          data: %{candidate_count: length(issues), accepted_count: accepted}
        })

        %{state | last_poll_at: now, last_poll_count: accepted, last_poll_error: nil}

      {:error, reason} ->
        publish_event(state, "tracker.poll.failed", %{
          stage: "intake",
          status: "failed",
          message: inspect(reason)
        })

        %{state | last_poll_at: now, last_poll_count: 0, last_poll_error: inspect(reason)}
    end
  end

  defp skip_tracker_poll(state, kind, reason \\ nil) do
    now = DateTime.utc_now()
    message = tracker_skip_message(kind, reason)

    publish_event(state, "tracker.poll.skipped", %{
      stage: "intake",
      status: "skipped",
      message: message,
      data: %{
        tracker_kind: kind,
        reason: tracker_skip_reason(reason),
        manual_intake_available: true
      }
    })

    %{state | last_poll_at: now, last_poll_count: 0, last_poll_error: nil}
  end

  defp tracker_skip_message(kind, nil) when kind in ["none", "manual", "local"],
    do: "No external tracker is required; waiting for a conductor movement."

  defp tracker_skip_message("linear", reasons) when is_list(reasons),
    do:
      "Linear intake is not configured (#{Enum.map_join(reasons, ", ", &inspect/1)}); manual movements remain available."

  defp tracker_skip_message(kind, reason),
    do: "Tracker #{kind} intake skipped: #{inspect(reason)}"

  defp tracker_skip_reason(nil), do: nil
  defp tracker_skip_reason(reasons) when is_list(reasons), do: Enum.map(reasons, &inspect/1)
  defp tracker_skip_reason(reason), do: inspect(reason)

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
        publish_issue_event(state, "issue.dispatch.skipped", issue, %{
          stage: "intake",
          status: "already_claimed",
          message: "Issue is already claimed."
        })

        {{:error, :already_claimed}, state}

      map_size(state.running) >= state.max_concurrent_agents ->
        publish_issue_event(state, "issue.dispatch.deferred", issue, %{
          stage: "intake",
          status: "deferred",
          message: "No available orchestrator slots."
        })

        {{:error, :no_available_orchestrator_slots},
         retry_issue(state, issue, attempt, "no available orchestrator slots")}

      true ->
        do_dispatch_result(issue, attempt, state)
    end
  end

  defp do_dispatch_result(issue, attempt, state) do
    with {:ok, provider} <- Symphony.Orchestration.Providers.execution_ready(state.config),
         {:ok, agent_profile} <- assigned_agent_profile(state.config, "builder"),
         {:ok, ws} <- Manager.create_for_issue(issue.identifier, state.config),
         :ok <-
           Symphony.Hooks.Executor.run(
             get_in(state.config.hooks, ["before_run"]),
             ws.path,
             state.config.hook_timeout_ms
           ),
         {:ok, prompt} <-
           Prompt.render(blank_prompt(state.config.workflow.prompt_template), issue, attempt, %{
             agent: agent_profile || %{}
           }) do
      run = %Run{
        issue_id: issue.id,
        issue_identifier: issue.identifier,
        issue: issue,
        phase: "build",
        agent_profile: agent_profile,
        attempt: attempt,
        workspace_path: ws.path,
        status: :running,
        started_at: DateTime.utc_now(),
        last_message: String.slice(prompt, 0, 160),
        prompt: prompt
      }

      parent = self()
      runner = provider.runner

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

      publish_issue_event(ns, "issue.stage.started", issue, %{
        stage: "build",
        status: "running",
        message: "#{provider.label} run started.",
        data: %{
          provider: provider.id,
          workspace_path: ws.path,
          attempt: attempt,
          phase: "build",
          agent_profile: agent_profile
        }
      })

      {{:ok, run}, ns}
    else
      {:error, reason, message} ->
        publish_issue_event(state, "issue.dispatch.blocked", issue, %{
          stage: "orchestration",
          status: "blocked",
          message: message,
          data: %{
            reason: reason,
            provider: Symphony.Orchestration.Providers.active_provider(state.config)
          }
        })

        {{:error, reason}, state}

      {:error, r} ->
        publish_issue_event(state, "issue.dispatch.failed", issue, %{
          stage: "intake",
          status: "failed",
          message: inspect(r)
        })

        {{:error, r}, retry_issue(state, issue, attempt, inspect(r))}
    end
  end

  defp finish(state, id, :normal) do
    case state.running[id] do
      %{run: %{phase: "build"}} ->
        finish_build_success(state, id)

      %{run: %{phase: "judge"}} ->
        finish_judge_success(state, id)

      %{run: %{phase: "refiner"}} ->
        finish_refiner_success(state, id)

      _ ->
        complete_run(state, id)
    end
  end

  defp finish(state, id, reason) do
    phase = current_phase(state, id)

    publish_run_event(state, id, "issue.execution.failed", %{
      stage: phase,
      status: "failed",
      message: inspect(reason)
    })

    state |> add_runtime(id) |> retry_id(id, inspect(reason))
  end

  defp finish_build_success(state, id) do
    if phase_configured?(state.config, "judge") do
      state = add_runtime(state, id)

      case start_followup_phase(state, id, "judge") do
        {:ok, next} ->
          next

        {:error, reason, message} ->
          block_followup_start(state, id, "judge", reason, message)
      end
    else
      complete_run(state, id)
    end
  end

  defp finish_refiner_success(state, id) do
    state = add_runtime(state, id)

    publish_run_event(state, id, "issue.stage.completed", %{
      stage: "refiner",
      status: "completed",
      message: "Refiner run completed."
    })

    case start_followup_phase(state, id, "judge") do
      {:ok, next} ->
        next

      {:error, reason, message} ->
        block_followup_start(state, id, "judge", reason, message)
    end
  end

  defp finish_judge_success(state, id) do
    case state.running[id] do
      nil ->
        complete_run(state, id)

      %{run: run} ->
        case read_judge_verdict(run) do
          {:ok, verdict} ->
            state = put_run_verdict(state, id, verdict)
            publish_judge_verdict(state, id, verdict)
            apply_judge_verdict(state, id, verdict)

          {:error, reason, message, data} ->
            block_verdict(state, id, "judge", reason, message, data)
        end
    end
  end

  defp apply_judge_verdict(state, id, %{action: :pass} = _verdict), do: complete_run(state, id)

  defp apply_judge_verdict(state, id, %{action: :needs_refinement} = verdict) do
    case state.running[id] do
      nil ->
        block_verdict(state, id, "refiner", :run_missing, "Run #{id} is not active.", %{
          verdict: verdict[:verdict]
        })

      %{run: run} ->
        max_attempts = refiner_max_attempts(state.config)
        current_attempt = run.refiner_attempt || 0

        if current_attempt >= max_attempts do
          block_verdict(
            state,
            id,
            "refiner",
            :refiner_attempts_exhausted,
            "Refiner max attempts exhausted (#{current_attempt}/#{max_attempts}).",
            %{
              verdict: verdict[:verdict],
              verdict_path: verdict[:path],
              refiner_attempt: current_attempt,
              refiner_max_attempts: max_attempts
            }
          )
        else
          state = add_runtime(state, id)

          context = %{
            judge_verdict: public_verdict(verdict),
            refiner_attempt: current_attempt + 1,
            refiner_max_attempts: max_attempts
          }

          case start_followup_phase(state, id, "refiner", context) do
            {:ok, next} ->
              next

            {:error, reason, message} ->
              block_followup_start(state, id, "refiner", reason, message, %{
                verdict: verdict[:verdict],
                verdict_path: verdict[:path],
                refiner_attempt: current_attempt,
                refiner_max_attempts: max_attempts
              })
          end
        end
    end
  end

  defp apply_judge_verdict(state, id, %{action: :blocked} = verdict) do
    block_verdict(state, id, "judge", :judge_rejected, "Judge verdict blocked completion.", %{
      verdict: verdict[:verdict],
      verdict_path: verdict[:path],
      summary: verdict[:summary]
    })
  end

  defp complete_run(state, id) do
    phase = current_phase(state, id)

    publish_run_event(state, id, "issue.execution.completed", %{
      stage: phase,
      status: "completed",
      message: "#{phase_label(phase)} run completed."
    })

    state |> add_runtime(id) |> complete(id)
  end

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
      %{
        state
        | running: Map.delete(state.running, id),
          claimed: MapSet.put(state.claimed, id),
          completed: MapSet.put(state.completed, id),
          completed_runs: completed_runs(state, id)
      }

  defp retry_id(state, id, error, metadata \\ %{}) do
    {issue, attempt, run_metadata} =
      case state.running[id] do
        %{run: run} ->
          {%{
             id: run.issue_id || id,
             identifier: run.issue_identifier || run.issue_id || id
           }, run.attempt || 0,
           %{
             phase: run.phase,
             agent_profile: run.agent_profile,
             judge_verdict: run.judge_verdict,
             refiner_attempt: run.refiner_attempt,
             refiner_max_attempts: run.refiner_max_attempts
           }}

        _ ->
          {%{id: id, identifier: id}, 0, %{}}
      end

    retry_issue(release(state, id), issue, attempt, error, Map.merge(run_metadata, metadata))
  end

  defp retry_issue(state, issue, attempt, error, metadata \\ %{}) do
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
      error: error,
      phase: metadata[:phase],
      agent_profile: metadata[:agent_profile],
      judge_verdict: metadata[:judge_verdict],
      verdict: metadata[:verdict],
      verdict_path: metadata[:verdict_path],
      reason: metadata[:reason],
      refiner_attempt: metadata[:refiner_attempt],
      refiner_max_attempts: metadata[:refiner_max_attempts]
    }

    if error != "continuation" do
      publish_issue_event(state, "issue.retry.scheduled", issue, %{
        stage: "retry",
        status: "retrying",
        message: error,
        data: Map.merge(%{attempt: next, due_at: retry.due_at}, metadata)
      })
    end

    %{
      state
      | retry_attempts: Map.put(state.retry_attempts, issue.id, retry),
        claimed: MapSet.put(state.claimed, issue.id)
    }
  end

  defp blank_prompt(""), do: "You are working on a Symphony movement."
  defp blank_prompt(nil), do: "You are working on a Symphony movement."
  defp blank_prompt(p), do: p

  defp start_followup_phase(state, id, phase, context \\ %{}) do
    case state.running[id] do
      nil ->
        {:error, :run_missing, "Run #{id} is not active."}

      entry ->
        with {:ok, provider} <- Symphony.Orchestration.Providers.execution_ready(state.config),
             {:ok, agent_profile} <- assigned_agent_profile(state.config, phase),
             {:ok, agent_profile} <- require_agent_profile(agent_profile, phase),
             {:ok, prompt} <-
               followup_prompt(state.config, entry.run, phase, agent_profile, context) do
          %Run{} = previous_run = entry.run

          run = %{
            previous_run
            | phase: phase,
              agent_profile: agent_profile,
              status: :running,
              started_at: DateTime.utc_now(),
              last_event_at: nil,
              last_event: nil,
              last_message: String.slice(prompt, 0, 160),
              session_id: nil,
              turn_count: 0,
              tokens: zero_tokens(),
              events: [],
              prompt: prompt,
              refiner_attempt:
                Map.get(context, :refiner_attempt, previous_run.refiner_attempt || 0),
              refiner_max_attempts:
                Map.get(context, :refiner_max_attempts, previous_run.refiner_max_attempts),
              judge_verdict: Map.get(context, :judge_verdict, previous_run.judge_verdict)
          }

          with :ok <- prepare_phase_artifacts(run) do
            parent = self()
            runner = provider.runner
            workspace = %Symphony.Workspace{path: run.workspace_path}

            task =
              Task.Supervisor.async_nolink(Symphony.AgentSupervisor, fn ->
                runner.run(run, workspace, state.config, parent)
              end)

            next_entry = %{
              entry
              | run: run,
                pid: task.pid,
                ref: task.ref,
                started_at: DateTime.utc_now()
            }

            next = %{
              state
              | running: Map.put(state.running, id, next_entry),
                worker_refs: Map.put(state.worker_refs, task.ref, id)
            }

            publish_issue_event(next, "issue.stage.started", run.issue, %{
              stage: phase,
              status: phase_status(phase),
              message: "#{provider.label} #{phase_label(phase)} run started.",
              data: %{
                provider: provider.id,
                workspace_path: run.workspace_path,
                attempt: run.attempt,
                phase: phase,
                agent_profile: agent_profile,
                refiner_attempt: run.refiner_attempt,
                refiner_max_attempts: run.refiner_max_attempts,
                judge_verdict: run.judge_verdict,
                verdict_path: if(phase == "judge", do: judge_verdict_path(run), else: nil)
              }
            })

            {:ok, next}
          else
            {:error, reason} -> {:error, :phase_artifact_prepare_failed, inspect(reason)}
          end
        else
          {:error, reason, message} -> {:error, reason, message}
          {:error, reason} -> {:error, reason, inspect(reason)}
        end
    end
  end

  defp require_agent_profile(nil, role),
    do: {:error, :agent_profile_missing, "Workflow #{role} profile is not configured."}

  defp require_agent_profile(profile, _role), do: {:ok, profile}

  defp followup_prompt(config, build_run, "judge", agent_profile, _context) do
    judge_config = workflow_role_config(config, "judge")
    rubric = map_get(judge_config, "rubric", [])
    threshold = map_get(judge_config, "pass_threshold", nil)
    instructions = map_get(judge_config, "instructions", nil)
    verdict_path = judge_verdict_path(build_run)

    {:ok,
     [
       "You are #{agent_name(agent_profile)}, the Judge agent for Symphony.",
       "Inspect the real workspace and judge the Builder output before completion.",
       "",
       "Issue identifier: #{build_run.issue_identifier || build_run.issue_id}",
       "Issue title: #{issue_title(build_run.issue)}",
       "Workspace path: #{build_run.workspace_path}",
       "Builder profile: #{agent_name(build_run.agent_profile)}",
       "Builder last event: #{build_run.last_event || "not reported"}",
       "Builder last message: #{build_run.last_message || "not reported"}",
       "",
       "Required verdict artifact:",
       "Write a JSON file to #{verdict_path}.",
       "The orchestrator will read this file after your process exits; process success alone is not approval.",
       "Use real workspace evidence, changed files, and command output. Do not invent test output or use demo data.",
       "",
       "Verdict JSON contract:",
       ~s({"verdict":"pass | approved | needs_refinement | refine | blocked | fail | failed","summary":"short evidence-backed summary","findings":[{"severity":"blocking | warning | info","message":"finding","evidence":"workspace file, diff, or command evidence"}],"evidence":["commands, files, or observations used"],"recommended_next_action":"complete | refine | block"}),
       "",
       "Rubric:",
       format_rubric(rubric),
       pass_threshold_line(threshold),
       instructions_line("Judge", instructions),
       "",
       "Write only the verdict artifact for machine approval. You may also report a concise human summary."
     ]
     |> Enum.reject(&(&1 == nil))
     |> Enum.join("\n")}
  end

  defp followup_prompt(config, run, "refiner", agent_profile, context) do
    refiner_config = workflow_role_config(config, "refiner")
    strategy = map_get(refiner_config, "strategy", "fix_judge_findings")
    instructions = map_get(refiner_config, "instructions", nil)
    verdict = stringify(context[:judge_verdict] || run.judge_verdict || %{})

    {:ok,
     [
       "You are #{agent_name(agent_profile)}, the Refiner agent for Symphony.",
       "Address the Judge findings using the same issue workspace. Keep the scope bounded to the requested issue and Judge findings.",
       "",
       "Issue identifier: #{run.issue_identifier || run.issue_id}",
       "Issue title: #{issue_title(run.issue)}",
       "Workspace path: #{run.workspace_path}",
       "Refiner attempt: #{context[:refiner_attempt] || run.refiner_attempt || 0}/#{context[:refiner_max_attempts] || refiner_max_attempts(config)}",
       "Strategy: #{strategy}",
       instructions_line("Refiner", instructions),
       "",
       "Judge verdict artifact: #{map_get(verdict, "path", judge_verdict_path(run))}",
       "Judge verdict: #{map_get(verdict, "verdict", "needs_refinement")}",
       "Judge summary: #{map_get(verdict, "summary", "not reported")}",
       "",
       "Judge findings:",
       format_findings(map_get(verdict, "findings", [])),
       "",
       "Use only real workspace evidence and commands. Do not invent test output, broaden the issue, or mark the issue complete.",
       "When your refinement is done, stop. Symphony will run the Judge again."
     ]
     |> Enum.reject(&(&1 == nil))
     |> Enum.join("\n")}
  end

  defp followup_prompt(_config, _run, phase, _agent_profile, _context),
    do: {:error, :unsupported_phase, "Unsupported follow-up phase: #{phase}"}

  defp block_followup_start(state, id, phase, reason, message, data \\ %{}) do
    data = Map.merge(%{reason: reason, phase: phase}, data)

    publish_run_event(state, id, "issue.stage.blocked", %{
      stage: phase,
      status: "blocked",
      message: message,
      data: data
    })

    retry_id(state, id, message, data)
  end

  defp block_verdict(state, id, phase, reason, message, data) do
    data = Map.merge(%{reason: reason, phase: phase}, data)

    publish_run_event(state, id, "issue.stage.blocked", %{
      stage: phase,
      status: "blocked",
      message: message,
      data: data
    })

    state |> add_runtime(id) |> retry_id(id, message, data)
  end

  defp publish_judge_verdict(state, id, verdict) do
    status =
      case verdict[:action] do
        :pass -> "approved"
        :needs_refinement -> "needs_refinement"
        :blocked -> "blocked"
      end

    publish_run_event(state, id, "issue.judge.verdict", %{
      stage: "judge",
      status: status,
      message: judge_verdict_message(verdict),
      data: public_verdict(verdict)
    })
  end

  defp judge_verdict_message(%{summary: summary}) when is_binary(summary) and summary != "",
    do: summary

  defp judge_verdict_message(verdict), do: "Judge verdict: #{verdict[:verdict]}"

  defp put_run_verdict(state, id, verdict) do
    case state.running[id] do
      nil ->
        state

      entry ->
        run = %{entry.run | judge_verdict: public_verdict(verdict)}
        put_in(state.running[id], %{entry | run: run})
    end
  end

  defp public_verdict(verdict) do
    %{
      verdict: verdict[:verdict],
      action: verdict[:action] && to_string(verdict[:action]),
      summary: verdict[:summary],
      findings: verdict[:findings],
      evidence: verdict[:evidence],
      recommended_next_action: verdict[:recommended_next_action],
      path: verdict[:path]
    }
  end

  defp read_judge_verdict(run) do
    path = judge_verdict_path(run)

    with {:read, {:ok, body}} <- {:read, File.read(path)},
         {:decode, {:ok, decoded}} <- {:decode, Jason.decode(body)},
         {:map, true} <- {:map, is_map(decoded)},
         {:verdict, {:ok, verdict}} <- {:verdict, normalize_judge_verdict(decoded)} do
      {:ok, Map.put(verdict, :path, path)}
    else
      {:read, {:error, :enoent}} ->
        {:error, :missing_judge_verdict, "Judge verdict artifact is missing: #{path}",
         %{verdict_path: path}}

      {:read, {:error, reason}} ->
        {:error, :judge_verdict_read_failed,
         "Judge verdict artifact could not be read: #{inspect(reason)}", %{verdict_path: path}}

      {:decode, {:error, reason}} ->
        {:error, :invalid_judge_verdict,
         "Judge verdict artifact is not valid JSON: #{Exception.message(reason)}",
         %{verdict_path: path}}

      {:map, false} ->
        {:error, :invalid_judge_verdict, "Judge verdict artifact must be a JSON object.",
         %{verdict_path: path}}

      {:verdict, {:error, reason, message}} ->
        {:error, reason, message, %{verdict_path: path}}
    end
  end

  defp normalize_judge_verdict(decoded) do
    raw_verdict = map_get(decoded, "verdict", map_get(decoded, "status", nil))

    with {:ok, action, verdict} <- normalize_judge_verdict_value(raw_verdict),
         {:ok, normalized} <-
           validate_judge_verdict(%{
             action: action,
             verdict: verdict,
             summary: string_or_nil(map_get(decoded, "summary", nil)),
             findings: normalize_findings(map_get(decoded, "findings", [])),
             evidence: normalize_evidence(map_get(decoded, "evidence", [])),
             recommended_next_action:
               string_or_nil(map_get(decoded, "recommended_next_action", nil))
           }) do
      {:ok, normalized}
    else
      {:error, reason, message} -> {:error, reason, message}
    end
  end

  defp validate_judge_verdict(%{summary: summary}) when not is_binary(summary),
    do: {:error, :invalid_judge_verdict, "Judge verdict summary is required."}

  defp validate_judge_verdict(verdict) do
    cond do
      String.trim(verdict.summary) == "" ->
        {:error, :invalid_judge_verdict, "Judge verdict summary is required."}

      verdict.evidence == [] ->
        {:error, :invalid_judge_verdict, "Judge verdict evidence is required."}

      verdict.action in [:needs_refinement, :blocked] and verdict.findings == [] ->
        {:error, :invalid_judge_verdict,
         "Judge verdict findings are required for #{verdict.verdict}."}

      true ->
        {:ok, verdict}
    end
  end

  defp normalize_judge_verdict_value(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[\s-]+/, "_")

    case normalized do
      "" ->
        {:error, :invalid_judge_verdict, "Judge verdict is missing or blank."}

      "pass" ->
        {:ok, :pass, "pass"}

      "approved" ->
        {:ok, :pass, "approved"}

      "needs_refinement" ->
        {:ok, :needs_refinement, "needs_refinement"}

      "refine" ->
        {:ok, :needs_refinement, "refine"}

      "blocked" ->
        {:ok, :blocked, "blocked"}

      "fail" ->
        {:ok, :blocked, "fail"}

      "failed" ->
        {:ok, :blocked, "failed"}

      other ->
        {:error, :invalid_judge_verdict, "Judge verdict #{inspect(other)} is not supported."}
    end
  end

  defp normalize_judge_verdict_value(_value),
    do: {:error, :invalid_judge_verdict, "Judge verdict must be a string."}

  defp normalize_findings(value) do
    value
    |> list_items()
    |> Enum.map(fn
      finding when is_map(finding) ->
        finding |> stringify() |> Map.take(["severity", "message", "evidence", "file", "command"])

      finding ->
        %{"message" => to_string(finding)}
    end)
  end

  defp normalize_evidence(value),
    do:
      value
      |> list_items()
      |> Enum.map(&evidence_item/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

  defp evidence_item(value) when is_binary(value), do: value
  defp evidence_item(value), do: inspect(value)

  defp list_items(value) when is_list(value), do: value
  defp list_items(value) when is_binary(value), do: [value]
  defp list_items(_), do: []

  defp string_or_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp string_or_nil(nil), do: nil
  defp string_or_nil(value), do: to_string(value)

  defp prepare_phase_artifacts(%{phase: "judge"} = run) do
    path = judge_verdict_path(run)

    with :ok <- File.mkdir_p(Path.dirname(path)) do
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, {:verdict_cleanup_failed, reason}}
      end
    end
  end

  defp prepare_phase_artifacts(_run), do: :ok

  defp judge_verdict_path(%{workspace_path: workspace_path}) do
    Path.join(workspace_path || ".", @judge_verdict_relative_path)
  end

  defp refiner_max_attempts(config) do
    config
    |> workflow_role_config("refiner")
    |> map_get("max_attempts", 1)
    |> non_negative_int(1)
  end

  defp non_negative_int(value, _default) when is_integer(value), do: max(value, 0)

  defp non_negative_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> max(int, 0)
      _ -> default
    end
  end

  defp non_negative_int(_value, default), do: default

  defp format_findings(findings) do
    findings = normalize_findings(findings)

    case findings do
      [] ->
        "- No specific Judge findings were reported."

      items ->
        Enum.map_join(items, "\n", fn finding ->
          severity = map_get(finding, "severity", "finding")
          message = map_get(finding, "message", inspect(finding))
          evidence = map_get(finding, "evidence", nil)

          case string_or_nil(evidence) do
            nil -> "- #{severity}: #{message}"
            evidence -> "- #{severity}: #{message} Evidence: #{evidence}"
          end
        end)
    end
  end

  defp provider_label("agent_zero"), do: "Agent Zero"
  defp provider_label("direct_codex"), do: "Direct Codex Agents"
  defp provider_label(provider), do: to_string(provider)

  defp assigned_agent_profile(config, role) do
    profile_id = workflow_profile_id(config, role)

    cond do
      not present?(profile_id) ->
        {:ok, nil}

      true ->
        case registry_profile(profile_id) do
          {:ok, profile} ->
            profile = public_agent_profile(profile)

            if profile.enabled do
              {:ok, profile}
            else
              {:error, :agent_profile_disabled,
               "Workflow #{role} profile #{profile_id} is disabled."}
            end

          {:error, _} ->
            case workflow_stage_agent_profile(config, profile_id, role) do
              nil ->
                {:error, :agent_profile_missing,
                 "Workflow #{role} profile #{profile_id} is not configured."}

              profile ->
                if profile.enabled do
                  {:ok, profile}
                else
                  {:error, :agent_profile_disabled,
                   "Workflow #{role} profile #{profile_id} is disabled."}
                end
            end
        end
    end
  end

  defp workflow_profile_id(config, role) do
    map_get(workflow_role_config(config, role), "profile", nil)
  end

  defp workflow_role_config(config, role) do
    config
    |> workflow_config()
    |> map_get(role, %{})
    |> map_or_empty()
  end

  defp phase_configured?(config, phase), do: Map.has_key?(workflow_config(config), phase)

  defp registry_profile(profile_id) do
    if Process.whereis(Symphony.AgentProfileRegistry) do
      Symphony.AgentProfileRegistry.get(profile_id)
    else
      {:error, :registry_unavailable}
    end
  catch
    :exit, _ -> {:error, :registry_unavailable}
  end

  defp workflow_stage_agent_profile(config, profile_id, role) do
    config
    |> workflow_config()
    |> map_get("stage_agents", [])
    |> Enum.find(fn raw ->
      raw = stringify(raw)
      (raw["profile"] || raw["id"] || raw["profile_key"]) == profile_id
    end)
    |> case do
      nil -> nil
      raw -> public_stage_agent_profile(raw, profile_id, role)
    end
  end

  defp public_stage_agent_profile(raw, profile_id, role) do
    raw = stringify(raw)
    music = raw["music"] |> map_or_empty() |> stringify()
    stage = (raw["stage"] || raw["stage_position"]) |> map_or_empty() |> stringify()
    section = raw["section"] || music["section"] || "Strings"
    instrument = raw["instrument_name"] || raw["instrument"] || music["instrument"] || "Violin"

    public_agent_profile(%{
      "id" => profile_id,
      "name" => raw["name"] || humanize(profile_id),
      "role" => raw["role"] || humanize(role),
      "profile_key" => raw["profile_key"] || profile_id,
      "section" => section,
      "instrument_name" => instrument,
      "enabled" => profile_enabled?(raw["enabled"]),
      "status" => raw["status"] || "idle",
      "capabilities" => list_strings(raw["capabilities"]),
      "music" =>
        Map.merge(music, %{
          "section" => section,
          "instrument" => instrument,
          "motif" => raw["motif"] || music["motif"] || ""
        }),
      "stage_position" => stage
    })
  end

  defp public_agent_profile(nil), do: nil

  defp public_agent_profile(profile) when is_map(profile) do
    profile = stringify(profile)
    enabled = profile_enabled?(profile["enabled"])

    %{
      id: profile["id"],
      name: profile["name"],
      role: profile["role"] || "Agent",
      profile_key: profile["profile_key"] || profile["id"],
      section: profile["section"] || "Strings",
      instrument_name: profile["instrument_name"] || "Violin",
      enabled: enabled,
      status: profile["status"] || if(enabled, do: "idle", else: "disabled"),
      capabilities: list_strings(profile["capabilities"]),
      music: profile["music"] |> map_or_empty() |> stringify(),
      stage_position: profile["stage_position"] |> map_or_empty() |> stringify()
    }
  end

  defp workflow_config(%{workflow: %{config: config}}) when is_map(config), do: stringify(config)
  defp workflow_config(_), do: %{}

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(value), do: value

  defp map_get(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp map_get(_, _, default), do: default
  defp map_or_empty(value) when is_map(value), do: value
  defp map_or_empty(_), do: %{}

  defp list_strings(value) when is_list(value),
    do:
      value
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

  defp list_strings(value) when is_binary(value),
    do:
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

  defp list_strings(_), do: []

  defp humanize(value),
    do:
      value
      |> to_string()
      |> String.replace(~r/[-_]+/, " ")
      |> String.split()
      |> Enum.map_join(" ", &String.capitalize/1)

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false

  defp profile_enabled?(nil), do: true
  defp profile_enabled?(false), do: false
  defp profile_enabled?(0), do: false

  defp profile_enabled?(value) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    normalized not in ["false", "0", "no", "disabled"]
  end

  defp profile_enabled?(_), do: true

  defp current_phase(state, id) do
    case state.running[id] do
      %{run: %{phase: phase}} when is_binary(phase) and phase != "" -> phase
      _ -> "build"
    end
  end

  defp phase_label("build"), do: "Builder"
  defp phase_label("judge"), do: "Judge"
  defp phase_label("refiner"), do: "Refiner"
  defp phase_label(phase), do: humanize(phase)

  defp phase_status("judge"), do: "judging"
  defp phase_status("refiner"), do: "refining"
  defp phase_status(_), do: "running"

  defp zero_tokens, do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}

  defp agent_name(nil), do: "unassigned"

  defp agent_name(profile) when is_map(profile),
    do: Map.get(profile, :name) || Map.get(profile, "name") || "agent"

  defp agent_name(value), do: to_string(value)

  defp issue_title(nil), do: "not reported"
  defp issue_title(issue), do: Map.get(issue, :title) || Map.get(issue, "title") || "not reported"

  defp format_rubric(values) when is_list(values) do
    values
    |> list_strings()
    |> case do
      [] -> "- No explicit rubric configured."
      items -> Enum.map_join(items, "\n", &"- #{&1}")
    end
  end

  defp format_rubric(value) when is_binary(value), do: format_rubric([value])
  defp format_rubric(_), do: "- No explicit rubric configured."

  defp pass_threshold_line(nil), do: nil
  defp pass_threshold_line(value), do: "Pass threshold: #{value}"

  defp instructions_line(_role, nil), do: nil
  defp instructions_line(_role, ""), do: nil
  defp instructions_line(role, value), do: "#{role} instructions: #{value}"

  defp publish_event(state, type, fields) do
    Symphony.Events.publish(
      Map.merge(
        %{
          type: type,
          provider: Symphony.Orchestration.Providers.active_provider(state.config),
          source: "orchestrator"
        },
        fields
      )
    )
  end

  defp publish_issue_event(state, type, issue, fields) do
    publish_event(
      state,
      type,
      Map.merge(
        %{
          issue_id: issue.id,
          issue_identifier: issue.identifier,
          data: %{
            issue_title: Map.get(issue, :title),
            issue_state: Map.get(issue, :state)
          }
        },
        fields
      )
    )
  end

  defp publish_run_event(state, id, type, fields) do
    case state.running[id] do
      nil ->
        publish_event(state, type, Map.put(fields, :issue_id, id))

      entry ->
        run = entry.run

        publish_event(
          state,
          type,
          Map.merge(
            %{
              issue_id: run.issue_id,
              issue_identifier: run.issue_identifier,
              data: %{
                workspace_path: run.workspace_path,
                session_id: run.session_id,
                phase: run.phase,
                agent_profile: run.agent_profile,
                refiner_attempt: run.refiner_attempt,
                refiner_max_attempts: run.refiner_max_attempts,
                judge_verdict: run.judge_verdict
              }
            },
            merge_event_data(fields, %{
              workspace_path: run.workspace_path,
              session_id: run.session_id,
              phase: run.phase,
              agent_profile: run.agent_profile,
              refiner_attempt: run.refiner_attempt,
              refiner_max_attempts: run.refiner_max_attempts,
              judge_verdict: run.judge_verdict
            })
          )
        )
    end
  end

  defp merge_event_data(fields, base_data) do
    extra = map_get(fields, :data, %{}) |> map_or_empty()
    fields |> Map.delete(:data) |> Map.put(:data, Map.merge(base_data, extra))
  end

  defp publish_agent_event(state, id, event) do
    entry = state.running[id]
    phase = if(entry, do: entry.run.phase || "build", else: "build")

    publish_event(state, "agent.event", %{
      source: "agent_runner",
      issue_id: id,
      issue_identifier: entry && entry.run.issue_identifier,
      stage: phase,
      status: event_status(event[:event]),
      action: event[:event],
      message: event[:message],
      data:
        event
        |> Map.drop([:message])
        |> Map.put(:phase, phase)
        |> Map.put(:agent_profile, entry && entry.run.agent_profile)
        |> Map.put(:refiner_attempt, entry && entry.run.refiner_attempt)
        |> Map.put(:refiner_max_attempts, entry && entry.run.refiner_max_attempts)
        |> Map.put(:judge_verdict, entry && entry.run.judge_verdict)
    })
  end

  defp event_status("turn_completed"), do: "completed"
  defp event_status("turn_failed"), do: "failed"
  defp event_status("startup_failed"), do: "failed"
  defp event_status("session_started"), do: "running"
  defp event_status(_), do: "running"

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
      completed_runs: completed_run_values(state.completed_runs),
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

  defp completed_runs(state, id) do
    case state.running[id] do
      %{run: run} ->
        run =
          %{
            run
            | status: :completed,
              last_event: run.last_event || "completed",
              last_message: run.last_message || "#{phase_label(run.phase)} run completed.",
              last_event_at: run.last_event_at || DateTime.utc_now()
          }

        state.completed_runs
        |> Map.put(id, run)
        |> trim_completed_runs()

      _ ->
        state.completed_runs
    end
  end

  defp completed_run_values(completed_runs) do
    completed_runs
    |> Map.values()
    |> Enum.sort_by(&run_sort_time/1, {:desc, DateTime})
  end

  defp trim_completed_runs(completed_runs) do
    completed_runs
    |> completed_run_values()
    |> Enum.take(20)
    |> Map.new(&{&1.issue_id, &1})
  end

  defp run_sort_time(run), do: run.last_event_at || run.started_at || ~U[1970-01-01 00:00:00Z]
end
