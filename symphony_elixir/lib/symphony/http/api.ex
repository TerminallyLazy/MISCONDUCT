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

  def workflow(conn), do: json(conn, 200, workflow_metadata())

  def list_workflow_templates(conn),
    do: json(conn, 200, %{ok: true, templates: Symphony.Workflow.Files.templates()})

  def list_workflows(conn) do
    {:ok, payload} = Symphony.Workflow.Files.list()
    json(conn, 200, payload)
  end

  def generate_workflow(conn) do
    case Symphony.Workflow.Files.generate(conn.body_params || %{}) do
      {:ok, payload} -> json(conn, 200, payload)
      {:error, reason} -> workflow_error(conn, reason)
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
    case Symphony.Workflow.Files.create(conn.body_params || %{}) do
      {:ok, payload} -> json(conn, 201, payload)
      {:error, reason} -> workflow_error(conn, reason)
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
    case Symphony.Codex.Auth.login_start(current_config()) do
      {:ok, payload} -> json(conn, 200, payload)
      {:error, :codex_cli_missing} -> error(conn, 404, "Codex CLI executable was not found")
      {:error, reason} -> error(conn, 500, inspect(reason))
    end
  end

  def codex_auth_check(conn) do
    {:ok, payload} = Symphony.Codex.Auth.check(current_config())
    json(conn, 200, payload)
  end

  def codex_auth_logout(conn) do
    case Symphony.Codex.Auth.logout(current_config()) do
      {:ok, payload} -> json(conn, 200, payload)
      {:error, :codex_cli_missing} -> error(conn, 404, "Codex CLI executable was not found")
      {:error, reason} -> error(conn, 500, inspect(reason))
    end
  end

  def list_agents(conn) do
    case Symphony.AgentProfileRegistry.list() do
      {:ok, profiles} -> json(conn, 200, %{profiles: profiles})
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
    json(conn, 202, %{
      ok: true,
      reloaded: false,
      message:
        "Runtime workflow reload is not wired yet; restart the service to load WORKFLOW.md changes.",
      workflow: workflow_metadata()
    })
  end

  def refresh(conn) do
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

  defp workflow_error(conn, :not_found), do: error(conn, 404, "workflow not found")

  defp workflow_error(conn, :template_not_found),
    do: error(conn, 404, "workflow template not found")

  defp workflow_error(conn, :conflict),
    do: error(conn, 409, "workflow destination already exists")

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

  defp workflow_metadata do
    c = current_config()
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
      hooks: %{configured: Map.keys(c.hooks || %{}), timeout_ms: c.hook_timeout_ms}
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

  defp run_card(run) do
    issue = run.issue || %{}

    %{
      id: run.issue_id,
      issue_id: run.issue_id,
      identifier: run.issue_identifier,
      linear_identifier: run.issue_identifier,
      title: Map.get(issue, :title) || run.issue_identifier || run.issue_id,
      state: Map.get(issue, :state) || "Running",
      status: run.status,
      operator_status: "running",
      operator_summary: run.last_message,
      workspace_path: run.workspace_path,
      session_id: run.session_id,
      last_event: run.last_event,
      last_message: run.last_message,
      last_event_at: run.last_event_at,
      started_at: run.started_at,
      turn_count: run.turn_count,
      tokens: run.tokens,
      events: run.events
    }
  end

  defp retry_card(retry) do
    %{
      id: retry.issue_id,
      issue_id: retry.issue_id,
      identifier: retry.issue_identifier,
      linear_identifier: retry.issue_identifier,
      title: retry.issue_identifier || retry.issue_id,
      state: "Retrying",
      status: "retrying",
      operator_status: "needs_attention",
      operator_summary: retry.error,
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
end
