defmodule Symphony.Http.RouterTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Plug.Test

  test "serves dashboard and operator API endpoints" do
    conn = conn(:get, "/dashboard") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    assert conn.resp_body =~ "Symphony Dashboard"

    conn = conn(:get, "/api/workflow") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    assert Jason.decode!(conn.resp_body)["validation"]

    conn = conn(:get, "/api/kanban") |> Symphony.Http.Router.call([])
    assert conn.status == 200
    body = Jason.decode!(conn.resp_body)
    assert is_list(body["columns"])
    assert body["counts"]
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
    assert generated["review"]["judge"]

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

    assert Jason.decode!(conn.resp_body)["preview"]["frontmatter"]["tracker"]["api_key"] ==
             "$LINEAR_API_KEY"

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
end
