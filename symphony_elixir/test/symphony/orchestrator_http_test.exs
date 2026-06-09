defmodule Symphony.OrchestratorHttpTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Plug.Test

  setup do
    old_app_provider = Application.get_env(:symphony_elixir, :orchestration_provider)
    old_agent_zero_url = System.get_env("SYMPHONY_AGENT_ZERO_URL")

    assert Process.whereis(Symphony.AgentSupervisor)
    assert Process.whereis(Symphony.Workspace.Manager)
    assert Process.whereis(Symphony.Orchestrator)

    on_exit(fn ->
      restore_app_env(:orchestration_provider, old_app_provider)
      restore_env("SYMPHONY_AGENT_ZERO_URL", old_agent_zero_url)
    end)

    :ok
  end

  test "router health and state endpoints return json" do
    conn = conn(:get, "/healthz") |> Symphony.Http.Router.call([])
    assert conn.status == 200

    assert Jason.decode!(conn.resp_body)["status"] in [
             "healthy",
             "degraded_missing_credentials",
             "degraded_config"
           ]

    conn = conn(:get, "/api/v1/state") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["counts"]
  end

  test "events endpoint returns provider-neutral event history" do
    Symphony.Events.reset()
    Symphony.Events.publish(%{type: "provider.selected", provider: "direct_codex"})

    conn = conn(:get, "/api/events") |> Symphony.Http.Router.call([])
    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["stream"] == "/api/events/stream"
    assert [%{"type" => "provider.selected", "provider" => "direct_codex"}] = body["events"]
  end

  test "provider endpoint exposes direct codex default and optional agent zero" do
    conn = conn(:get, "/api/orchestration/providers") |> Symphony.Http.Router.call([])
    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["active_provider"] in ["direct_codex", "agent_zero"]
    assert body["default_provider"] == "direct_codex"
    assert body["provider_contract"] == ["direct_codex", "agent_zero"]
    assert Enum.any?(body["providers"], &(&1["id"] == "direct_codex"))
    assert Enum.any?(body["providers"], &(&1["id"] == "agent_zero"))
  end

  test "provider selection endpoint accepts direct codex" do
    conn =
      conn(
        :post,
        "/api/orchestration/providers/select",
        Jason.encode!(%{provider: "direct_codex"})
      )
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["active_provider"] == "direct_codex"
  end

  test "provider selection endpoint rejects agent zero while adapter is pending" do
    System.put_env("SYMPHONY_AGENT_ZERO_URL", "http://127.0.0.1:55000")

    conn =
      conn(:post, "/api/orchestration/providers/select", Jason.encode!(%{provider: "agent_zero"}))
      |> put_req_header("content-type", "application/json")
      |> Symphony.Http.Router.call([])

    assert conn.status == 409
    body = Jason.decode!(conn.resp_body)
    assert body["error"]["code"] == "agent_zero_adapter_pending"
    assert body["provider_status"]["active_provider"] == "direct_codex"
  end

  test "workflow reload endpoint reloads runtime config and ensures stage agents" do
    old_workflow_path = System.get_env("SYMPHONY_WORKFLOW_PATH")
    old_config = Symphony.Config.load()

    dir =
      Path.join(System.tmp_dir!(), "symphony-http-reload-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    workflow_path = Path.join(dir, "WORKFLOW.md")

    {:ok, content} =
      Symphony.Workflow.Files.render_template("linear_codex_judge_refiner", %{
        "name" => "http-reload-orchestra",
        "objective" => "Reload without restarting the desktop backend."
      })

    File.write!(workflow_path, content)
    System.put_env("SYMPHONY_WORKFLOW_PATH", workflow_path)

    on_exit(fn ->
      restore_env("SYMPHONY_WORKFLOW_PATH", old_workflow_path)

      case old_config do
        {:ok, config} ->
          _ = Symphony.AgentProfileRegistry.reload_config(config)
          _ = Symphony.Orchestrator.reload_config(config)

        _ ->
          :ok
      end

      File.rm_rf!(dir)
    end)

    conn = conn(:post, "/api/workflow/reload") |> Symphony.Http.Router.call([])

    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert body["reloaded"] == true
    assert body["workflow"]["path"] == Path.expand(workflow_path)
    assert body["workflow"]["polling"]["interval_ms"] == 30_000
    assert body["agent_registry"]["path"] == Path.join(dir, "agent_profiles.json")
    assert body["agent_profile_changes"]["count"] == 4

    conn = conn(:get, "/api/agents") |> Symphony.Http.Router.call([])
    listed_ids = Enum.map(Jason.decode!(conn.resp_body)["profiles"], & &1["id"])
    assert "workflow-builder" in listed_ids
    assert "workflow-judge" in listed_ids
    assert "workflow-refiner" in listed_ids
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
  defp restore_app_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end
