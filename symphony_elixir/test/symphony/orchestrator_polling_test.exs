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
      {:agent_event, run.issue_id,
       %{event: "session_started", message: "test #{run.phase || "build"} run started"}}
    )

    maybe_write_conductor_score(run)
    maybe_write_judge_verdict(run)
    Process.sleep(250)
    :ok
  end

  defp maybe_write_conductor_score(%{phase: "conductor", workspace_path: workspace_path} = run) do
    path = Path.join([workspace_path, ".symphony", "conductor-score.md"])
    File.mkdir_p!(Path.dirname(path))

    File.write!(path, """
    # Test Conductor Score

    Movement: #{run.issue_identifier}
    Builder should implement the scoped work and leave evidence for Judge.
    """)
  end

  defp maybe_write_conductor_score(_run), do: :ok

  defp maybe_write_judge_verdict(%{phase: "judge", workspace_path: workspace_path}) do
    case next_judge_verdict() do
      :missing ->
        :ok

      {:invalid, content} ->
        path = judge_verdict_path(workspace_path)
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, content)

      nil ->
        :ok

      verdict when is_binary(verdict) ->
        write_judge_verdict(workspace_path, %{
          verdict: verdict,
          summary: "test #{verdict}",
          findings: default_findings(verdict),
          evidence: ["test runner verdict"]
        })

      verdict when is_map(verdict) ->
        write_judge_verdict(workspace_path, verdict)
    end
  end

  defp maybe_write_judge_verdict(_run), do: :ok

  defp default_findings(verdict)
       when verdict in ["needs_refinement", "refine", "blocked", "fail", "failed"],
       do: [
         %{
           severity: "blocking",
           message: "test #{verdict} finding",
           evidence: "test runner verdict"
         }
       ]

  defp default_findings(_verdict), do: []

  defp next_judge_verdict do
    case Application.get_env(:symphony_elixir, :test_judge_verdict_sequence, []) do
      [next | rest] ->
        Application.put_env(:symphony_elixir, :test_judge_verdict_sequence, rest)
        next

      _ ->
        nil
    end
  end

  defp write_judge_verdict(workspace_path, verdict) do
    path = judge_verdict_path(workspace_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(verdict))
  end

  defp judge_verdict_path(workspace_path),
    do: Path.join([workspace_path, ".symphony", "judge-verdict.json"])
end

defmodule Symphony.EvidenceSpanRunner do
  @behaviour Symphony.AgentRunner

  def run(run, _workspace, _config, orchestrator) do
    send(orchestrator, {
      :agent_event,
      run.issue_id,
      %{event: "session_started", message: "evidence span run started"}
    })

    send(orchestrator, {
      :agent_event,
      run.issue_id,
      %{event: "stdout", message: "changed lib/runtime_evidence.ex API_TOKEN=secret"}
    })

    send(orchestrator, {
      :agent_event,
      run.issue_id,
      %{event: "stderr", message: "validation warning"}
    })

    send(orchestrator, {
      :agent_event,
      run.issue_id,
      %{event: "turn_completed", message: "span run completed"}
    })

    :ok
  end
end

