defmodule Symphony.Workspace.Manager do
  use GenServer
  alias Symphony.{Workspace, Config}
  alias Symphony.Filesystem.SafePath
  alias Symphony.Hooks.Executor

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))

  def create_for_issue(identifier, config, server \\ __MODULE__),
    do: GenServer.call(server, {:create, identifier, config}, 30000)

  def remove_for_issue(identifier, config, server \\ __MODULE__),
    do: GenServer.call(server, {:remove, identifier, config}, 30000)

  def init(opts), do: {:ok, %{root: Keyword.get(opts, :root)}}

  def handle_call({:create, identifier, %Config{} = config}, _from, state) do
    root =
      Path.expand(
        config.workspace_root || state.root || Path.join(System.tmp_dir!(), "symphony_workspaces")
      )

    key = SafePath.sanitize_segment(identifier)

    result =
      with {:ok, path} <- SafePath.safe_join(root, [key]),
           :ok <- File.mkdir_p(root),
           :ok <- SafePath.reject_symlink(path) do
        created = not File.exists?(path)
        :ok = File.mkdir_p(path)

        case if(created,
               do:
                 Executor.run(
                   get_in(config.hooks, ["after_create"]),
                   path,
                   config.hook_timeout_ms
                 ),
               else: :ok
             ) do
          :ok -> {:ok, %Workspace{path: path, workspace_key: key, created_now: created}}
          {:error, r} -> {:error, r}
        end
      end

    {:reply, result, state}
  end

  def handle_call({:remove, identifier, %Config{} = config}, _from, state) do
    root =
      Path.expand(
        config.workspace_root || state.root || Path.join(System.tmp_dir!(), "symphony_workspaces")
      )

    key = SafePath.sanitize_segment(identifier)

    result =
      with {:ok, path} <- SafePath.safe_join(root, [key]), :ok <- SafePath.reject_symlink(path) do
        _ =
          if File.dir?(path),
            do:
              Executor.run(get_in(config.hooks, ["before_remove"]), path, config.hook_timeout_ms),
            else: :ok

        File.rm_rf(path)
      end

    {:reply, result, state}
  end
end
