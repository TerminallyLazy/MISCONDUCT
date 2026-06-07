defmodule Symphony.OrchestratorHttpTest do
  use ExUnit.Case, async: false
  import Plug.Test

  setup do
    assert Process.whereis(Symphony.AgentSupervisor)
    assert Process.whereis(Symphony.Workspace.Manager)
    assert Process.whereis(Symphony.Orchestrator)
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
end