defmodule Symphony.OrchestratorPollingTest do
  use ExUnit.Case, async: false

  alias Symphony.{Config, Events, Linear.Issue, Orchestrator, Workflow}

  setup do
    old_client = Application.get_env(:symphony_elixir, :linear_client)
    old_runner = Application.get_env(:symphony_elixir, :agent_runner)
    old_issues = Application.get_env(:symphony_elixir, :test_linear_issues)
    old_provider = Application.get_env(:symphony_elixir, :orchestration_provider)

    old_judge_verdict_sequence =
      Application.get_env(:symphony_elixir, :test_judge_verdict_sequence)

    Application.put_env(:symphony_elixir, :linear_client, Symphony.TestLinearClient)
    Application.put_env(:symphony_elixir, :agent_runner, Symphony.TestRunner)
    Application.delete_env(:symphony_elixir, :orchestration_provider)
    Application.delete_env(:symphony_elixir, :test_judge_verdict_sequence)
    if Process.whereis(Events), do: Events.reset()

    dir = Path.join(System.tmp_dir!(), "symphony-poll-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      restore_env(:linear_client, old_client)
      restore_env(:agent_runner, old_runner)
      restore_env(:test_linear_issues, old_issues)
      restore_env(:orchestration_provider, old_provider)
      restore_env(:test_judge_verdict_sequence, old_judge_verdict_sequence)
      File.rm_rf!(dir)
    end)

    {:ok, dir: dir}
  end

  test "manual refresh polls Linear candidates and dispatches real runs", %{dir: dir} do
    issue = issue("poll-1", "TER-1", "Wire real polling")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    ensure_builder_profile()

    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0)

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)
             types = Events.list(50) |> Enum.map(& &1.type)

             snap.polling.last_poll_count == 1 and "tracker.poll.completed" in types and
               "issue.stage.started" in types and
               "agent.event" in types
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.polling.last_poll_error == nil

    started_event = Events.list(50) |> Enum.find(&(&1.type == "issue.stage.started"))
    assert started_event.issue_identifier == "TER-1"
    assert get_in(started_event, [:data, "agent_profile", "id"]) == "workflow-builder"
    assert get_in(started_event, [:data, "agent_profile", "name"]) == "Codex Builder"
    assert get_in(started_event, [:data, "agent_profile", "section"]) == "Strings"
    assert get_in(started_event, [:data, "agent_profile", "instrument_name"]) == "Violin"
    assert get_in(started_event, [:data, "agent_profile", "status"]) == "idle"
    assert get_in(started_event, [:data, "phase"]) == "build"
  end

  test "completed movements stay visible in recent completed runs", %{dir: dir} do
    ensure_builder_profile()
    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0)

    assert {:ok, _run} =
             Orchestrator.enqueue_issue(issue("manual-1", "MOV-1", "Visible finale"), nil, pid)

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)

             snap.counts.running == 0 and snap.counts.completed == 1 and
               Enum.any?(snap.completed_runs, &(&1.issue_identifier == "MOV-1"))
           end)

    snap = Orchestrator.snapshot(pid)
    [completed] = snap.completed_runs
    assert completed.status == :completed
    assert completed.issue.title == "Visible finale"
    assert completed.last_event
  end

  test "completed movements refresh runtime evidence from git status", %{dir: dir} do
    workspace = Path.join(dir, "repo")
    File.mkdir_p!(workspace)
    System.cmd("git", ["init"], cd: workspace)
    File.mkdir_p!(Path.join(workspace, "lib"))
    File.write!(Path.join(workspace, "lib/evidence.ex"), "runtime evidence\n")
    ensure_builder_profile()
    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0)

    issue = %Issue{
      id: "manual-evidence",
      identifier: "MOV-EVIDENCE",
      title: "Collect runtime evidence",
      state: "Todo",
      workspace_path: workspace,
      repository_path: workspace
    }

    assert {:ok, run} = Orchestrator.enqueue_issue(issue, nil, pid)
    assert run.runtime_evidence.workspace_path == workspace

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)

             Enum.any?(snap.completed_runs, fn run ->
               run.issue_identifier == "MOV-EVIDENCE" and
                 "lib/evidence.ex" in run.runtime_evidence.changed_files
             end)
           end)
  end

  test "runtime evidence captures runner stdout and stderr spans chronologically", %{dir: dir} do
    Application.put_env(:symphony_elixir, :agent_runner, Symphony.EvidenceSpanRunner)
    ensure_builder_profile()
    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0)

    assert {:ok, _run} =
             Orchestrator.enqueue_issue(
               issue("manual-spans", "MOV-SPANS", "Capture runner spans"),
               nil,
               pid
             )

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)

             Enum.any?(snap.completed_runs, fn run ->
               labels = Enum.map(run.runtime_evidence.command_spans, & &1.label)
               messages = Enum.map(run.runtime_evidence.command_spans, & &1.message)

               run.issue_identifier == "MOV-SPANS" and
                 labels == [
                   "runner session",
                   "runner stdout",
                   "runner stderr",
                   "runner turn"
                 ] and
                 "changed lib/runtime_evidence.ex API_TOKEN=[REDACTED]" in messages and
                 List.last(labels) == "runner turn"
             end)
           end)
  end

  test "configured conductor creates a score and hands it to builder", %{dir: dir} do
    issue = issue("manual-conductor", "MOV-CONDUCT", "Conduct a real score")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    ensure_conductor_and_builder_profiles()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config_with_conductor()
      )

    Orchestrator.refresh(pid)

    assert eventually(
             fn ->
               events = Events.list(100)

               Enum.any?(events, &(&1.type == "issue.stage.started" and &1.stage == "conductor")) and
                 Enum.any?(events, &(&1.type == "issue.score.ready" and &1.stage == "conductor")) and
                 Enum.any?(events, &(&1.type == "issue.stage.started" and &1.stage == "build"))
             end,
             80
           )

    events = Events.list(100)

    conductor_started =
      Enum.find(events, &(&1.type == "issue.stage.started" and &1.stage == "conductor"))

    build_started = Enum.find(events, &(&1.type == "issue.stage.started" and &1.stage == "build"))

    assert get_in(conductor_started, [:data, "agent_profile", "id"]) == "workflow-generator"
    assert get_in(build_started, [:data, "agent_profile", "id"]) == "workflow-builder"
    assert get_in(build_started, [:data, "score_path"]) =~ ".symphony/conductor-score.md"

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)

             snap.counts.running == 0 and snap.counts.completed == 1 and
               Enum.any?(snap.completed_runs, &(&1.issue_identifier == "MOV-CONDUCT"))
           end)

    snap = Orchestrator.snapshot(pid)
    completed = Enum.find(snap.completed_runs, &(&1.issue_identifier == "MOV-CONDUCT"))
    assert completed.score_path =~ ".symphony/conductor-score.md"
    assert completed.score_summary =~ "Test Conductor Score"

    assert Enum.any?(
             completed.phase_history,
             &(&1.phase == "conductor" and &1.status == "completed")
           )

    assert Enum.any?(completed.phase_history, &(&1.phase == "build" and &1.status == "completed"))

    assert Enum.any?(
             completed.conversation,
             &(&1.from == "Workflow Conductor" and &1.to == "Codex Builder")
           )

    assert Enum.any?(
             completed.conversation,
             &(&1.from == "Codex Builder" and &1.to == "Workflow Conductor")
           )
  end

  test "judge pass verdict completes with no retry", %{dir: dir} do
    issue = issue("poll-judge", "TER-JUDGE", "Judge real builder output")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    Application.put_env(:symphony_elixir, :test_judge_verdict_sequence, ["pass"])
    ensure_builder_and_judge_profiles()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config_with_judge()
      )

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             Events.list(100)
             |> Enum.any?(&(&1.type == "issue.stage.started" and &1.stage == "judge"))
           end)

    judge_started =
      Events.list(100)
      |> Enum.find(&(&1.type == "issue.stage.started" and &1.stage == "judge"))

    assert judge_started.status == "judging"
    assert get_in(judge_started, [:data, "phase"]) == "judge"
    assert get_in(judge_started, [:data, "agent_profile", "id"]) == "workflow-judge"
    assert get_in(judge_started, [:data, "agent_profile", "section"]) == "Piano"
    assert get_in(judge_started, [:data, "agent_profile", "instrument_name"]) == "Piano"

    assert eventually(fn ->
             Events.list(100)
             |> Enum.any?(&(&1.type == "issue.execution.completed" and &1.stage == "judge"))
           end)

    completed =
      Events.list(100)
      |> Enum.find(&(&1.type == "issue.execution.completed" and &1.stage == "judge"))

    assert get_in(completed, [:data, "phase"]) == "judge"
    assert get_in(completed, [:data, "agent_profile", "id"]) == "workflow-judge"
    assert get_in(completed, [:data, "judge_verdict", "verdict"]) == "pass"

    verdict =
      Events.list(100)
      |> Enum.find(&(&1.type == "issue.judge.verdict" and &1.stage == "judge"))

    assert verdict.status == "approved"
    assert get_in(verdict, [:data, "verdict"]) == "pass"
    assert get_in(verdict, [:data, "path"]) =~ ".symphony/judge-verdict.json"

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)
             snap.counts.running == 0 and snap.counts.retrying == 0 and snap.counts.completed == 1
           end)
  end

  test "judge refinement verdict starts refiner then re-judges and completes", %{dir: dir} do
    issue = issue("poll-refine", "TER-REFINE", "Refine judged output")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])

    Application.put_env(:symphony_elixir, :test_judge_verdict_sequence, [
      %{
        verdict: "needs_refinement",
        summary: "Needs a scoped fix",
        findings: [
          %{
            severity: "blocking",
            message: "missing validation evidence",
            evidence: "mix test was not reported"
          }
        ],
        evidence: ["test first judge"]
      },
      "pass"
    ])

    ensure_builder_judge_and_refiner_profiles()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config_with_refiner(max_attempts: 1)
      )

    Orchestrator.refresh(pid)

    assert eventually(
             fn ->
               snap = Orchestrator.snapshot(pid)

               snap.counts.running == 0 and snap.counts.retrying == 0 and
                 snap.counts.completed == 1
             end,
             80
           )

    events = Events.list(200)

    assert Enum.count(events, &(&1.type == "issue.stage.started" and &1.stage == "judge")) == 2

    refiner_started =
      Enum.find(events, &(&1.type == "issue.stage.started" and &1.stage == "refiner"))

    assert refiner_started.status == "refining"
    assert get_in(refiner_started, [:data, "phase"]) == "refiner"
    assert get_in(refiner_started, [:data, "agent_profile", "id"]) == "workflow-refiner"
    assert get_in(refiner_started, [:data, "refiner_attempt"]) == 1
    assert get_in(refiner_started, [:data, "refiner_max_attempts"]) == 1
    assert get_in(refiner_started, [:data, "judge_verdict", "verdict"]) == "needs_refinement"

    assert Enum.any?(events, &(&1.type == "issue.stage.completed" and &1.stage == "refiner"))

    refiner_execution_completions =
      Enum.filter(events, &(&1.type == "issue.execution.completed" and &1.stage == "refiner"))

    assert refiner_execution_completions == []

    verdicts = Enum.filter(events, &(&1.type == "issue.judge.verdict"))
    assert Enum.map(verdicts, &get_in(&1, [:data, "verdict"])) == ["needs_refinement", "pass"]
  end

  test "missing judge verdict blocks instead of completing", %{dir: dir} do
    issue = issue("poll-missing-verdict", "TER-NO-VERDICT", "Require verdict artifact")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    Application.put_env(:symphony_elixir, :test_judge_verdict_sequence, [:missing])
    ensure_builder_and_judge_profiles()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config_with_judge()
      )

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             blocked? = blocked_event?(issue, "judge")

             snap = Orchestrator.snapshot(pid)

             blocked? and snap.counts.running == 0 and snap.counts.retrying == 1 and
               snap.counts.completed == 0
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.counts.running == 0
    assert snap.counts.retrying == 1
    assert snap.counts.completed == 0
    assert [%{phase: "judge", reason: :missing_judge_verdict}] = snap.retrying

    blocked = blocked_event(issue, "judge")

    assert blocked.message =~ "Judge verdict artifact is missing"
    assert get_in(blocked, [:data, "reason"]) == "missing_judge_verdict"
    assert get_in(blocked, [:data, "verdict_path"]) =~ ".symphony/judge-verdict.json"
  end

  test "invalid judge verdict blocks instead of completing", %{dir: dir} do
    issue = issue("poll-invalid-verdict", "TER-BAD-VERDICT", "Reject bad verdict")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])

    Application.put_env(:symphony_elixir, :test_judge_verdict_sequence, [
      {:invalid, ~s({"verdict":"maybe","summary":"not a supported verdict"})}
    ])

    ensure_builder_and_judge_profiles()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config_with_judge()
      )

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)
             snap.counts.running == 0 and snap.counts.retrying == 1 and snap.counts.completed == 0
           end)

    blocked = blocked_event(issue, "judge")

    assert blocked.status == "blocked"
    assert blocked.message =~ "not supported"
    assert get_in(blocked, [:data, "reason"]) == "invalid_judge_verdict"
  end

  test "evidence-free judge pass verdict blocks instead of approving", %{dir: dir} do
    issue = issue("poll-bare-pass", "TER-BARE-PASS", "Reject bare judge approval")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])

    Application.put_env(:symphony_elixir, :test_judge_verdict_sequence, [
      %{verdict: "pass", summary: "Looks fine", findings: [], evidence: []}
    ])

    ensure_builder_and_judge_profiles()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config_with_judge()
      )

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)
             snap.counts.running == 0 and snap.counts.retrying == 1 and snap.counts.completed == 0
           end)

    blocked = blocked_event(issue, "judge")

    assert blocked.status == "blocked"
    assert blocked.message =~ "evidence is required"
    assert get_in(blocked, [:data, "reason"]) == "invalid_judge_verdict"
  end

  test "missing refiner profile blocks when judge requests refinement", %{dir: dir} do
    issue = issue("poll-missing-refiner", "TER-NO-REFINER", "Require real refiner")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    Application.put_env(:symphony_elixir, :test_judge_verdict_sequence, ["needs_refinement"])
    ensure_builder_and_judge_profiles()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config_with_judge()
      )

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             blocked? = blocked_event?(issue, "refiner")

             snap = Orchestrator.snapshot(pid)

             blocked? and snap.counts.running == 0 and snap.counts.retrying == 1 and
               snap.counts.completed == 0
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.counts.running == 0
    assert snap.counts.retrying == 1
    assert snap.counts.completed == 0
    assert [%{phase: "refiner", reason: :agent_profile_missing}] = snap.retrying

    blocked = blocked_event(issue, "refiner")

    assert blocked.message =~ "Workflow refiner profile is not configured"
    assert get_in(blocked, [:data, "verdict"]) == "needs_refinement"
  end

  test "refiner max attempts are bounded", %{dir: dir} do
    issue = issue("poll-refiner-max", "TER-REFINER-MAX", "Stop infinite refinement")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])

    Application.put_env(:symphony_elixir, :test_judge_verdict_sequence, [
      "needs_refinement",
      "needs_refinement"
    ])

    ensure_builder_judge_and_refiner_profiles()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config_with_refiner(max_attempts: 1)
      )

    Orchestrator.refresh(pid)

    assert eventually(
             fn ->
               snap = Orchestrator.snapshot(pid)
               blocked? = blocked_event?(issue, "refiner")

               blocked? and snap.counts.running == 0 and snap.counts.retrying == 1 and
                 snap.counts.completed == 0
             end,
             80
           )

    events = issue_events(issue, 200)
    assert Enum.count(events, &(&1.type == "issue.stage.started" and &1.stage == "refiner")) == 1
    assert Enum.count(events, &(&1.type == "issue.stage.started" and &1.stage == "judge")) == 2

    blocked =
      Enum.find(events, &(&1.type == "issue.stage.blocked" and &1.stage == "refiner"))

    assert blocked.message =~ "Refiner max attempts exhausted"
    assert get_in(blocked, [:data, "reason"]) == "refiner_attempts_exhausted"
    assert get_in(blocked, [:data, "refiner_attempt"]) == 1
    assert get_in(blocked, [:data, "refiner_max_attempts"]) == 1
  end

  test "explicit judge config without profile blocks after builder", %{dir: dir} do
    issue = issue("poll-blank-judge", "TER-BLANK-JUDGE", "Block malformed judge")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    ensure_builder_profile()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config:
          workflow_config()
          |> Map.put("judge", %{"rubric" => ["tests_pass"]})
      )

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             blocked? = blocked_event?(issue, "judge")

             snap = Orchestrator.snapshot(pid)

             blocked? and snap.counts.running == 0 and snap.counts.retrying == 1 and
               snap.counts.completed == 0
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.counts.running == 0
    assert snap.counts.retrying == 1
    assert snap.counts.completed == 0

    blocked = blocked_event(issue, "judge")

    assert blocked.status == "blocked"
    assert blocked.message =~ "Workflow judge profile is not configured"
    assert get_in(blocked, [:data, "reason"]) == "agent_profile_missing"
  end

  test "missing configured judge profile blocks after builder instead of completing", %{dir: dir} do
    issue = issue("poll-missing-judge", "TER-NO-JUDGE", "Block missing judge")
    missing_profile = "missing-judge-#{System.unique_integer([:positive])}"
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    ensure_builder_profile()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config:
          workflow_config()
          |> Map.put("judge", %{
            "profile" => missing_profile,
            "rubric" => ["tests_pass"]
          })
      )

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             blocked? = blocked_event?(issue, "judge")

             snap = Orchestrator.snapshot(pid)

             blocked? and snap.counts.running == 0 and snap.counts.retrying == 1 and
               snap.counts.completed == 0
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.counts.running == 0
    assert snap.counts.retrying == 1
    assert snap.counts.completed == 0
    assert [%{issue_identifier: "TER-NO-JUDGE"}] = snap.retrying

    blocked = blocked_event(issue, "judge")

    assert blocked.status == "blocked"
    assert blocked.message =~ "#{missing_profile} is not configured"
    assert get_in(blocked, [:data, "reason"]) == "agent_profile_missing"
    assert get_in(blocked, [:data, "phase"]) == "judge"
  end

  test "disabled workflow-local judge profile blocks after builder", %{dir: dir} do
    issue = issue("poll-disabled-local-judge", "TER-DISABLED-JUDGE", "Block disabled local judge")
    judge_profile = "workflow-local-judge-#{System.unique_integer([:positive])}"
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    ensure_builder_profile()

    config =
      workflow_config()
      |> Map.put("judge", %{"profile" => judge_profile, "rubric" => ["tests_pass"]})
      |> append_stage_agent(%{
        "profile" => judge_profile,
        "name" => "Disabled Local Judge",
        "role" => "Judge",
        "enabled" => false,
        "section" => "Piano",
        "instrument" => "Piano"
      })

    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0, workflow_config: config)

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             blocked? = blocked_event?(issue, "judge")
             snap = Orchestrator.snapshot(pid)

             blocked? and snap.counts.running == 0 and snap.counts.retrying == 1 and
               snap.counts.completed == 0
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.counts.running == 0
    assert snap.counts.retrying == 1
    assert snap.counts.completed == 0

    blocked = blocked_event(issue, "judge")

    assert blocked.status == "blocked"
    assert blocked.message =~ "#{judge_profile} is disabled"
    assert get_in(blocked, [:data, "reason"]) == "agent_profile_disabled"
  end

  test "disabled workflow-local refiner profile blocks refinement", %{dir: dir} do
    issue =
      issue("poll-disabled-local-refiner", "TER-DISABLED-REFINER", "Block disabled local refiner")

    refiner_profile = "workflow-local-refiner-#{System.unique_integer([:positive])}"
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    Application.put_env(:symphony_elixir, :test_judge_verdict_sequence, ["needs_refinement"])
    ensure_builder_and_judge_profiles()

    config =
      workflow_config_with_judge()
      |> Map.put("refiner", %{
        "profile" => refiner_profile,
        "max_attempts" => 1,
        "strategy" => "fix_judge_findings"
      })
      |> append_stage_agent(%{
        "profile" => refiner_profile,
        "name" => "Disabled Local Refiner",
        "role" => "Refiner",
        "enabled" => false,
        "section" => "Brass",
        "instrument" => "French Horn"
      })

    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0, workflow_config: config)

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             blocked? = blocked_event?(issue, "refiner")
             snap = Orchestrator.snapshot(pid)

             blocked? and snap.counts.running == 0 and snap.counts.retrying == 1 and
               snap.counts.completed == 0
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.counts.running == 0
    assert snap.counts.retrying == 1
    assert snap.counts.completed == 0

    blocked = blocked_event(issue, "refiner")

    assert blocked.status == "blocked"
    assert blocked.message =~ "#{refiner_profile} is disabled"
    assert get_in(blocked, [:data, "reason"]) == "agent_profile_disabled"
    assert get_in(blocked, [:data, "verdict"]) == "needs_refinement"
  end

  test "disabled named builder profile blocks dispatch instead of falling back", %{dir: dir} do
    issue = issue("poll-disabled", "TER-DISABLED", "Respect disabled profile")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    ensure_disabled_builder_profile()
    on_exit(fn -> ensure_builder_profile() end)

    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0)

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             Events.list(50)
             |> Enum.any?(&(&1.type == "issue.dispatch.blocked"))
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.counts.running == 0
    assert snap.counts.retrying == 0

    blocked = Events.list(50) |> Enum.find(&(&1.type == "issue.dispatch.blocked"))
    assert blocked.status == "blocked"
    assert blocked.message =~ "workflow-builder is disabled"
    assert get_in(blocked, [:data, "reason"]) == "agent_profile_disabled"
  end

  test "missing named builder profile blocks dispatch instead of inventing an agent", %{dir: dir} do
    issue = issue("poll-missing-profile", "TER-MISSING", "Respect missing profile")
    missing_profile = "missing-builder-#{System.unique_integer([:positive])}"
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: %{"builder" => %{"profile" => missing_profile}, "stage_agents" => []}
      )

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             Events.list(50)
             |> Enum.any?(&(&1.type == "issue.dispatch.blocked"))
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.counts.running == 0
    assert snap.counts.retrying == 0

    blocked = Events.list(50) |> Enum.find(&(&1.type == "issue.dispatch.blocked"))
    assert blocked.status == "blocked"
    assert blocked.message =~ "#{missing_profile} is not configured"
    assert get_in(blocked, [:data, "reason"]) == "agent_profile_missing"
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

  test "agent zero selection blocks dispatch until adapter is wired", %{dir: dir} do
    issue = issue("poll-a0", "TER-A0", "Do not silently fall back")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    Application.put_env(:symphony_elixir, :orchestration_provider, "agent_zero")

    {:ok, pid} = start_orchestrator(dir, poll_interval_ms: 0)

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             types = Events.list(50) |> Enum.map(& &1.type)
             "issue.dispatch.blocked" in types
           end)

    snap = Orchestrator.snapshot(pid)
    assert snap.polling.last_poll_count == 0
    assert snap.counts.running == 0
    assert snap.counts.retrying == 0
  end

  test "reload_config updates idle runtime settings", %{dir: dir} do
    ensure_builder_profile()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config()
      )

    {:ok, config} =
      Symphony.Config.from_workflow(Path.join(dir, "WORKFLOW.md"), %Workflow{
        config:
          workflow_config()
          |> Map.put("polling", %{"interval_ms" => 125})
          |> Map.put("agent", %{"max_concurrent_agents" => 2}),
        prompt_template: "Reloaded {{ issue.identifier }}"
      })

    assert {:ok, snap} = Orchestrator.reload_config(config, pid)
    assert snap.polling.interval_ms == 125

    reload_event =
      Events.list(50)
      |> Enum.find(&(&1.type == "workflow.reload.completed"))

    assert reload_event.status == "completed"
    assert get_in(reload_event, [:data, "poll_interval_ms"]) == 125
    assert get_in(reload_event, [:data, "max_concurrent_agents"]) == 2
  end

  test "reload_config blocks while runs are active", %{dir: dir} do
    issue = issue("poll-reload-active", "TER-RELOAD-ACTIVE", "Block active reload")
    Application.put_env(:symphony_elixir, :test_linear_issues, [issue])
    ensure_builder_profile()

    {:ok, pid} =
      start_orchestrator(dir,
        poll_interval_ms: 0,
        workflow_config: workflow_config()
      )

    Orchestrator.refresh(pid)

    assert eventually(fn ->
             snap = Orchestrator.snapshot(pid)
             snap.counts.running == 1
           end)

    {:ok, config} =
      Symphony.Config.from_workflow(Path.join(dir, "WORKFLOW.md"), %Workflow{
        config:
          workflow_config()
          |> Map.put("polling", %{"interval_ms" => 125}),
        prompt_template: "Reloaded {{ issue.identifier }}"
      })

    assert {:error, :active_runs, message, %{running: 1}} =
             Orchestrator.reload_config(config, pid)

    assert message =~ "blocked while agent runs are active"
  end

  defp start_orchestrator(dir, opts) do
    name = :"poll_orchestrator_#{System.unique_integer([:positive])}"

    config = %Config{
      workflow_path: Path.join(dir, "WORKFLOW.md"),
      workflow_dir: dir,
      workflow: %Workflow{
        config: Keyword.get(opts, :workflow_config, workflow_config()),
        prompt_template: "Work on {{ issue.identifier }}: {{ issue.title }}"
      },
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

  defp workflow_config do
    %{
      "builder" => %{"profile" => "workflow-builder"},
      "stage_agents" => [
        %{
          "profile" => "workflow-builder",
          "name" => "Codex Builder",
          "role" => "Builder",
          "profile_key" => "workflow-builder",
          "section" => "Strings",
          "instrument" => "Violin",
          "capabilities" => ["implementation", "codex"],
          "music" => %{
            "motif" => "Movement I / Build",
            "section" => "Strings",
            "instrument" => "Violin"
          },
          "stage" => %{"section" => "strings", "seat" => "front-center"}
        }
      ]
    }
  end

  defp workflow_config_with_conductor do
    workflow_config()
    |> Map.put("generator", %{
      "profile" => "workflow-generator",
      "instructions" => "Turn the manual movement into a bounded score."
    })
    |> Map.update!("stage_agents", fn agents ->
      [
        %{
          "profile" => "workflow-generator",
          "name" => "Workflow Conductor",
          "role" => "Generator",
          "profile_key" => "workflow-generator",
          "section" => "Woodwinds",
          "instrument" => "Clarinet",
          "capabilities" => ["workflow-generation", "planning"],
          "music" => %{
            "motif" => "Overture / Conductor Intake",
            "section" => "Woodwinds",
            "instrument" => "Clarinet"
          },
          "stage" => %{"section" => "woodwinds", "seat" => "front-left"}
        }
        | agents
      ]
    end)
  end

  defp workflow_config_with_judge do
    workflow_config()
    |> Map.put("judge", %{
      "profile" => "workflow-judge",
      "rubric" => [
        "tests_pass",
        "implementation_matches_issue",
        "no_unrequested_file_changes"
      ],
      "pass_threshold" => 0.8
    })
    |> Map.update!("stage_agents", fn agents ->
      agents ++
        [
          %{
            "profile" => "workflow-judge",
            "name" => "Codex Judge",
            "role" => "Judge",
            "profile_key" => "workflow-judge",
            "section" => "Piano",
            "instrument" => "Piano",
            "capabilities" => ["review", "validation"],
            "music" => %{
              "motif" => "Movement II / Judge",
              "section" => "Piano",
              "instrument" => "Piano"
            },
            "stage" => %{"section" => "piano", "seat" => "center"}
          }
        ]
    end)
  end

  defp workflow_config_with_refiner(opts) do
    max_attempts = Keyword.get(opts, :max_attempts, 1)

    workflow_config_with_judge()
    |> Map.put("refiner", %{
      "profile" => "workflow-refiner",
      "max_attempts" => max_attempts,
      "strategy" => "fix_judge_findings"
    })
    |> Map.update!("stage_agents", fn agents ->
      agents ++
        [
          %{
            "profile" => "workflow-refiner",
            "name" => "Codex Refiner",
            "role" => "Refiner",
            "profile_key" => "workflow-refiner",
            "section" => "Brass",
            "instrument" => "French Horn",
            "capabilities" => ["refinement", "review-fixes"],
            "music" => %{
              "motif" => "Movement III / Refine",
              "section" => "Brass",
              "instrument" => "French Horn"
            },
            "stage" => %{"section" => "brass", "seat" => "back-right"}
          }
        ]
    end)
  end

  defp append_stage_agent(config, agent),
    do: Map.update(config, "stage_agents", [agent], &(&1 ++ [agent]))

  defp ensure_builder_profile do
    {:ok, _} =
      Symphony.AgentProfileRegistry.ensure_many([
        %{
          "id" => "workflow-builder",
          "name" => "Codex Builder",
          "role" => "Builder",
          "profile_key" => "workflow-builder",
          "section" => "Strings",
          "instrument_name" => "Violin",
          "enabled" => true,
          "capabilities" => ["implementation", "codex"]
        }
      ])
  end

  defp ensure_conductor_and_builder_profiles do
    {:ok, _} =
      Symphony.AgentProfileRegistry.ensure_many([
        %{
          "id" => "workflow-generator",
          "name" => "Workflow Conductor",
          "role" => "Generator",
          "profile_key" => "workflow-generator",
          "section" => "Woodwinds",
          "instrument_name" => "Clarinet",
          "enabled" => true,
          "capabilities" => ["workflow-generation", "planning"]
        },
        %{
          "id" => "workflow-builder",
          "name" => "Codex Builder",
          "role" => "Builder",
          "profile_key" => "workflow-builder",
          "section" => "Strings",
          "instrument_name" => "Violin",
          "enabled" => true,
          "capabilities" => ["implementation", "codex"]
        }
      ])
  end

  defp ensure_builder_and_judge_profiles do
    {:ok, _} =
      Symphony.AgentProfileRegistry.ensure_many([
        %{
          "id" => "workflow-builder",
          "name" => "Codex Builder",
          "role" => "Builder",
          "profile_key" => "workflow-builder",
          "section" => "Strings",
          "instrument_name" => "Violin",
          "enabled" => true,
          "capabilities" => ["implementation", "codex"]
        },
        %{
          "id" => "workflow-judge",
          "name" => "Codex Judge",
          "role" => "Judge",
          "profile_key" => "workflow-judge",
          "section" => "Piano",
          "instrument_name" => "Piano",
          "enabled" => true,
          "capabilities" => ["review", "validation", "codex"],
          "music" => %{
            "motif" => "Movement II / Judge",
            "section" => "Piano",
            "instrument" => "Piano"
          }
        }
      ])
  end

  defp ensure_builder_judge_and_refiner_profiles do
    {:ok, _} =
      Symphony.AgentProfileRegistry.ensure_many([
        %{
          "id" => "workflow-builder",
          "name" => "Codex Builder",
          "role" => "Builder",
          "profile_key" => "workflow-builder",
          "section" => "Strings",
          "instrument_name" => "Violin",
          "enabled" => true,
          "capabilities" => ["implementation", "codex"]
        },
        %{
          "id" => "workflow-judge",
          "name" => "Codex Judge",
          "role" => "Judge",
          "profile_key" => "workflow-judge",
          "section" => "Piano",
          "instrument_name" => "Piano",
          "enabled" => true,
          "capabilities" => ["review", "validation", "codex"],
          "music" => %{
            "motif" => "Movement II / Judge",
            "section" => "Piano",
            "instrument" => "Piano"
          }
        },
        %{
          "id" => "workflow-refiner",
          "name" => "Codex Refiner",
          "role" => "Refiner",
          "profile_key" => "workflow-refiner",
          "section" => "Brass",
          "instrument_name" => "French Horn",
          "enabled" => true,
          "capabilities" => ["refinement", "review-fixes", "codex"],
          "music" => %{
            "motif" => "Movement III / Refine",
            "section" => "Brass",
            "instrument" => "French Horn"
          }
        }
      ])
  end

  defp ensure_disabled_builder_profile do
    {:ok, _} =
      Symphony.AgentProfileRegistry.ensure_many([
        %{
          "id" => "workflow-builder",
          "name" => "Codex Builder",
          "role" => "Builder",
          "profile_key" => "workflow-builder",
          "section" => "Strings",
          "instrument_name" => "Violin",
          "enabled" => false,
          "capabilities" => ["implementation", "codex"]
        }
      ])
  end

  defp issue(id, identifier, title),
    do: %Issue{id: id, identifier: identifier, title: title, state: "Todo"}

  defp issue_events(issue, limit),
    do: Events.list(limit) |> Enum.filter(&event_for_issue?(&1, issue))

  defp blocked_event?(issue, stage),
    do: Enum.any?(issue_events(issue, 100), &stage_blocked?(&1, stage))

  defp blocked_event(issue, stage),
    do: Enum.find(issue_events(issue, 100), &stage_blocked?(&1, stage))

  defp stage_blocked?(event, stage),
    do: event.type == "issue.stage.blocked" and event.stage == stage

  defp event_for_issue?(event, issue),
    do:
      Map.get(event, :issue_id) == issue.id or
        Map.get(event, :issue_identifier) == issue.identifier

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
