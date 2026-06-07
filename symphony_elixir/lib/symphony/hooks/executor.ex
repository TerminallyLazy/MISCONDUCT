defmodule Symphony.Hooks.Executor do
  def run(nil, _cwd, _timeout), do: :ok
  def run("", _cwd, _timeout), do: :ok

  def run(script, cwd, timeout) do
    task =
      Task.async(fn -> System.cmd("sh", ["-lc", script], cd: cwd, stderr_to_stdout: true) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {_, 0}} -> :ok
      {:ok, {out, code}} -> {:error, {:hook_failed, code, String.slice(out, 0, 1000)}}
      nil -> {:error, :hook_timeout}
    end
  end
end
