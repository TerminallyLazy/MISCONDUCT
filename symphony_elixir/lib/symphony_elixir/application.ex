defmodule SymphonyElixir.Application do
  use Application

  def start(_type, _args) do
    config = load_config()

    children =
      [
        {Symphony.Events, []},
        {Task.Supervisor, name: Symphony.AgentSupervisor},
        {Symphony.Workspace.Manager, root: config.workspace_root},
        {Symphony.AgentProfileRegistry, config: config},
        {Symphony.Orchestrator, config: config}
      ] ++ http_child(config)

    Supervisor.start_link(children, strategy: :one_for_one, name: SymphonyElixir.Supervisor)
  end

  defp load_config do
    path = System.get_env("SYMPHONY_WORKFLOW_PATH") || Path.expand("WORKFLOW.md")
    unless File.exists?(path), do: File.write!(path, default_workflow())
    Symphony.Config.load!(path)
  end

  defp http_child(config) do
    enabled = Application.get_env(:symphony_elixir, :http_enabled, true)

    port =
      String.to_integer(
        to_string(
          System.get_env("SYMPHONY_HTTP_PORT") || System.get_env("PORT") || config.http_port ||
            "4004"
        )
      )

    if enabled,
      do: [{Bandit, plug: Symphony.Http.Router, scheme: :http, ip: {127, 0, 0, 1}, port: port}],
      else: []
  end

  defp default_workflow do
    case Symphony.Workflow.Files.render_template("blank", %{}) do
      {:ok, content} ->
        content

      {:error, _reason} ->
        "---\ntracker:\n  kind: none\nworkspace:\n  root: ./misconduct_workspaces\nserver:\n  port: 4004\n---\nYou are working on MISCONDUCT movement {{ issue.identifier }}: {{ issue.title }}. Attempt: {{ attempt }}.\n"
    end
  end
end
