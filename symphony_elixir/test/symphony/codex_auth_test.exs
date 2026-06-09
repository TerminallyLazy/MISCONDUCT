defmodule Symphony.Codex.AuthTest do
  use ExUnit.Case, async: true

  alias Symphony.{Codex.Auth, Config}

  setup do
    dir =
      Path.join(System.tmp_dir!(), "symphony-codex-auth-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir}
  end

  test "status exposes desktop-compatible fields without leaking tokens", %{dir: dir} do
    cli =
      write_cli!(dir, "codex-auth-status", """
      #!/bin/sh
      if [ "$1" = "--version" ]; then
        echo "codex-cli 9.9.9"
        exit 0
      fi
      if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
        echo "Logged in using ChatGPT as user@example.test bearer=secret-token"
        exit 0
      fi
      echo "unknown command: $*" >&2
      exit 1
      """)

    status = Auth.status(%Config{codex_command: "#{cli} app-server"})

    assert status.ok
    assert status.available == true
    assert status.cli_available == true
    assert status.connected == true
    assert status.authenticated == true
    assert status.state == "authenticated"
    assert status.status == "authenticated"
    assert status.command == "#{cli} app-server"
    assert status.configured_command == "#{cli} app-server"
    assert status.version == "codex-cli 9.9.9"
    assert status.cli_version == "codex-cli 9.9.9"
    assert status.login_command == "#{cli} login --device-auth"
    assert status.account_label == "user@example.test"
    assert status.message =~ "Logged in using ChatGPT"
    refute status.message =~ "secret-token"
  end

  test "missing CLI status preserves false booleans and login command" do
    command = "missing-codex-#{System.unique_integer([:positive])} app-server"

    status = Auth.status(%Config{codex_command: command})

    assert status.ok
    assert status.available == false
    assert status.cli_available == false
    assert status.connected == false
    assert status.authenticated == false
    assert status.state == "cli_missing"
    assert status.status == "cli_missing"
    assert status.command == command
    assert status.configured_command == command
    assert status.version == nil
    assert status.cli_version == nil
    assert status.login_command =~ "login --device-auth"
  end

  test "login start uses bounded device auth command", %{dir: dir} do
    args_path = Path.join(dir, "args.txt")

    cli =
      write_cli!(dir, "codex-login", """
      #!/bin/sh
      if [ "$1" = "--version" ]; then
        echo "codex-cli 9.9.9"
        exit 0
      fi
      if [ "$1" = "login" ] && [ "$2" = "--device-auth" ]; then
        printf "%s\\n" "$*" > "#{args_path}"
        echo "Device auth started at https://example.test/?code=secret"
        exit 0
      fi
      if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
        echo "Logged in using ChatGPT"
        exit 0
      fi
      exit 1
      """)

    assert {:ok, payload} = Auth.login_start(%Config{codex_command: "#{cli} app-server"})

    assert payload.ok
    assert payload.state == "login_completed_or_pending"
    assert payload.login_command == "#{cli} login --device-auth"
    assert payload.output =~ "[REDACTED_URL]"
    assert File.read!(args_path) == "login --device-auth\n"
    assert payload.status.cli_available == true
  end

  defp write_cli!(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, String.replace(String.trim_leading(body), ~r/\n\s{4}/, "\n"))
    File.chmod!(path, 0o755)
    path
  end
end
