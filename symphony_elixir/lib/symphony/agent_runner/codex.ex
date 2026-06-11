defmodule Symphony.AgentRunner.Codex do
  @behaviour Symphony.AgentRunner
  @codex_exec_args [
    "exec",
    "-c",
    "approval_policy=\"never\"",
    "--sandbox",
    "workspace-write",
    "--skip-git-repo-check",
    "--color",
    "never"
  ]

  @impl true
  def run(run, workspace, config, orchestrator) do
    prompt = Map.get(run, :prompt) || run.last_message || ""
    command = String.trim(to_string(config.codex_command || ""))
    timeout_ms = max(to_int(config.codex_turn_timeout_ms, 3_600_000), 1)

    if command == "" do
      emit(orchestrator, run.issue_id, "startup_failed", %{message: "codex.command is empty"})
      {:error, :missing_codex_command}
    else
      execution_command = execution_command(command)

      emit(orchestrator, run.issue_id, "session_started", %{
        message: "Started subprocess: #{execution_command}",
        thread_id: run.issue_identifier || run.issue_id,
        turn_id: Integer.to_string(System.unique_integer([:positive]))
      })

      execution_command
      |> run_command(prompt, workspace.path, config, run)
      |> await_result(timeout_ms, run, orchestrator)
    end
  end

  defp run_command(command, prompt, cwd, config, run) do
    Task.async(fn ->
      nonce = System.unique_integer([:positive])
      stdin_path = Path.join(cwd, ".symphony-agent-stdin-#{nonce}.txt")
      stderr_path = Path.join(cwd, ".symphony-agent-stderr-#{nonce}.log")

      wrapped = "( #{command} ) <#{shell_quote(stdin_path)} 2>#{shell_quote(stderr_path)}"

      try do
        File.write!(stdin_path, prompt)

        {stdout, status} =
          System.cmd(shell_path(), ["-lc", wrapped],
            cd: cwd,
            env: env(config, run, cwd),
            stderr_to_stdout: false
          )

        stderr = read_file(stderr_path)
        {status, Symphony.Codex.Auth.redact(stdout), Symphony.Codex.Auth.redact(stderr)}
      after
        File.rm(stdin_path)
        File.rm(stderr_path)
      end
    end)
  end

  defp await_result(task, timeout_ms, run, orchestrator) do
    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, {0, stdout, stderr}} ->
        emit_stream(orchestrator, run.issue_id, "stdout", stdout)
        emit_stream(orchestrator, run.issue_id, "stderr", stderr)

        emit(orchestrator, run.issue_id, "turn_completed", %{
          message: "Subprocess completed successfully",
          stdout: stdout,
          stderr: stderr
        })

        :ok

      {:ok, {status, stdout, stderr}} ->
        emit_stream(orchestrator, run.issue_id, "stdout", stdout)
        emit_stream(orchestrator, run.issue_id, "stderr", stderr)
        msg = "Subprocess exited with status #{status}"

        emit(orchestrator, run.issue_id, "turn_failed", %{
          message: msg,
          stdout: stdout,
          stderr: stderr
        })

        {:error, {:exit_status, status}}

      nil ->
        msg = "Subprocess timed out after #{timeout_ms}ms"
        emit(orchestrator, run.issue_id, "turn_failed", %{message: msg})
        {:error, :timeout}
    end
  end

  defp emit_stream(_orchestrator, _issue_id, _event, ""), do: :ok

  defp emit_stream(orchestrator, issue_id, event, text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.each(fn line -> emit(orchestrator, issue_id, event, %{message: line}) end)
  end

  defp emit(orchestrator, issue_id, event, fields) do
    send(orchestrator, {:agent_event, issue_id, Map.put(fields, :event, event)})
  end

  defp env(config, run, cwd) do
    profile = run.agent_profile || %{}

    Symphony.Codex.Auth.env() ++
      [
        {"SYMPHONY_CODEX_COMMAND", to_string(config.codex_command || "")},
        {"SYMPHONY_CODEX_EXECUTION_COMMAND",
         execution_command(to_string(config.codex_command || ""))},
        {"SYMPHONY_ISSUE_ID", to_string(run.issue_id || "")},
        {"SYMPHONY_ISSUE_IDENTIFIER", to_string(run.issue_identifier || "")},
        {"SYMPHONY_WORKSPACE", cwd},
        {"SYMPHONY_RUN_PHASE", to_string(run.phase || "build")},
        {"SYMPHONY_AGENT_PROFILE_ID", profile_value(profile, :id)},
        {"SYMPHONY_AGENT_PROFILE_NAME", profile_value(profile, :name)},
        {"SYMPHONY_AGENT_PROFILE_ROLE", profile_value(profile, :role)},
        {"SYMPHONY_AGENT_PROFILE_SECTION", profile_value(profile, :section)},
        {"SYMPHONY_AGENT_PROFILE_INSTRUMENT", profile_value(profile, :instrument_name)},
        {"SYMPHONY_AGENT_PROFILE_STATUS", profile_value(profile, :status)},
        {"SYMPHONY_AGENT_RUNNER", "codex_subprocess"}
      ]
  end

  defp profile_value(profile, key) do
    value = Map.get(profile, key) || Map.get(profile, Atom.to_string(key))
    to_string(value || "")
  end

  defp execution_command(command) do
    command
    |> command_parts()
    |> case do
      [] ->
        command

      [executable | args] ->
        case Enum.split_while(args, &(&1 != "app-server")) do
          {global_args, ["app-server" | _runtime_args]} ->
            [executable | global_args ++ @codex_exec_args]
            |> Enum.map(&shell_quote/1)
            |> Enum.join(" ")

          _ ->
            command
        end
    end
  end

  defp command_parts(command) do
    OptionParser.split(command)
  rescue
    _ -> String.split(command, ~r/\s+/, trim: true)
  end

  defp shell_quote(value), do: "'" <> String.replace(to_string(value), "'", "'\\''") <> "'"
  defp shell_path, do: System.find_executable("bash") || System.find_executable("sh") || "/bin/sh"
  defp read_file(path), do: if(File.exists?(path), do: File.read!(path), else: "")
  defp to_int(v, _d) when is_integer(v), do: v

  defp to_int(v, d) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      _ -> d
    end
  end

  defp to_int(_, d), do: d
end
