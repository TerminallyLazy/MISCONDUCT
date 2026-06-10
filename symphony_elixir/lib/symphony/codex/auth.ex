defmodule Symphony.Codex.Auth do
  @moduledoc """
  Sanitized Codex CLI auth/status helper.

  MISCONDUCT does not collect or store ChatGPT/Codex OAuth tokens. The Codex CLI owns
  its OAuth/session files. This module only detects CLI availability, starts CLI
  login/logout commands when available, and returns redacted status metadata.
  """

  @default_timeout 8_000

  def status(config \\ nil) do
    command = codex_command(config)
    spec = command_spec(command)
    exe = spec.executable
    now = DateTime.utc_now()
    login_command = manual_login_command(spec)

    cond do
      is_nil(exe) ->
        %{
          ok: true,
          available: false,
          connected: false,
          authenticated: false,
          state: "cli_missing",
          status: "cli_missing",
          auth_phase: "cli_missing",
          cli_available: false,
          command: command,
          configured_command: command,
          executable: nil,
          version: nil,
          cli_version: nil,
          account_label: nil,
          auth_source: "codex_cli",
          login_command: login_command,
          last_checked_at: now,
          message: "Codex CLI executable was not found on PATH. Install Codex CLI, then sign in."
        }

      true ->
        version = version(spec)
        auth = auth_probe(spec)

        %{
          ok: true,
          available: true,
          connected: auth.connected,
          authenticated: auth.connected,
          state: auth.state,
          status: auth.state,
          auth_phase: auth.state,
          cli_available: true,
          command: command,
          configured_command: command,
          executable: exe,
          version: version,
          cli_version: version,
          account_label: auth.account_label,
          auth_source: "codex_cli",
          login_command: login_command,
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
    spec = command_spec(command)

    case spec.executable do
      nil ->
        {:error, :codex_cli_missing}

      _exe ->
        login_command = manual_login_command(spec)

        case run_cli(spec, ["login", "--device-auth"], 12_000) do
          {0, out} ->
            current_status = status(config)

            phase =
              if current_status.authenticated,
                do: "authenticated",
                else: "device_authorization_started"

            {:ok,
             %{
               ok: true,
               state: phase,
               auth_phase: phase,
               auth_source: "codex_cli",
               login_command: login_command,
               message:
                 if(current_status.authenticated,
                   do: "Codex CLI login completed and the account is authenticated.",
                   else:
                     "Codex CLI device authorization started. Complete the browser flow, then click Check connection."
                 ),
               output: redact(out),
               status: current_status
             }}

          {code, out} ->
            {:ok,
             %{
               ok: true,
               state: "manual_login_required",
               auth_phase: "manual_login_required",
               auth_source: "codex_cli",
               login_command: login_command,
               message:
                 "Codex CLI login could not be completed from the desktop app. Run `#{login_command}` in the same user environment, then click Check status.",
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
    spec = command_spec(command)

    case spec.executable do
      nil ->
        {:error, :codex_cli_missing}

      _exe ->
        {code, out} = run_cli(spec, ["logout"], 30_000)

        {:ok,
         %{
           ok: code == 0,
           state: if(code == 0, do: "logged_out", else: "logout_failed"),
           auth_phase: if(code == 0, do: "signed_out", else: "logout_failed"),
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

  defp command_spec(command) do
    parts =
      command
      |> command_parts()
      |> case do
        [] -> ["codex"]
        parts -> parts
      end

    executable_name = hd(parts)
    args = tl(parts)

    %{
      executable_name: executable_name,
      executable: System.find_executable(executable_name),
      global_args: global_args(args)
    }
  end

  defp command_parts(command) do
    command
    |> OptionParser.split()
  rescue
    _ ->
      command
      |> String.split(~r/\s+/, trim: true)
  end

  defp global_args(args) do
    case Enum.split_while(args, &(&1 != "app-server")) do
      {global, ["app-server" | _runtime_args]} -> global
      {global, []} -> global
    end
  end

  defp manual_login_command(spec) do
    args = [spec.executable_name | spec.global_args ++ ["login", "--device-auth"]]

    args
    |> Enum.map(&shell_quote/1)
    |> Enum.join(" ")
  end

  defp shell_quote(value) do
    value = to_string(value)

    if String.match?(value, ~r"^[A-Za-z0-9_@%+=:,./-]+$") do
      value
    else
      "'" <> String.replace(value, "'", "'\\''") <> "'"
    end
  end

  defp version(spec) do
    [["--version"], ["version"], ["-V"]]
    |> Enum.reduce_while(nil, fn args, _acc ->
      case run_cli(spec, args, @default_timeout) do
        {0, out} ->
          text = out |> redact() |> String.trim()
          if text == "", do: {:cont, nil}, else: {:halt, text}

        {_code, out} ->
          text = out |> redact() |> String.trim()

          if String.contains?(String.downcase(text), "codex"),
            do: {:halt, text},
            else: {:cont, nil}
      end
    end) || "installed"
  end

  defp auth_probe(spec) do
    cli_probe(spec) || file_probe() ||
      %{
        connected: false,
        state: "auth_status_unverified",
        account_label: nil,
        message:
          "Codex CLI is installed, but MISCONDUCT could not verify the CLI session. If you already signed in, click Check connection after restarting the app; otherwise run `codex login`."
      }
  end

  defp cli_probe(spec) do
    probes = [["login", "status"], ["auth", "status"], ["status"], ["whoami"], ["account"]]

    Enum.reduce_while(probes, nil, fn args, fallback ->
      case run_cli(spec, args, @default_timeout) do
        {0, out} ->
          auth = classify_auth(out)

          cond do
            auth.connected -> {:halt, auth}
            auth.state != "auth_status_unverified" -> {:cont, auth}
            true -> {:cont, fallback}
          end

        {_code, out} ->
          auth = classify_auth(out)

          cond do
            auth.connected -> {:halt, auth}
            auth.state != "auth_status_unverified" -> {:cont, auth}
            true -> {:cont, fallback}
          end
      end
    end)
  end

  defp file_probe do
    auth_files()
    |> Enum.find_value(fn path ->
      case File.read(path) do
        {:ok, body} -> classify_auth_file(path, body)
        _ -> nil
      end
    end)
  end

  defp auth_files do
    home = System.user_home!()

    [
      Path.join([home, ".codex", "auth.json"]),
      Path.join([home, ".codex", "credentials.json"]),
      Path.join([home, ".codex", "codex.json"]),
      Path.join([home, ".config", "codex", "auth.json"]),
      Path.join([home, ".config", "codex", "credentials.json"]),
      Path.join([home, "Library", "Application Support", "codex", "auth.json"]),
      Path.join([home, "Library", "Application Support", "Codex", "auth.json"])
    ]
  rescue
    _ -> []
  end

  defp classify_auth_file(path, body) when is_binary(body) do
    down = String.downcase(body)

    tokenish =
      String.contains?(down, "access_token") or String.contains?(down, "refresh_token") or
        String.contains?(down, "id_token") or String.contains?(down, "account") or
        String.contains?(down, "chatgpt") or String.contains?(down, "openai")

    revoked =
      String.contains?(down, "revoked") or String.contains?(down, "invalidated") or
        String.contains?(down, "expired")

    if tokenish and not revoked do
      %{
        connected: true,
        state: "authenticated",
        account_label: extract_account(body),
        message:
          "Codex CLI session file detected at #{redact_path(path)}. Tokens remain owned by Codex CLI and are not exposed to MISCONDUCT."
      }
    else
      nil
    end
  end

  defp classify_auth_file(_path, _body), do: nil

  defp classify_auth(out) do
    redacted = redact(out)
    down = String.downcase(redacted)

    signed_out =
      String.contains?(down, "not logged in") or String.contains?(down, "not authenticated") or
        String.contains?(down, "not signed in") or String.contains?(down, "signed out") or
        String.contains?(down, "login required") or String.contains?(down, "no active session")

    device_auth =
      String.contains?(down, "device") and
        (String.contains?(down, "code") or String.contains?(down, "authorize"))

    connected =
      not signed_out and
        (String.contains?(down, "logged in") or String.contains?(down, "authenticated") or
           String.contains?(down, "signed in") or String.contains?(down, "already logged in") or
           String.contains?(down, "login successful") or String.contains?(down, "subscription") or
           String.contains?(down, "chatgpt"))

    state =
      cond do
        connected -> "authenticated"
        signed_out -> "signed_out"
        device_auth -> "device_authorization_required"
        true -> "auth_status_unverified"
      end

    %{
      connected: connected,
      state: state,
      account_label: extract_account(redacted),
      message:
        case String.trim(redacted) do
          "" -> "Codex CLI did not return recognizable auth status."
          message -> message
        end
    }
  end

  defp redact_path(path) do
    home = System.user_home!()
    path |> to_string() |> String.replace(home, "~")
  rescue
    _ -> to_string(path)
  end

  defp extract_account(text) do
    Regex.run(~r/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i, text)
    |> case do
      [email | _] -> email
      _ -> nil
    end
  end

  defp run_cli(spec, args, timeout) do
    task =
      Task.async(fn ->
        try do
          {out, code} =
            System.cmd(spec.executable, spec.global_args ++ args,
              stderr_to_stdout: true,
              env: env()
            )

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
