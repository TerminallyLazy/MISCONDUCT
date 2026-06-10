defmodule Symphony.WorkflowConfigTest do
  use ExUnit.Case, async: true

  test "loads WORKFLOW.md front matter and strict prompt" do
    dir = Path.join(System.tmp_dir!(), "symwf_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    wf = Path.join(dir, "WORKFLOW.md")

    File.write!(wf, """
    ---
    tracker:
      kind: linear
      api_key: $TEST_LINEAR_KEY
      project_slug: DEMO
    polling:
      interval_ms: 1234
    workspace:
      root: ./ws
    agent:
      max_concurrent_agents_by_state:
        Todo: 2
    ---
    Work on {{ issue.identifier }} attempt {{ attempt }}.
    """)

    System.put_env("TEST_LINEAR_KEY", "secret")
    {:ok, config} = Symphony.Config.load(wf)
    assert config.tracker_kind == "linear"
    assert config.tracker_api_key == "secret"
    assert config.poll_interval_ms == 1234
    assert config.workspace_root == Path.expand("ws", dir)
    assert config.max_concurrent_agents_by_state["todo"] == 2
    assert :ok == Symphony.Config.validate_dispatch(config)
    issue = %Symphony.Linear.Issue{id: "1", identifier: "LIN-1", title: "T", state: "Todo"}

    assert {:ok, "Work on LIN-1 attempt 3."} ==
             Symphony.Prompt.render(config.workflow.prompt_template, issue, 3)

    assert {:ok, "Agent Codex Builder plays Violin."} ==
             Symphony.Prompt.render(
               "Agent {{ agent.name }} plays {{ agent.instrument_name }}.",
               issue,
               3,
               %{agent: %{name: "Codex Builder", instrument_name: "Violin"}}
             )

    assert {:error, {:template_render_error, _}} = Symphony.Prompt.render("{{ missing }}", issue)
  end

  test "manual workflow validates without Linear credentials" do
    dir = Path.join(System.tmp_dir!(), "symwf_manual_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    wf = Path.join(dir, "WORKFLOW.md")

    File.write!(wf, """
    ---
    tracker:
      kind: none
    polling:
      interval_ms: 0
    workspace:
      root: ./ws
    codex:
      command: codex app-server
    ---
    Conduct {{ issue.identifier }}: {{ issue.title }}.
    """)

    old_linear_key = System.get_env("LINEAR_API_KEY")
    old_linear_project = System.get_env("LINEAR_PROJECT_SLUG")

    on_exit(fn ->
      restore_env("LINEAR_API_KEY", old_linear_key)
      restore_env("LINEAR_PROJECT_SLUG", old_linear_project)
    end)

    System.delete_env("LINEAR_API_KEY")
    System.delete_env("LINEAR_PROJECT_SLUG")

    {:ok, config} = Symphony.Config.load(wf)
    assert config.tracker_kind == "none"
    assert config.tracker_api_key == nil
    assert config.tracker_project_slug == nil
    assert config.poll_interval_ms == 0
    assert :ok == Symphony.Config.validate_dispatch(config)
    assert Symphony.Config.tracker_poll_errors(config) == [:tracker_disabled]
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
