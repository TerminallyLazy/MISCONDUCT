defmodule Symphony.TestLinearClient do
  @behaviour Symphony.Linear.Client

  def fetch_candidate_issues(_config),
    do: {:ok, Application.get_env(:symphony_elixir, :test_linear_issues, [])}

  def fetch_issues_by_states(_states, config), do: fetch_candidate_issues(config)
  def fetch_issue_states_by_ids(_ids, _config), do: {:ok, []}
end

defmodule Symphony.TestRunner do
  @behaviour Symphony.AgentRunner

  def run(run, _workspace, _config, orchestrator) do
    send(
      orchestrator,
      {:agent_event, run.issue_id, %{event: "session_started", message: "test run started"}}
    )

    Process.sleep(250)
    :ok
  end
end

defmodule Symphony.OrchestratorPollingTest do
  use ExUnit.Case, async: false

  alias Symphony.{Config, Linear.Issue, Orchestrator, Workflow}

  setup do
    old_client = Application.get_env(:symphony_elixir, :linear_client)
    old_runner = Application.get_env(:symphony_elixir, :agent_runner)
    old_issues = Application.get_env(:symphony_elixir, :test_linear_issues)

    Application.put_env(:symphony_elixir, :linear_client, Symphony.TestLinearClient)
    Application.put_env(:symphony_elixir, :agent_runner, Symphony.TestRunner)

    dir = Path.join(System.tmp_dir!(), "symphony-poll-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      restore_env(:linear_client, old_client)
      restore_env(:agent_runner, old_runner)
      restore_env(:test_linear_issues, old_issues)
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  test "manual refresh polls Linear candidates and dispatches real runs", %{dir: dir} do
    issue = issue("poll-1", "TER-1", "Wire real polling")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])

    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0)

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)
             snap.polling.last_poll_count == 1 and snap.counts.running == 1
           end)

    snap = Orchestrator.snapshot(pid)
    assert [run] = snap.running
    assert run.issue_identifier == "TER-1"
    assert snap.polling.last_poll_error == nil
  end

  test "interval polling schedules and ingests Linear candidates", %{dir: dir} do
    issue = issue("poll-2", "TER-2", "Scheduled polling")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])

    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 25)

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)
             snap.polling.last_poll_count == 1 and snap.counts.running == 1
           end)
  end

  test "poll errors are surfaced in snapshots", %{dir: dir} do
    Application.put_env(:symphony_elixir, :linear_client, Symphony.ErrorLinearClient)
    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0)

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)
             snap.polling.last_poll_error =~ "linear_down"
           end)
  end

  defp start_orchestrator(dir, opts) do
    name = :"poll_orchestrator_#{System.unique_integer([:positive])}"

    config = %Config{
      workflow_path: Path.join(dir, "WORKFLOW.md"),
      workflow_dir: dir,
      workflow: %Workflow{prompt_template: "Work on {{ issue.identifier }}: {{ issue.title }}"},
      tracker_kind: "linear",
      tracker_api_key: "test-key",
      tracker_project_slug: "real-test-project",
      workspace_root: dir,
      hooks: %{},
      poll_interval_ms: Keyword.fetch!(opts, :poll_interval_ms),
      max_concurrent_agents: 10,
      max_retry_backoff_ms: 100
    }

    Orchestrator.start_link(name: name, config: config)
  end

  defp issue(id, identifier, title),
    do: %Issue{id: id, identifier: identifier, title: title, state: "Todo"}

  defp eventually(fun, attempts \\ 30)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.(),
      do: true,
      else:
        (
          Process.sleep(20)
          eventually(fun, attempts - 1)
        )
  end

  defp eventually(_fun, 0), do: false

  defp restore_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end

defmodule Symphony.ErrorLinearClient do
  @behaviour Symphony.Linear.Client

  def fetch_candidate_issues(_config), do: {:error, :linear_down}
  def fetch_issues_by_states(_states, _config), do: {:error, :linear_down}
  def fetch_issue_states_by_ids(_ids, _config), do: {:error, :linear_down}
end
