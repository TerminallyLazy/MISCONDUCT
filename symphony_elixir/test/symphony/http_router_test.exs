defmodule Symphony.HttpRouterTestRunner do
  @behaviour Symphony.AgentRunner

  def run(run, _workspace, _config, orchestrator) do
    send(orchestrator, {
      :agent_event,
      run.issue_id,
      %{event: "session_started", message: "router test movement accepted"}
    })

    if run.phase == "conductor" do
      path = Path.join([run.workspace_path, ".symphony", "conductor-score.md"])
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "Router test Conductor score for #{run.issue_identifier}")
    end

    :ok
  end
end

defmodule Symphony.HttpRouterBlockingTestRunner do
  @behaviour Symphony.AgentRunner

  def run(run, _workspace, _config, orchestrator) do
    send(orchestrator, {
      :agent_event,
      run.issue_id,
      %{event: "session_started", message: "blocking router test movement accepted"}
    })

    receive do
      :release -> :ok
    after
      30_000 -> :ok
    end
  end
end

defmodule Symphony.Http.RouterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  test "serves dashboard and operator API endpoints" do
    conn = conn(:get, "/dashboard") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    assert conn.resp_body =~ "MISCONDUCT Dashboard"

    conn = conn(:get, "/api/workflow") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["validation"]

    conn = conn(:get, "/api/kanban") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_list(body["columns"])
    assert body["counts"]

    conn = conn(:get, "/api/rehearsal") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    rehearsal = Jason.decode!(conn.resp_body)
    assert is_boolean(rehearsal["ready"])
    assert is_list(rehearsal["checks"])
    assert Enum.any?(rehearsal["checks"], &(&1["id"] == "workflow"))
    assert Enum.any?(rehearsal["checks"], &(&1["id"] == "codex_auth"))
  end

  test "debug miss, move, actions, and not found routes return json" do
    conn = conn(:get, "/api/issues/LIN-101/debug") |> Symphony.Http.Router.call([])
    assert conn.status == 404

    conn =
      conn(:post, "/api/issues/LIN-101/move", Jason.encode!(%{target: "Done"}))
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 202
    assert Jason.decode!(conn.resp_body)["target"] == "Done"

    conn = conn(:post, "/api/issues/LIN-101/actions/retry") |> Symphony.Http.Router.call([])
    assert conn.status == 202
    assert Jason.decode!(conn.resp_body)["action"] == "retry"

    conn = conn(:get, "/missing") |> Symphony.Http.Router.call([])
    assert conn.status == 404
    assert Jason.decode!(conn.resp_body)["error"]["code"] == "not_found"
  end

  test "manual movement API dispatches without Linear credentials" do
    old_runner = Application.get_env(:symphony_elixir, :agent_runner)
    old_key = System.get_env("LINEAR_API_KEY")
    old_project = System.get_env("LINEAR_PROJECT_SLUG")

    on_exit(fn ->
      restore_app_env(:agent_runner, old_runner)
      restore_env("LINEAR_API_KEY", old_key)
      restore_env("LINEAR_PROJECT_SLUG", old_project)
    end)

    Application.put_env(:symphony_elixir, :agent_runner, Symphony.HttpRouterTestRunner)
    System.delete_env("LINEAR_API_KEY")
    System.delete_env("LINEAR_PROJECT_SLUG")

    conn =
      conn(
        :post,
        "/api/movements",
        Jason.encode!(%{
          title: "Rehearse optional tracker workflow",
          description: "Prove a movement can be queued without Linear.",
          expected_evidence: ["runtime evidence card includes changed files"],
          validation_commands: ["mix test test/symphony/http_api_test.exs"],
          file_focus: ["symphony_elixir/lib/symphony/http/api.ex"]
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 202
    body = Jason.decode!(conn.resp_body)
    assert body["accepted"] == true
    assert body["movement"]["identifier"] =~ "MOV-"
    assert body["movement"]["labels"] == ["manual", "misconduct"]
    assert body["movement"]["description"] =~ "Expected evidence:"
    assert body["movement"]["description"] =~ "- runtime evidence card includes changed files"
    assert body["movement"]["description"] =~ "Validation commands:"
    assert body["movement"]["description"] =~ "- mix test test/symphony/http_api_test.exs"
    assert body["movement"]["description"] =~ "File focus:"
    assert body["movement"]["description"] =~ "- symphony_elixir/lib/symphony/http/api.ex"
    assert body["run"]["title"] == "Rehearse optional tracker workflow"
  end

  test "agent profile list overlays active movement assignments" do
    old_runner = Application.get_env(:symphony_elixir, :agent_runner)
    old_key = System.get_env("LINEAR_API_KEY")
    old_project = System.get_env("LINEAR_PROJECT_SLUG")

    on_exit(fn ->
      restore_app_env(:agent_runner, old_runner)
      restore_env("LINEAR_API_KEY", old_key)
      restore_env("LINEAR_PROJECT_SLUG", old_project)
    end)

    Application.put_env(:symphony_elixir, :agent_runner, Symphony.HttpRouterBlockingTestRunner)
    System.delete_env("LINEAR_API_KEY")
    System.delete_env("LINEAR_PROJECT_SLUG")

    conn =
      conn(
        :post,
        "/api/movements",
        Jason.encode!(%{
          title: "Keep profile assignment visible",
          description: "Prove stage profiles reflect active runtime assignment."
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 202
    body = Jason.decode!(conn.resp_body)
    run = body["run"]
    identifier = run["identifier"]

    try do
      conn = conn(:get, "/api/agents") |> Symphony.Http.Router.call([])
      assert conn.status == 200
      agents = Jason.decode!(conn.resp_body)["profiles"]

      active_profile =
        Enum.find(agents, fn profile ->
          identifier in (profile["current_assignments"] || [])
        end)

      assert active_profile
      assert active_profile["status"] == "running"

      assert [%{"identifier" => ^identifier, "status" => "running"}] =
               active_profile["active_assignments"]
    after
      Symphony.Orchestrator.cancel(run["issue_id"])
    end
  end

  test "agent profile API creates, lists, updates, and deletes profiles" do
    name = "API Agent #{System.unique_integer([:positive])}"

    conn =
      conn(
        :post,
        "/api/agents",
        Jason.encode!(%{
          name: name,
          role: "developer",
          profile_key: "developer",
          section: "Strings",
          instrument_name: "Violin",
          capabilities: ["frontend", "tests"],
          max_concurrent_tasks: 1
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 201
    profile = Jason.decode!(conn.resp_body)["profile"]
    assert profile["name"] == name
    assert profile["section"] == "Strings"

    conn = conn(:get, "/api/agents") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    assert Enum.any?(Jason.decode!(conn.resp_body)["profiles"], &(&1["id"] == profile["id"]))

    conn =
      conn(
        :patch,
        "/api/agents/#{profile["id"]}",
        Jason.encode!(%{section: "Brass", instrument_name: "Trumpet"})
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["profile"]["section"] == "Brass"

    conn = conn(:delete, "/api/agents/#{profile["id"]}") |> Symphony.Http.Router.call([])
    assert conn.status == 200

    conn = conn(:get, "/api/agents/#{profile["id"]}") |> Symphony.Http.Router.call([])
    assert conn.status == 404
  end

  test "workflow file API generates, validates, previews, creates, moves, and rejects unsafe paths" do
    conn = conn(:get, "/api/workflows/templates") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    templates = Jason.decode!(conn.resp_body)["templates"]
    assert Enum.any?(templates, &(&1["id"] == "linear_codex_judge_refiner"))

    conn =
      conn(
        :post,
        "/api/workflows/generate",
        Jason.encode!(%{
          template_id: "blank",
          overrides: %{name: "router-workflow", objective: "Validate real workflow authoring."}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    generated = Jason.decode!(conn.resp_body)
    assert generated["content"] =~ "# Workflow"
    assert generated["content"] =~ "MISCONDUCT default workflow"
    assert generated["content"] =~ "stage_agents:"
    assert generated["content"] =~ "provider: codex"
    refute generated["content"] =~ "TODO:"
    assert generated["review"]["judge"]
    generated_ids = Enum.map(generated["agent_profiles"], & &1["id"])
    assert "workflow-builder" in generated_ids
    assert "workflow-judge" in generated_ids

    conn =
      conn(:post, "/api/workflows/validate", Jason.encode!(%{content: generated["content"]}))
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["parse"]["ok"] == true

    conn =
      conn(:post, "/api/workflows/preview", Jason.encode!(%{content: generated["content"]}))
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200

    tracker = Jason.decode!(conn.resp_body)["preview"]["frontmatter"]["tracker"]
    assert tracker["kind"] == "none"
    refute Map.has_key?(tracker, "api_key")
    assert generated["content"] =~ "Overture / Conductor Intake"

    path_root = "tmp-router-workflow-#{System.unique_integer([:positive])}"
    moved_path_root = "tmp-router-workflow-moved-#{System.unique_integer([:positive])}"
    path = Path.join(path_root, "WORKFLOW.md")
    moved_path = Path.join(moved_path_root, "WORKFLOW.md")

    on_exit(fn ->
      File.rm_rf!(path_root)
      File.rm_rf!(moved_path_root)
    end)

    conn =
      conn(
        :post,
        "/api/workflows",
        Jason.encode!(%{path: path, content: generated["content"], overwrite: true})
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 201
    assert Jason.decode!(conn.resp_body)["path"] == path

    conn = conn(:get, "/api/workflows") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    assert Enum.any?(Jason.decode!(conn.resp_body)["workflows"], &(&1["path"] == path))

    conn =
      conn(
        :post,
        "/api/workflows",
        Jason.encode!(%{path: path, content: generated["content"], overwrite: false})
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 409

    conn =
      conn(
        :post,
        "/api/workflows/move",
        Jason.encode!(%{source_path: path, destination_path: moved_path, overwrite: true})
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["destination_path"] == moved_path

    conn =
      conn(
        :post,
        "/api/workflows",
        Jason.encode!(%{path: "../WORKFLOW.md", content: generated["content"]})
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 422
  end

  test "workflow generation and save ensure stage agent profiles" do
    conn =
      conn(
        :post,
        "/api/workflows/generate",
        Jason.encode!(%{
          template_id: "linear_codex_judge_refiner",
          overrides: %{name: "router-orchestra", objective: "Create the stage quartet."}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    generated = Jason.decode!(conn.resp_body)
    generated_ids = Enum.map(generated["agent_profiles"], & &1["id"])
    assert "workflow-generator" in generated_ids
    assert "workflow-builder" in generated_ids
    assert "workflow-judge" in generated_ids
    assert "workflow-refiner" in generated_ids
    assert generated["content"] =~ "stage_agents:"
    assert generated["content"] =~ "instrument: \"Piano\""

    conn = conn(:get, "/api/agents") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    listed_ids = Enum.map(Jason.decode!(conn.resp_body)["profiles"], & &1["id"])
    assert "workflow-judge" in listed_ids
    assert "workflow-refiner" in listed_ids

    path_root = "tmp-router-stage-agents-#{System.unique_integer([:positive])}"
    path = Path.join(path_root, "WORKFLOW.md")
    on_exit(fn -> File.rm_rf!(path_root) end)

    conn =
      conn(
        :post,
        "/api/workflows",
        Jason.encode!(%{path: path, content: generated["content"], overwrite: true})
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 201
    saved = Jason.decode!(conn.resp_body)
    saved_ids = Enum.map(saved["agent_profiles"], & &1["id"])
    assert "workflow-judge" in saved_ids
    assert "workflow-refiner" in saved_ids
    assert saved["agent_profile_changes"]["count"] == 4
  end

  test "workflow generation can assign an existing stage agent profile to a role" do
    name = "Solo Builder #{System.unique_integer([:positive])}"

    conn =
      conn(
        :post,
        "/api/agents",
        Jason.encode!(%{
          name: name,
          role: "Builder",
          profile_key: "solo-builder",
          section: "Strings",
          instrument_name: "Cello",
          capabilities: ["implementation", "codex"],
          music: %{"motif" => "Custom build line", "dynamic" => "mezzo-forte"},
          stage_position: %{"section" => "strings", "seat" => "front-right"}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 201
    profile = Jason.decode!(conn.resp_body)["profile"]

    conn =
      conn(
        :post,
        "/api/workflows/generate",
        Jason.encode!(%{
          template_id: "linear_codex_judge_refiner",
          overrides: %{
            name: "router-custom-builder",
            objective: "Use the selected stage builder.",
            builder_profile: profile["id"]
          }
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    generated = Jason.decode!(conn.resp_body)
    generated_ids = Enum.map(generated["agent_profiles"], & &1["id"])
    refute "workflow-builder" in generated_ids
    assert profile["id"] in generated_ids
    assert generated["content"] =~ "profile: #{inspect(profile["id"])}"
    assert generated["content"] =~ "instrument: \"Cello\""
    assert generated["content"] =~ "seat: \"front-right\""
  end

  test "workflow save refresh preserves operator-edited stage and music profile fields" do
    suffix = "#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
    profile_id = "router-preserve-#{suffix}"
    path_root = "tmp-router-preserve-stage-#{suffix}"
    path = Path.join(path_root, "WORKFLOW.md")

    content = """
    ---
    name: preserve-stage-profile
    tracker:
      kind: linear
      api_key: $LINEAR_API_KEY
      project_slug: TEST
    workspace:
      root: ./tmp-router-preserve-workspaces
    agent:
      profiles_path: ./agent_profiles.json
    builder:
      provider: codex
      profile: #{profile_id}
    judge:
      provider: codex
      profile: #{profile_id}
    refiner:
      provider: codex
      profile: #{profile_id}
    stage_agents:
      - profile: #{profile_id}
        name: Preserve Builder #{suffix}
        role: Builder
        profile_key: #{profile_id}
        section: Strings
        instrument: Violin
        capabilities: [implementation, codex]
        music:
          motif: Workflow motif
          dynamic: mezzo-piano
          register: middle
        stage:
          section: strings
          seat: front-center
    ---
    # Workflow

    ## Objective
    Preserve edited stage placement and music when WORKFLOW.md refreshes agents.

    ## Inputs
    - Synthetic router test workflow.

    ## Agents
    - #{profile_id}: generated from stage_agents.

    ## Phases
    - Build: execute scoped work.
    - Judge: review output.
    - Refine: fix findings.

    ## Validation Gates
    - Preserve operator-owned profile fields.

    ## Guardrails
    - No external tracker mutation.
    """

    on_exit(fn ->
      _ = Symphony.AgentProfileRegistry.delete(profile_id)
      File.rm_rf!(path_root)
    end)

    conn =
      conn(
        :post,
        "/api/workflows",
        Jason.encode!(%{path: path, content: content, overwrite: true})
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 201
    created = Jason.decode!(conn.resp_body)
    assert created["agent_profile_changes"]["created"] == [profile_id]

    conn =
      conn(
        :patch,
        "/api/agents/#{profile_id}",
        Jason.encode!(%{
          section: "Bells",
          instrument_name: "Glockenspiel",
          music: %{motif: "Operator cue", dynamic: "forte"},
          stage_position: %{section: "bells", seat: "back-center"}
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200

    conn =
      conn(
        :post,
        "/api/workflows",
        Jason.encode!(%{path: path, content: content, overwrite: true})
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 201
    refreshed = Jason.decode!(conn.resp_body)
    assert refreshed["agent_profile_changes"]["updated"] == [profile_id]

    conn = conn(:get, "/api/agents/#{profile_id}") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    profile = Jason.decode!(conn.resp_body)["profile"]
    assert profile["section"] == "Bells"
    assert profile["instrument_name"] == "Glockenspiel"
    assert profile["music"]["motif"] == "Operator cue"
    assert profile["music"]["dynamic"] == "forte"
    assert profile["music"]["register"] == "high"
    assert profile["stage_position"] == %{"section" => "bells", "seat" => "back-center"}
    assert profile["capabilities"] == ["implementation", "codex"]
  end

  test "workflow generation flags a missing selected role profile" do
    missing_profile = "missing-builder-#{System.unique_integer([:positive])}"

    conn =
      conn(
        :post,
        "/api/workflows/generate",
        Jason.encode!(%{
          template_id: "linear_codex_judge_refiner",
          overrides: %{
            name: "router-missing-builder",
            objective: "Catch a missing selected builder.",
            builder_profile: missing_profile
          }
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    generated = Jason.decode!(conn.resp_body)
    generated_ids = Enum.map(generated["agent_profiles"], & &1["id"])
    refute missing_profile in generated_ids
    assert generated["content"] =~ "profile: #{inspect(missing_profile)}"

    dispatch_errors = get_in(generated, ["validation", "dispatch", "errors"]) || []
    assert Enum.any?(dispatch_errors, &String.contains?(&1, "profile #{missing_profile}"))
    assert generated["validation"]["valid"] == false
    assert generated["review"]["verdict"] == "needs_refinement"

    assert Enum.any?(
             generated["review"]["judge"]["findings"],
             &String.contains?(&1, missing_profile)
           )
  end

  test "workflow generation flags a disabled selected role profile" do
    name = "Disabled Builder #{System.unique_integer([:positive])}"

    conn =
      conn(
        :post,
        "/api/agents",
        Jason.encode!(%{
          name: name,
          role: "Builder",
          profile_key: "disabled-builder",
          section: "Strings",
          instrument_name: "Violin",
          enabled: false
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 201
    profile = Jason.decode!(conn.resp_body)["profile"]

    conn =
      conn(
        :post,
        "/api/workflows/generate",
        Jason.encode!(%{
          template_id: "linear_codex_judge_refiner",
          overrides: %{
            name: "router-disabled-builder",
            objective: "Catch a disabled selected builder.",
            builder_profile: profile["id"]
          }
        })
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    generated = Jason.decode!(conn.resp_body)
    assert generated["content"] =~ "profile: #{inspect(profile["id"])}"
    assert generated["content"] =~ "enabled: \"false\""

    dispatch_errors = get_in(generated, ["validation", "dispatch", "errors"]) || []

    assert Enum.any?(
             dispatch_errors,
             &String.contains?(&1, "profile #{profile["id"]} is disabled")
           )

    assert generated["validation"]["valid"] == false
    assert generated["review"]["verdict"] == "needs_refinement"

    assert Enum.any?(
             generated["review"]["judge"]["findings"],
             &String.contains?(&1, profile["id"])
           )
  end

  test "workflow judge flags missing judge and refiner metadata" do
    content = """
    ---
    name: weak-workflow
    tracker:
      kind: linear
      api_key: $LINEAR_API_KEY
      project_slug: TEST
    workspace:
      root: ./tmp-router-workflow
    server:
      port: 4004
    ---
    Handle the issue.
    """

    conn =
      conn(:post, "/api/workflows/validate", Jason.encode!(%{content: content}))
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    warnings = body["warnings"] || []
    assert Enum.any?(warnings, &String.contains?(&1, "missing judge metadata"))
    assert Enum.any?(warnings, &String.contains?(&1, "missing refiner metadata"))
    assert get_in(body, ["metadata", "has_judge"]) == false
    assert get_in(body, ["metadata", "has_refiner"]) == false
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
  defp restore_app_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end
