defmodule Symphony.Orchestration.Providers do
  @providers ["direct_codex", "agent_zero"]

  def active_provider(config) do
    provider =
      Application.get_env(:symphony_elixir, :orchestration_provider) ||
        System.get_env("SYMPHONY_ORCHESTRATION_PROVIDER") ||
        get_in(workflow_config(config), ["orchestration", "provider"]) ||
        workflow_config(config)["provider"] ||
        "direct_codex"

    normalize(provider)
  end

  def status(config) do
    active = active_provider(config)
    codex = Symphony.Codex.Auth.status(config)
    agent_zero = agent_zero_config()

    providers = [
      %{
        id: "direct_codex",
        name: "Direct Codex Agents",
        active: active == "direct_codex",
        default: true,
        available: codex[:cli_available] == true,
        selectable: true,
        authenticated: codex[:authenticated] == true,
        status: if(codex[:cli_available], do: codex[:state], else: "cli_missing"),
        command: config.codex_command,
        auth_source: codex[:auth_source],
        message: codex[:message],
        blocked_reason: nil
      },
      %{
        id: "agent_zero",
        name: "Agent Zero",
        active: active == "agent_zero",
        default: false,
        available: false,
        selectable: false,
        configured: agent_zero.configured,
        implemented: false,
        authenticated: false,
        status: if(agent_zero.configured, do: "adapter_pending", else: "not_configured"),
        endpoint: agent_zero.endpoint,
        command: agent_zero.command,
        blocked_reason:
          if(agent_zero.configured,
            do: "Agent Zero execution adapter is not implemented yet.",
            else:
              "Set SYMPHONY_AGENT_ZERO_URL or SYMPHONY_AGENT_ZERO_COMMAND before enabling Agent Zero."
          ),
        message:
          if(agent_zero.configured,
            do: "Agent Zero configuration detected; adapter execution is not wired yet.",
            else: "Agent Zero is optional and not configured."
          )
      }
    ]

    %{
      active_provider: active,
      default_provider: "direct_codex",
      contract_version: 1,
      provider_contract: @providers,
      providers: providers,
      status: provider_status(active, providers),
      generated_at: DateTime.utc_now()
    }
  end

  def select("direct_codex", config), do: select(:direct_codex, config)

  def select(:direct_codex, config) do
    Application.put_env(:symphony_elixir, :orchestration_provider, "direct_codex")
    {:ok, status(config)}
  end

  def select("agent_zero", config), do: select(:agent_zero, config)

  def select(:agent_zero, config) do
    agent_zero = agent_zero_config()

    cond do
      not agent_zero.configured ->
        {:error, :agent_zero_not_configured,
         "Set SYMPHONY_AGENT_ZERO_URL or SYMPHONY_AGENT_ZERO_COMMAND before enabling Agent Zero.",
         status(config)}

      true ->
        {:error, :agent_zero_adapter_pending,
         "Agent Zero is configured, but Symphony does not have a production execution adapter wired yet.",
         status(config)}
    end
  end

  def select(provider, config) do
    {:error, :unsupported_provider, "Unsupported provider: #{provider}", status(config)}
  end

  def execution_ready(config) do
    case active_provider(config) do
      "direct_codex" ->
        runner = Application.get_env(:symphony_elixir, :agent_runner, Symphony.AgentRunner.Codex)
        {:ok, %{id: "direct_codex", label: "Direct Codex Agents", runner: runner}}

      "agent_zero" ->
        {:error, :agent_zero_adapter_pending,
         "Agent Zero orchestration is selected, but the production execution adapter is not wired yet."}
    end
  end

  defp provider_status(active, providers) do
    case Enum.find(providers, &(&1.id == active)) do
      %{available: true} -> "ready"
      %{id: "agent_zero", configured: true} -> "agent_zero_adapter_pending"
      %{id: "agent_zero"} -> "agent_zero_not_configured"
      _ -> "degraded"
    end
  end

  defp agent_zero_config do
    endpoint = blank(System.get_env("SYMPHONY_AGENT_ZERO_URL"))
    command = blank(System.get_env("SYMPHONY_AGENT_ZERO_COMMAND"))

    %{
      configured: present?(endpoint) or present?(command),
      endpoint: endpoint,
      command: command
    }
  end

  defp workflow_config(%{workflow: nil}), do: %{}
  defp workflow_config(%{workflow: workflow}), do: Map.from_struct(workflow).config || %{}
  defp workflow_config(_), do: %{}

  defp normalize(provider) do
    provider = to_string(provider)
    if provider in @providers, do: provider, else: "direct_codex"
  end

  defp blank(nil), do: nil
  defp blank(value), do: if(String.trim(to_string(value)) == "", do: nil, else: to_string(value))
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
