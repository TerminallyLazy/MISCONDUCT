defmodule Symphony.Http.Api do
  import Plug.Conn

  alias Symphony.Http.Json

  def json(conn, status, data) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, Json.encode!(data))
  end

  def html(conn, status, body) do
    conn |> put_resp_content_type("text/html") |> send_resp(status, body)
  end

  def dashboard(conn), do: html(conn, 200, Symphony.Http.Dashboard.html())

  def health(conn) do
    json(conn, 200, %{
      ok: true,
      status: health_status(),
      service: "symphony",
      generated_at: DateTime.utc_now(),
      workflow: workflow_metadata()
    })
  end

  def state(conn) do
    snap = Symphony.Orchestrator.snapshot()

    json(
      conn,
      200,
      snap
      |> Map.put(:workflow, workflow_metadata())
      |> Map.put(:operator_status, operator_status(snap))
      |> Map.put(:operator_summary, operator_summary(snap))
    )
  end

  def kanban(conn) do
    snap = Symphony.Orchestrator.snapshot()

    json(conn, 200, %{
      generated_at: DateTime.utc_now(),
      workflow: workflow_metadata(),
      columns: [
        %{
          id: "running",
          title: "Running",
          count: length(snap.running),
          cards: Enum.map(snap.running, &run_card/1)
        },
        %{
          id: "retrying",
          title: "Retrying",
          count: length(snap.retrying),
          cards: Enum.map(snap.retrying, &retry_card/1)
        },
        %{id: "completed", title: "Completed", count: snap.counts.completed, cards: []}
      ],
      counts: snap.counts,
      codex_totals: snap.codex_totals,
      rate_limits: snap.rate_limits
    })
  end

  def events(conn) do
    json(conn, 200, %{
      generated_at: DateTime.utc_now(),
      stream: "/api/events/stream",
      events: Symphony.Events.list(100)
    })
  end

  def orchestration_providers(conn),
    do: json(conn, 200, Symphony.Orchestration.Providers.status(current_config()))

  def select_orchestration_provider(conn) do
    config = current_config()
    provider = body_value(conn, "provider") || body_value(conn, "id")

    case Symphony.Orchestration.Providers.select(provider, config) do
      {:ok, status} ->
        Symphony.Events.publish(%{
          type: "provider.selection.accepted",
          source: "http_api",
          provider: status.active_provider,
          stage: "orchestration",
          status: "ready",
          message: "#{provider_label(status.active_provider)} provider selected.",
          data: %{active_provider: status.active_provider}
        })

        json(conn, 200, status)

      {:error, reason, message, status} ->
        Symphony.Events.publish(%{
          type: "provider.selection.rejected",
          source: "http_api",
          provider: to_string(provider || ""),
          stage: "orchestration",
          status: "blocked",
          message: message,
          data: %{reason: reason, requested_provider: provider}
        })

        json(conn, 409, %{
          ok: false,
          error: %{code: to_string(reason), message: message},
          provider_status: status
        })
    end
  end

  def event_stream(conn) do
    conn =
      conn
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)

    conn =
      Symphony.Events.list(25)
      |> Enum.reduce_while(conn, fn event, acc ->
        case write_sse(acc, event) do
          {:ok, next} -> {:cont, next}
          {:error, _reason} -> {:halt, acc}
        end
      end)

    :ok = Symphony.Events.subscribe()

    try do
      stream_events(conn)
    after
      Symphony.Events.unsubscribe()
    end
  end

  def workflow(conn), do: json(conn, 200, workflow_metadata())

  def list_workflow_templates(conn),
    do: json(conn, 200, %{ok: true, templates: Symphony.Workflow.Files.templates()})

  def list_workflows(conn) do
    {:ok, payload} = Symphony.Workflow.Files.list()
    json(conn, 200, payload)
  end

  def generate_workflow(conn) do
    params = conn.body_params || %{}

    case Symphony.Workflow.Files.generate(params) do
      {:ok, payload} ->
        with {:ok, agent_payload} <- ensure_workflow_agents(params, payload) do
          json(conn, 200, Map.merge(payload, agent_payload))
        else
          {:error, reason} -> workflow_error(conn, reason)
        end

      {:error, reason} ->
        workflow_error(conn, reason)
    end
  end

  def validate_workflow(conn) do
    case Symphony.Workflow.Files.validate(conn.body_params || %{}) do
      {:ok, payload} -> json(conn, 200, payload)
      {:error, reason} -> workflow_error(conn, reason)
    end
  end

  def preview_workflow(conn) do
    case Symphony.Workflow.Files.preview(conn.body_params || %{}) do
      {:ok, payload} -> json(conn, 200, payload)
      {:error, reason} -> workflow_error(conn, reason)
    end
  end

  def create_workflow(conn) do
    params = conn.body_params || %{}

    case Symphony.Workflow.Files.create(params) do
      {:ok, payload} ->
        with {:ok, agent_payload} <- ensure_workflow_agents(params, payload) do
          json(conn, 201, Map.merge(payload, agent_payload))
        else
          {:error, reason} -> workflow_error(conn, reason)
        end

      {:error, reason} ->
        workflow_error(conn, reason)
    end
  end

  def move_workflow(conn) do
    case Symphony.Workflow.Files.move(conn.body_params || %{}) do
      {:ok, payload} -> json(conn, 200, payload)
      {:error, reason} -> workflow_error(conn, reason)
    end
  end

  def codex_cli_status(conn), do: json(conn, 200, Symphony.Codex.Auth.status(current_config()))

  def codex_auth_status(conn), do: json(conn, 200, Symphony.Codex.Auth.status(current_config()))

  def codex_auth_login_start(conn) do
    Symphony.Events.publish(%{
      type: "auth.codex.login.requested",
      source: "http_api",
      action: "login_start",
      message: "Codex login requested."
    })

    case Symphony.Codex.Auth.login_start(current_config()) do
      {:ok, payload} ->
        publish_codex_auth_event("auth.codex.login.completed", payload)
        json(conn, 200, payload)

      {:error, :codex_cli_missing} ->
        error(conn, 404, "Codex CLI executable was not found")

      {:error, reason} ->
        error(conn, 500, inspect(reason))
    end
  end

  def codex_auth_check(conn) do
    {:ok, payload} = Symphony.Codex.Auth.check(current_config())
    publish_codex_auth_event("auth.codex.check.completed", payload)
    json(conn, 200, payload)
  end

  def codex_auth_logout(conn) do
    case Symphony.Codex.Auth.logout(current_config()) do
      {:ok, payload} ->
        publish_codex_auth_event("auth.codex.logout.completed", payload)
        json(conn, 200, payload)

      {:error, :codex_cli_missing} ->
        error(conn, 404, "Codex CLI executable was not found")

      {:error, reason} ->
        error(conn, 500, inspect(reason))
    end
  end

  def list_agents(conn) do
    with {:ok, profiles} <- Symphony.AgentProfileRegistry.list(),
         {:ok, metadata} <- Symphony.AgentProfileRegistry.metadata() do
      json(conn, 200, %{profiles: profiles, count: length(profiles), storage: metadata})
    else
      {:error, reason} -> error(conn, 500, reason)
    end
  end

  def get_agent(conn, id) do
    case Symphony.AgentProfileRegistry.get(id) do
      {:ok, profile} -> json(conn, 200, %{profile: profile})
      {:error, :not_found} -> error(conn, 404, :not_found)
    end
  end

  def create_agent(conn) do
    case Symphony.AgentProfileRegistry.create(conn.body_params || %{}) do
      {:ok, profile} -> json(conn, 201, %{profile: profile})
      {:error, {:conflict, message}} -> error(conn, 409, message)
      {:error, {:validation, message}} -> error(conn, 422, message)
      {:error, reason} -> error(conn, 500, reason)
    end
  end

  def update_agent(conn, id) do
    case Symphony.AgentProfileRegistry.update(id, conn.body_params || %{}) do
      {:ok, profile} -> json(conn, 200, %{profile: profile})
      {:error, :not_found} -> error(conn, 404, :not_found)
      {:error, {:conflict, message}} -> error(conn, 409, message)
      {:error, {:validation, message}} -> error(conn, 422, message)
      {:error, reason} -> error(conn, 500, reason)
    end
  end

  def delete_agent(conn, id) do
    case Symphony.AgentProfileRegistry.delete(id) do
      :ok -> json(conn, 200, %{ok: true, deleted: id})
      {:error, :not_found} -> error(conn, 404, :not_found)
    end
  end

  def reload_workflow(conn) do
    with {:ok, config} <- Symphony.Config.load(),
         {:ok, orchestrator} <- Symphony.Orchestrator.reload_config(config),
         {:ok, registry} <- Symphony.AgentProfileRegistry.reload_config(config),
         {:ok, agent_payload} <- ensure_active_workflow_agents(config) do
      json(
        conn,
        200,
        %{
          ok: true,
          reloaded: true,
          message: "Runtime workflow configuration reloaded.",
          workflow: workflow_metadata(config),
          orchestrator: Map.take(orchestrator, [:counts, :polling]),
          agent_registry: registry
        }
        |> Map.merge(agent_payload)
      )
    else
      {:error, :active_runs, message, data} ->
        json(conn, 409, %{
          ok: false,
          reloaded: false,
          error: %{code: "active_runs", message: message, data: data},
          workflow: workflow_metadata()
        })

      {:error, reason} ->
        workflow_error(conn, reason)
    end
  end

  def refresh(conn) do
    Symphony.Events.publish(%{
      type: "operator.refresh.requested",
      source: "http_api",
      action: "refresh",
      message: "Operator requested a Linear poll."
    })

    Symphony.Orchestrator.refresh()

    json(conn, 202, %{
      queued: true,
      coalesced: false,
      requested_at: DateTime.utc_now(),
      operations: ["poll", "reconcile"]
    })
  end

  def debug_issue(conn, id) do
    case find_issue(id) do
      {:ok, card} ->
        json(conn, 200, %{
          ok: true,
          issue:
            Map.take(card, [:id, :issue_id, :identifier, :linear_identifier, :title, :state]),
          operator_status: card[:operator_status],
          operator_summary: card[:operator_summary],
          card: card,
          activity: card[:events] || []
        })

      :error ->
        json(conn, 404, %{ok: false, error: %{code: "not_found", message: "issue not found"}})
    end
  end

  def move_issue(conn, id) do
    target = body_value(conn, "target") || body_value(conn, "column") || body_value(conn, "state")

    Symphony.Events.publish(%{
      type: "operator.issue.move.accepted",
      source: "http_api",
      issue_id: id,
      action: "move",
      message: "Move request accepted for operator workflow.",
      data: %{target: target, external_tracker_wired: false}
    })

    json(conn, 202, %{
      ok: true,
      issue_id: id,
      accepted: true,
      target: target,
      message:
        "Move request accepted for operator workflow; external tracker mutation is not wired yet."
    })
  end

  def issue_action(conn, id, action) do
    Symphony.Events.publish(%{
      type: "operator.issue.action.accepted",
      source: "http_api",
      issue_id: id,
      action: action,
      message: "Operator action accepted.",
      data: %{external_tracker_wired: false}
    })

    json(conn, 202, %{
      ok: true,
      issue_id: id,
      action: action,
      accepted: true,
      message: "Operator action accepted."
    })
  end

  def not_found(conn),
    do: json(conn, 404, %{ok: false, error: %{code: "not_found", message: "route not found"}})

  defp error(conn, status, :not_found), do: error(conn, status, "not found")

  defp error(conn, status, reason),
    do: json(conn, status, %{ok: false, error: %{code: "error", message: to_string(reason)}})

  defp ensure_workflow_agents(params, payload) do
    params = params || %{}
    content = payload[:content]

    profiles =
      params
      |> Symphony.Workflow.Files.companion_agent_profiles()
      |> case do
        [] when is_binary(content) ->
          Symphony.Workflow.Files.companion_agent_profiles(%{"content" => content})

        companion_profiles ->
          companion_profiles
      end

    case profiles do
      [] ->
        {:ok,
         %{
           agent_profiles: [],
           agent_profile_changes: %{created: [], updated: [], count: 0}
         }}

      profiles ->
        with {:ok, result} <- Symphony.AgentProfileRegistry.ensure_many(profiles) do
          Symphony.Events.publish(%{
            type: "workflow.agents.ensured",
            source: "http_api",
            action: "ensure_workflow_agents",
            message: "Workflow stage agents were created or refreshed.",
            data: %{
              created: result.created,
              updated: result.updated,
              count: result.count
            }
          })

          {:ok,
           %{
             agent_profiles: result.profiles,
             agent_profile_changes: %{
               created: result.created,
               updated: result.updated,
               count: result.count
             }
           }}
        end
    end
  end

  defp ensure_active_workflow_agents(config) do
    case File.read(config.workflow_path) do
      {:ok, content} ->
        ensure_workflow_agents(%{"content" => content}, %{content: content})

      {:error, reason} ->
        {:error, {:workflow_reload_failed, "workflow could not be read: #{inspect(reason)}"}}
    end
  end

  defp workflow_error(conn, :not_found), do: error(conn, 404, "workflow not found")

  defp workflow_error(conn, :template_not_found),
    do: error(conn, 404, "workflow template not found")

  defp workflow_error(conn, :conflict),
    do: error(conn, 409, "workflow destination already exists")

  defp workflow_error(conn, {:conflict, message}), do: error(conn, 409, message)

  defp workflow_error(conn, {:unsafe_path, message}), do: error(conn, 422, message)

  defp workflow_error(conn, {:validation, message}) when is_binary(message),
    do: error(conn, 422, message)

  defp workflow_error(conn, {:validation, messages}) when is_list(messages) do
    json(conn, 422, %{
      ok: false,
      error: %{code: "validation", message: Enum.join(messages, "; "), errors: messages}
    })
  end

  defp workflow_error(conn, {:workflow_parse_error, reason}),
    do: error(conn, 422, "workflow parse error: #{inspect(reason)}")

  defp workflow_error(conn, reason), do: error(conn, 500, inspect(reason))

  defp health_status do
    case Symphony.Config.validate_dispatch(current_config()) do
      :ok ->
        "healthy"

      {:error, errors} when is_list(errors) ->
        if Enum.any?(errors, &(&1 == :missing_tracker_api_key)),
          do: "degraded_missing_credentials",
          else: "degraded_config"

      _ ->
        "degraded_config"
    end
  end

  defp workflow_metadata(config \\ nil) do
    c = config || current_config()
    validation = Symphony.Config.validate_dispatch(c)

    %{
      path: c.workflow_path,
      loaded_at: get_in(c.workflow && Map.from_struct(c.workflow), [:loaded_at]),
      validation: validation_json(validation),
      tracker: %{
        kind: c.tracker_kind,
        endpoint: c.tracker_endpoint,
        project_slug: c.tracker_project_slug,
        active_states: c.active_states,
        terminal_states: c.terminal_states,
        has_api_key: is_binary(c.tracker_api_key) and String.trim(c.tracker_api_key) != ""
      },
      polling: %{interval_ms: c.poll_interval_ms},
      agent: %{
        max_concurrent_agents: c.max_concurrent_agents,
        max_turns: c.max_turns,
        max_retry_backoff_ms: c.max_retry_backoff_ms,
        max_concurrent_agents_by_state: c.max_concurrent_agents_by_state
      },
      workspace: %{root: c.workspace_root},
      agents: %{profiles_path: c.agent_profiles_path},
      codex: %{
        command: c.codex_command,
        turn_timeout_ms: c.codex_turn_timeout_ms,
        read_timeout_ms: c.codex_read_timeout_ms,
        stall_timeout_ms: c.codex_stall_timeout_ms
      },
      hooks: %{configured: Map.keys(c.hooks || %{}), timeout_ms: c.hook_timeout_ms},
      orchestration: %{
        active_provider: Symphony.Orchestration.Providers.active_provider(c),
        default_provider: "direct_codex",
        provider_contract: ["direct_codex", "agent_zero"]
      }
    }
  end

  defp validation_json(:ok), do: %{status: "ok", errors: []}

  defp validation_json({:error, errors}),
    do: %{status: "error", errors: Enum.map(errors, &inspect/1)}

  defp current_config do
    case Symphony.Config.load() do
      {:ok, c} -> c
      {:error, _} -> %Symphony.Config{}
    end
  end

  defp operator_status(snap) do
    cond do
      snap.counts.running > 0 -> "running"
      snap.counts.retrying > 0 -> "needs_attention"
      true -> "idle"
    end
  end

  defp operator_summary(snap),
    do:
      "#{snap.counts.running} running, #{snap.counts.retrying} retrying, #{snap.counts.completed} completed"

  def run_card(run) do
    issue = run.issue || %{}
    agent_profile = run.agent_profile || %{}
    phase = run.phase || "build"

    %{
      id: run.issue_id,
      issue_id: run.issue_id,
      identifier: run.issue_identifier,
      linear_identifier: run.issue_identifier,
      title: Map.get(issue, :title) || run.issue_identifier || run.issue_id,
      state: Map.get(issue, :state) || "Running",
      status: run.status,
      stage: phase,
      phase: phase,
      operator_status: phase_operator_status(phase),
      operator_summary: run.last_message,
      agent_profile: agent_profile,
      agent_profile_id: agent_profile[:id],
      agent_name: agent_profile[:name],
      agent_role: agent_profile[:role],
      agent_section: agent_profile[:section],
      instrument_name: agent_profile[:instrument_name],
      agent_profile_status: agent_profile[:status],
      workspace_path: run.workspace_path,
      session_id: run.session_id,
      last_event: run.last_event,
      last_message: run.last_message,
      last_event_at: run.last_event_at,
      started_at: run.started_at,
      turn_count: run.turn_count,
      tokens: run.tokens,
      refiner_attempt: run.refiner_attempt,
      refiner_max_attempts: run.refiner_max_attempts,
      judge_verdict: run.judge_verdict,
      verdict:
        get_in(run.judge_verdict || %{}, [:verdict]) ||
          get_in(run.judge_verdict || %{}, ["verdict"]),
      verdict_path:
        get_in(run.judge_verdict || %{}, [:path]) || get_in(run.judge_verdict || %{}, ["path"]),
      events: run.events
    }
  end

  defp phase_operator_status("judge"), do: "judging"
  defp phase_operator_status("refiner"), do: "refining"
  defp phase_operator_status(_), do: "running"

  defp retry_card(retry) do
    agent_profile = retry.agent_profile || %{}
    phase = retry.phase || "retry"

    %{
      id: retry.issue_id,
      issue_id: retry.issue_id,
      identifier: retry.issue_identifier,
      linear_identifier: retry.issue_identifier,
      title: retry.issue_identifier || retry.issue_id,
      state: "Retrying",
      status: "retrying",
      stage: phase,
      phase: phase,
      operator_status: "needs_attention",
      operator_summary: retry.error,
      agent_profile: agent_profile,
      agent_profile_id: agent_profile[:id],
      agent_name: agent_profile[:name],
      agent_role: agent_profile[:role],
      agent_section: agent_profile[:section],
      instrument_name: agent_profile[:instrument_name],
      agent_profile_status: agent_profile[:status],
      judge_verdict: retry.judge_verdict,
      verdict: retry.verdict,
      verdict_path: retry.verdict_path,
      reason: retry.reason,
      refiner_attempt: retry.refiner_attempt,
      refiner_max_attempts: retry.refiner_max_attempts,
      attempt: retry.attempt,
      due_at: retry.due_at,
      error: retry.error
    }
  end

  defp find_issue(id) do
    snap = Symphony.Orchestrator.snapshot()

    (Enum.map(snap.running, &run_card/1) ++ Enum.map(snap.retrying, &retry_card/1))
    |> Enum.find(fn card ->
      Enum.any?(
        [card[:id], card[:issue_id], card[:identifier], card[:linear_identifier]],
        &(&1 == id)
      )
    end)
    |> case do
      nil -> :error
      card -> {:ok, card}
    end
  end

  defp body_value(conn, key) do
    params = conn.body_params || %{}
    Map.get(params, key) || Map.get(params, String.to_atom(key))
  end

  defp provider_label("agent_zero"), do: "Agent Zero"
  defp provider_label("direct_codex"), do: "Direct Codex Agents"
  defp provider_label(provider), do: to_string(provider)

  defp publish_codex_auth_event(type, payload) do
    status = payload[:status] || payload["status"] || payload

    Symphony.Events.publish(%{
      type: type,
      source: "codex_auth",
      action: auth_value(payload, :state) || auth_value(status, :state),
      status: auth_value(status, :state),
      message: auth_value(payload, :message) || auth_value(status, :message),
      data: %{
        authenticated: auth_value(status, :authenticated),
        connected: auth_value(status, :connected),
        cli_available: auth_value(status, :cli_available),
        auth_source: auth_value(status, :auth_source)
      }
    })
  end

  defp auth_value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, to_string(key)))
  defp auth_value(_map, _key), do: nil

  defp stream_events(conn) do
    receive do
      {:symphony_event, event} ->
        case write_sse(conn, event) do
          {:ok, next} -> stream_events(next)
          {:error, _reason} -> conn
        end
    after
      15_000 ->
        case chunk(conn, ": heartbeat #{DateTime.to_iso8601(DateTime.utc_now())}\n\n") do
          {:ok, next} -> stream_events(next)
          {:error, _reason} -> conn
        end
    end
  end

  defp write_sse(conn, event) do
    id = event[:id] || event["id"] || ""
    chunk(conn, "id: #{id}\ndata: #{Json.encode!(event)}\n\n")
  end
end
