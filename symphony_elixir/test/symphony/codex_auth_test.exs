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
      if [ "$1" = "login" ] && [ "$2" = "status" ]; then
        echo "Logged in using ChatGPT as user@example.test bearer=secret-token"
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
    assert status.auth_phase == "authenticated"
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
    assert status.auth_phase == "cli_missing"
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
      if [ "$1" = "login" ] && [ "$2" = "status" ]; then
        echo "Logged in using ChatGPT"
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
    assert payload.state == "authenticated"
    assert payload.auth_phase == "authenticated"
    assert payload.login_command == "#{cli} login --device-auth"
    assert payload.output =~ "[REDACTED_URL]"
    assert File.read!(args_path) == "login --device-auth\n"
    assert payload.status.cli_available == true
  end

  test "login start reports device authorization phase before auth completes", %{dir: dir} do
    cli =
      write_cli!(dir, "codex-login-device-phase", """
      #!/bin/sh
      if [ "$1" = "--version" ]; then
        echo "codex-cli 9.9.9"
        exit 0
      fi
      if [ "$1" = "login" ] && [ "$2" = "--device-auth" ]; then
        echo "Device auth started at https://example.test/?code=secret"
        exit 0
      fi
      if [ "$1" = "login" ] && [ "$2" = "status" ]; then
        echo "Not logged in"
        exit 1
      fi
      exit 1
      """)

    assert {:ok, payload} = Auth.login_start(%Config{codex_command: "#{cli} app-server"})

    assert payload.ok
    assert payload.state == "device_authorization_started"
    assert payload.auth_phase == "device_authorization_started"
    assert payload.status.state == "signed_out"
    assert payload.output =~ "[REDACTED_URL]"
  end

  test "status parses quoted command paths and preserves global codex flags", %{dir: dir} do
    bin_dir = Path.join(dir, "Codex CLI")
    File.mkdir_p!(bin_dir)
    calls_path = Path.join(dir, "calls.txt")

    cli =
      write_cli!(bin_dir, "codex-profile", """
      #!/bin/sh
      printf "%s\\n" "$*" >> "#{calls_path}"
      if [ "$1" = "--profile" ] && [ "$2" = "work" ] && [ "$3" = "--version" ]; then
        echo "codex-cli 9.9.9"
        exit 0
      fi
      if [ "$1" = "--profile" ] && [ "$2" = "work" ] && [ "$3" = "login" ] && [ "$4" = "status" ]; then
        echo "Logged in using ChatGPT as profile@example.test"
        exit 0
      fi
      exit 1
      """)

    command = "'#{cli}' --profile work app-server --port 4700"
    status = Auth.status(%Config{codex_command: command})

    assert status.available == true
    assert status.authenticated == true
    assert status.account_label == "profile@example.test"
    assert status.login_command == "'#{cli}' --profile work login --device-auth"

    calls = File.read!(calls_path)
    assert calls =~ "--profile work --version"
    assert calls =~ "--profile work login status"
    refute calls =~ "app-server"
    refute calls =~ "--port 4700"
  end

  test "login start preserves global flags and strips app-server runtime args", %{dir: dir} do
    bin_dir = Path.join(dir, "Codex CLI")
    File.mkdir_p!(bin_dir)
    args_path = Path.join(dir, "args.txt")

    cli =
      write_cli!(bin_dir, "codex-login-profile", """
      #!/bin/sh
      if [ "$1" = "--profile" ] && [ "$2" = "work" ] && [ "$3" = "--version" ]; then
        echo "codex-cli 9.9.9"
        exit 0
      fi
      if [ "$1" = "--profile" ] && [ "$2" = "work" ] && [ "$3" = "login" ] && [ "$4" = "--device-auth" ]; then
        printf "%s\\n" "$*" > "#{args_path}"
        echo "Device auth started at https://example.test/?code=secret"
        exit 0
      fi
      if [ "$1" = "--profile" ] && [ "$2" = "work" ] && [ "$3" = "login" ] && [ "$4" = "status" ]; then
        echo "Logged in using ChatGPT"
        exit 0
      fi
      exit 1
      """)

    command = "'#{cli}' --profile work app-server --port 4700"
    assert {:ok, payload} = Auth.login_start(%Config{codex_command: command})

    assert payload.ok
    assert payload.state == "authenticated"
    assert payload.auth_phase == "authenticated"
    assert payload.login_command == "'#{cli}' --profile work login --device-auth"
    assert File.read!(args_path) == "--profile work login --device-auth\n"
    refute payload.login_command =~ "app-server"
    refute payload.login_command =~ "--port"
  end

  defp write_cli!(dir, name, body) do
    path = Path.join(dir, name)
    File.write!(path, String.replace(String.trim_leading(body), ~r/\n\s{4}/, "\n"))
    File.chmod!(path, 0o755)
    path
  end
end
