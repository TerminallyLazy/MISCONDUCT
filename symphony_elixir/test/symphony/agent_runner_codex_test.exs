defmodule Symphony.AgentRunner.CodexTest do
  use ExUnit.Case, async: true

  alias Symphony.AgentRunner.Codex

  test "runs configured command in workspace with prompt on stdin and strict env" do
    dir = temp_dir!()
    run = %Symphony.Run{issue_id: "issue-1", issue_identifier: "LIN-1", prompt: "PROMPT BODY\n"}

    config = %Symphony.Config{
      codex_command:
        "cat > prompt.txt; echo env:$SYMPHONY_ISSUE_IDENTIFIER:$SYMPHONY_AGENT_RUNNER; pwd; echo err >&2",
      codex_turn_timeout_ms: 2_000
    }

    workspace = %Symphony.Workspace{path: dir}

    assert :ok = Codex.run(run, workspace, config, self())
    assert_receive {:agent_event, "issue-1", %{event: "session_started"}}

    assert_receive {:agent_event, "issue-1",
                    %{event: "stdout", message: "env:LIN-1:codex_subprocess"}}

    assert_receive {:agent_event, "issue-1", %{event: "stdout", message: ^dir}}
    assert_receive {:agent_event, "issue-1", %{event: "stderr", message: "err"}}

    assert_receive {:agent_event, "issue-1",
                    %{event: "turn_completed", stdout: stdout, stderr: stderr}}

    assert stdout =~ "env:LIN-1:codex_subprocess"
    assert stderr =~ "err"
    assert File.read!(Path.join(dir, "prompt.txt")) == "PROMPT BODY\n"
  end

  test "times out long-running command" do
    dir = temp_dir!()
    run = %Symphony.Run{issue_id: "issue-timeout", issue_identifier: "LIN-2", prompt: "x"}
    config = %Symphony.Config{codex_command: "sleep 2", codex_turn_timeout_ms: 50}
    workspace = %Symphony.Workspace{path: dir}

    assert {:error, :timeout} = Codex.run(run, workspace, config, self())
    assert_receive {:agent_event, "issue-timeout", %{event: "session_started"}}
    assert_receive {:agent_event, "issue-timeout", %{event: "turn_failed", message: message}}
    assert message =~ "timed out"
  end

  defp temp_dir! do
    dir = Path.join(System.tmp_dir!(), "symrunner_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
