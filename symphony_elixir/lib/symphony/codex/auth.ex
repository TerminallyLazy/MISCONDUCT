defmodule Symphony.Codex.Auth do
  @moduledoc """
  Sanitized Codex CLI auth/status helper.

  Symphony does not collect or store ChatGPT/Codex OAuth tokens. The Codex CLI owns
  its OAuth/session files. This module only detects CLI availability, starts CLI
  login/logout commands when available, and returns redacted status metadata.
  """

  @default_timeout 8_000

  def status(config \\ nil) do
    command = codex_command(config)
    exe = executable(command)
    now = DateTime.utc_now()

    cond do
      is_nil(exe) ->
        %{
          ok: true,
          connected: false,
          authenticated: false,
          state: "cli_missing",
          cli_available: false,
          configured_command: command,
          executable: nil,
          cli_version: nil,
          account_label: nil,
          auth_source: "codex_cli",
          last_checked_at: now,
          message: "Codex CLI executable was not found on PATH. Install Codex CLI, then sign in."
        }

      true ->
        version = version(exe)
        auth = auth_probe(exe)

        %{
          ok: true,
          connected: auth.connected,
          authenticated: auth.connected,
          state: auth.state,
          cli_available: true,
          configured_command: command,
          executable: exe,
          cli_version: version,
          account_label: auth.account_label,
          auth_source: "codex_cli",
          last_checked_at: now,
          message: auth.message,
          supports_login: true,
          supports_logout: true,
          token_storage: "owned_by_codex_cli"
        }
    end
  end

  def login_start(config \\ nil) do
    command = codex_command(config)

    case executable(command) do
      nil ->
        {:error, :codex_cli_missing}

      exe ->
        case run_cli(exe, ["login"], 120_000) do
          {0, out} ->
            {:ok,
             %{
               ok: true,
               state: "login_completed_or_pending",
               auth_source: "codex_cli",
               message:
                 "Codex CLI login command completed. Click Check status to verify the account.",
               output: redact(out),
               status: status(config)
             }}

          {code, out} ->
            {:ok,
             %{
               ok: true,
               state: "manual_required",
               auth_source: "codex_cli",
               message:
                 "Codex CLI login could not be completed non-interactively. Run `codex login` in the same user environment, then click Check status.",
               exit_status: code,
               output: redact(out),
               status: status(config)
             }}
        end
    end
  end

  def check(config \\ nil), do: {:ok, status(config)}

  def logout(config \\ nil) do
    command = codex_command(config)

    case executable(command) do
      nil ->
        {:error, :codex_cli_missing}

      exe ->
        {code, out} = run_cli(exe, ["logout"], 30_000)

        {:ok,
         %{
           ok: code == 0,
           state: if(code == 0, do: "logged_out", else: "logout_failed"),
           message:
             if(code == 0,
               do: "Codex CLI logout completed.",
               else: "Codex CLI logout command failed."
             ),
           exit_status: code,
           output: redact(out),
           status: status(config)
         }}
    end
  end

  def env do
    # Reserved for future isolated Codex CLI auth homes. Do not inject secrets here.
    []
  end

  def redact(text) when is_binary(text) do
    text
    |> String.replace(
      ~r/(access_token|refresh_token|id_token|authorization|bearer)\s*[:=]\s*[^\s]+/i,
      "\\1=[REDACTED]"
    )
    |> String.replace(~r/(code=)[^\s&]+/i, "\\1[REDACTED]")
    |> String.replace(~r/(token=)[^\s&]+/i, "\\1[REDACTED]")
    |> String.replace(~r/https:\/\/[^\s]+/i, "[REDACTED_URL]")
    |> String.slice(0, 4_000)
  end

  def redact(other), do: inspect(other)

  defp codex_command(nil) do
    case Symphony.Config.load() do
      {:ok, cfg} -> codex_command(cfg)
      _ -> "codex"
    end
  end

  defp codex_command(config) do
    config
    |> Map.get(:codex_command, "codex")
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "codex"
      cmd -> cmd
    end
  end

  defp executable(command) do
    command
    |> String.split(~r/\s+/, parts: 2)
    |> hd()
    |> System.find_executable()
  end

  defp version(exe) do
    case run_cli(exe, ["--version"], @default_timeout) do
      {0, out} -> out |> redact() |> String.trim()
      {_code, out} -> out |> redact() |> String.trim()
    end
  end

  defp auth_probe(exe) do
    probes = [["auth", "status"], ["status"], ["whoami"]]

    Enum.reduce_while(probes, nil, fn args, _acc ->
      case run_cli(exe, args, @default_timeout) do
        {0, out} -> {:halt, classify_auth(out)}
        {_code, _out} -> {:cont, nil}
      end
    end) ||
      %{
        connected: false,
        state: "unknown",
        account_label: nil,
        message:
          "Codex CLI is installed, but no supported auth status command was detected. Use Sign in or run `codex login`, then test agent spawning."
      }
  end

  defp classify_auth(out) do
    redacted = redact(out)
    down = String.downcase(redacted)

    connected =
      String.contains?(down, "logged in") or String.contains?(down, "authenticated") or
        String.contains?(down, "signed in")

    %{
      connected: connected,
      state: if(connected, do: "authenticated", else: "not_authenticated"),
      account_label: extract_account(redacted),
      message: String.trim(redacted)
    }
  end

  defp extract_account(text) do
    Regex.run(~r/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i, text)
    |> case do
      [email | _] -> email
      _ -> nil
    end
  end

  defp run_cli(exe, args, timeout) do
    task =
      Task.async(fn ->
        try do
          {out, code} = System.cmd(exe, args, stderr_to_stdout: true, env: env())
          {code, out}
        rescue
          e -> {127, Exception.message(e)}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {124, "Codex CLI command timed out"}
    end
  end
end
