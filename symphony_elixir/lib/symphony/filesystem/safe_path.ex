defmodule Symphony.Filesystem.SafePath do
  def sanitize_segment(s) do
    s |> to_string() |> String.replace(~r/[^A-Za-z0-9._-]/, "_") |> blank()
  end

  def safe_join(root, segs) do
    root = Path.expand(root)

    with :ok <- Enum.reduce_while(segs, :ok, fn s, _ -> valid(s) end) do
      p = Path.expand(Path.join([root | Enum.map(segs, &to_string/1)]))
      if inside_root?(root, p), do: {:ok, p}, else: {:error, :path_escape}
    end
  end

  def inside_root?(root, path) do
    root = Path.expand(root)
    path = Path.expand(path)
    path == root or String.starts_with?(path, root <> "/")
  end

  def reject_symlink(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :symlink}} -> {:error, :symlink_rejected}
      {:ok, _} -> :ok
      {:error, :enoent} -> :ok
      {:error, e} -> {:error, e}
    end
  end

  defp blank(""), do: "_"
  defp blank(s), do: s

  defp valid(s) do
    s = to_string(s)

    cond do
      String.contains?(s, <<0>>) -> {:halt, {:error, :null_byte}}
      s in ["", ".", ".."] -> {:halt, {:error, :invalid_segment}}
      Path.type(s) == :absolute -> {:halt, {:error, :absolute_segment}}
      String.contains?(s, "/") -> {:halt, {:error, :slash_segment}}
      true -> {:cont, :ok}
    end
  end
end
