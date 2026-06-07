defmodule Symphony.Config do
  @derive {Jason.Encoder, except: [:tracker_api_key]}
  defstruct workflow_path: nil,
            workflow_dir: nil,
            workflow: nil,
            tracker_kind: nil,
            tracker_endpoint: "https://api.linear.app/graphql",
            tracker_api_key: nil,
            tracker_project_slug: nil,
            active_states: ["Todo", "In Progress"],
            terminal_states: ["Closed", "Cancelled", "Canceled", "Duplicate", "Done"],
            poll_interval_ms: 30_000,
            workspace_root: nil,
            hooks: %{},
            hook_timeout_ms: 60_000,
            max_concurrent_agents: 10,
            max_turns: 20,
            max_retry_backoff_ms: 300_000,
            max_concurrent_agents_by_state: %{},
            codex_command: "codex app-server",
            codex_turn_timeout_ms: 3_600_000,
            codex_read_timeout_ms: 5_000,
            codex_stall_timeout_ms: 300_000,
            http_port: nil,
            agent_profiles_path: nil

  alias Symphony.Workflow.Loader

  def load(path \\ nil) do
    path = path || System.get_env("SYMPHONY_WORKFLOW_PATH") || Path.expand("WORKFLOW.md")
    with {:ok, wf} <- Loader.load(path), do: from_workflow(path, wf)
  end

  def load!(path \\ nil) do
    case load(path) do
      {:ok, c} -> c
      {:error, e} -> raise inspect(e)
    end
  end

  def from_workflow(path, wf) do
    cfg = wf.config || %{}
    dir = Path.dirname(Path.expand(path))
    tr = getv(cfg, "tracker", %{})
    po = getv(cfg, "polling", %{})
    ws = getv(cfg, "workspace", %{})
    hk = getv(cfg, "hooks", %{})
    ag = getv(cfg, "agent", %{})
    cx = getv(cfg, "codex", %{})
    sv = getv(cfg, "server", %{})

    {:ok,
     %__MODULE__{
       workflow_path: Path.expand(path),
       workflow_dir: dir,
       workflow: wf,
       tracker_kind: getv(tr, "kind", nil),
       tracker_endpoint: getv(tr, "endpoint", "https://api.linear.app/graphql"),
       tracker_api_key: resolve_env(getv(tr, "api_key", "$LINEAR_API_KEY")),
       tracker_project_slug: resolve_env(getv(tr, "project_slug", nil)),
       active_states: list_or(getv(tr, "active_states", nil), ["Todo", "In Progress"]),
       terminal_states:
         list_or(getv(tr, "terminal_states", nil), [
           "Closed",
           "Cancelled",
           "Canceled",
           "Duplicate",
           "Done"
         ]),
       poll_interval_ms: int_or(getv(po, "interval_ms", nil), 30_000),
       workspace_root:
         expand_path(
           resolve_env(getv(ws, "root", Path.join(System.tmp_dir!(), "symphony_workspaces"))),
           dir
         ),
       hooks: hk,
       hook_timeout_ms: int_or(getv(hk, "timeout_ms", nil), 60_000),
       max_concurrent_agents: int_or(getv(ag, "max_concurrent_agents", nil), 10),
       max_turns: int_or(getv(ag, "max_turns", nil), 20),
       max_retry_backoff_ms: int_or(getv(ag, "max_retry_backoff_ms", nil), 300_000),
       max_concurrent_agents_by_state:
         state_limits(getv(ag, "max_concurrent_agents_by_state", %{})),
       codex_command: getv(cx, "command", "codex app-server"),
       codex_turn_timeout_ms: int_or(getv(cx, "turn_timeout_ms", nil), 3_600_000),
       codex_read_timeout_ms: int_or(getv(cx, "read_timeout_ms", nil), 5_000),
       codex_stall_timeout_ms: int_or(getv(cx, "stall_timeout_ms", nil), 300_000),
       http_port: getv(sv, "port", nil),
       agent_profiles_path: expand_path(resolve_env(getv(ag, "profiles_path", nil)), dir)
     }}
  end

  def validate_dispatch(c) do
    []
    |> maybe_error(c.tracker_kind in ["linear"], {:unsupported_tracker_kind, c.tracker_kind})
    |> maybe_error(present?(c.tracker_api_key), :missing_tracker_api_key)
    |> maybe_error(present?(c.tracker_project_slug), :missing_tracker_project_slug)
    |> maybe_error(present?(c.codex_command), :missing_codex_command)
    |> case do
      [] -> :ok
      errs -> {:error, Enum.reverse(errs)}
    end
  end

  def active_state?(c, s), do: norm(s) in Enum.map(c.active_states, &norm/1)
  def terminal_state?(c, s), do: norm(s) in Enum.map(c.terminal_states, &norm/1)
  def norm(nil), do: ""
  def norm(s), do: s |> to_string() |> String.downcase()

  defp getv(m, k, d), do: Map.get(m || %{}, k, Map.get(m || %{}, String.to_atom(k), d))
  defp resolve_env("$" <> v), do: blank(System.get_env(v))
  defp resolve_env(v), do: v
  defp blank(nil), do: nil
  defp blank(v), do: if(String.trim(v) == "", do: nil, else: v)

  defp expand_path(nil, d),
    do: Path.expand(Path.join(System.tmp_dir!(), "symphony_workspaces"), d)

  defp expand_path(v, d), do: Path.expand(to_string(v), d)
  defp list_or(v, _d) when is_list(v), do: Enum.map(v, &to_string/1)
  defp list_or(_, d), do: d
  defp int_or(v, _d) when is_integer(v), do: v

  defp int_or(v, d) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      _ -> d
    end
  end

  defp int_or(_, d), do: d

  defp state_limits(m) when is_map(m) do
    Enum.reduce(m, %{}, fn {k, v}, acc ->
      i = int_or(v, 0)
      if i > 0, do: Map.put(acc, norm(k), i), else: acc
    end)
  end

  defp state_limits(_), do: %{}
  defp present?(v), do: is_binary(v) and String.trim(v) != ""
  defp maybe_error(errs, true, _), do: errs
  defp maybe_error(errs, false, reason), do: [reason | errs]
end
