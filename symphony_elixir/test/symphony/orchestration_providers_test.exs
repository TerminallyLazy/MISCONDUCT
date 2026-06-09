defmodule Symphony.Orchestration.ProvidersTest do
  use ExUnit.Case, async: false

  alias Symphony.{Config, Orchestration.Providers}

  setup do
    old_app_provider = Application.get_env(:symphony_elixir, :orchestration_provider)
    old_provider = System.get_env("SYMPHONY_ORCHESTRATION_PROVIDER")
    old_url = System.get_env("SYMPHONY_AGENT_ZERO_URL")
    old_command = System.get_env("SYMPHONY_AGENT_ZERO_COMMAND")

    on_exit(fn ->
      restore_app_env(:orchestration_provider, old_app_provider)
      restore_env("SYMPHONY_ORCHESTRATION_PROVIDER", old_provider)
      restore_env("SYMPHONY_AGENT_ZERO_URL", old_url)
      restore_env("SYMPHONY_AGENT_ZERO_COMMAND", old_command)
    end)

    :ok
  end

  test "direct codex is the default provider" do
    System.delete_env("SYMPHONY_ORCHESTRATION_PROVIDER")
    System.delete_env("SYMPHONY_AGENT_ZERO_URL")
    System.delete_env("SYMPHONY_AGENT_ZERO_COMMAND")

    status = Providers.status(%Config{codex_command: "codex app-server"})

    assert status.active_provider == "direct_codex"
    assert status.default_provider == "direct_codex"
    assert status.provider_contract == ["direct_codex", "agent_zero"]

    assert Enum.find(status.providers, &(&1.id == "direct_codex")).active
    refute Enum.find(status.providers, &(&1.id == "agent_zero")).available
  end

  test "agent zero selection stays explicit while adapter execution is pending" do
    System.put_env("SYMPHONY_ORCHESTRATION_PROVIDER", "agent_zero")
    System.put_env("SYMPHONY_AGENT_ZERO_URL", "http://127.0.0.1:55000")

    status = Providers.status(%Config{codex_command: "codex app-server"})
    agent_zero = Enum.find(status.providers, &(&1.id == "agent_zero"))

    assert status.active_provider == "agent_zero"
    assert status.status == "agent_zero_adapter_pending"
    assert agent_zero.active
    assert agent_zero.configured
    refute agent_zero.available
    refute agent_zero.implemented
    assert agent_zero.status == "adapter_pending"
    assert agent_zero.endpoint == "http://127.0.0.1:55000"
  end

  test "selecting direct codex sets the runtime provider override" do
    System.put_env("SYMPHONY_ORCHESTRATION_PROVIDER", "agent_zero")
    assert {:ok, status} = Providers.select("direct_codex", %Config{codex_command: "codex app-server"})

    assert status.active_provider == "direct_codex"
    assert Application.get_env(:symphony_elixir, :orchestration_provider) == "direct_codex"
  end

  test "selecting agent zero is blocked until the adapter is implemented" do
    System.put_env("SYMPHONY_AGENT_ZERO_URL", "http://127.0.0.1:55000")

    assert {:error, :agent_zero_adapter_pending, message, status} =
             Providers.select("agent_zero", %Config{codex_command: "codex app-server"})

    assert message =~ "adapter"
    assert status.active_provider == "direct_codex"
    refute Application.get_env(:symphony_elixir, :orchestration_provider)
  end

  test "agent zero active provider is not execution-ready while adapter is pending" do
    System.put_env("SYMPHONY_ORCHESTRATION_PROVIDER", "agent_zero")

    assert {:error, :agent_zero_adapter_pending, message} =
             Providers.execution_ready(%Config{codex_command: "codex app-server"})

    assert message =~ "not wired"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
  defp restore_app_env(key, nil), do: Application.delete_env(:symphony_elixir, key)
  defp restore_app_env(key, value), do: Application.put_env(:symphony_elixir, key, value)
end
