defmodule Symphony.Prompt do
  def render(template, issue, attempt \\ nil, context \\ %{}) do
    Regex.scan(~r/{{\s*([^}]+?)\s*}}/, template)
    |> Enum.reduce_while({:ok, template}, fn [raw, expr], {:ok, acc} ->
      case val(String.trim(expr), issue, attempt, context) do
        {:ok, v} -> {:cont, {:ok, String.replace(acc, raw, to_string(v || ""))}}
        {:error, e} -> {:halt, {:error, {:template_render_error, e}}}
      end
    end)
  end

  defp val("attempt", _, a, _), do: {:ok, a}
  defp val("issue." <> p, i, _, _), do: getp(i, String.split(p, "."), "issue." <> p)

  defp val("agent." <> p, _, _, c),
    do:
      getp(Map.get(c, :agent) || Map.get(c, "agent") || %{}, String.split(p, "."), "agent." <> p)

  defp val(o, _, _, _), do: {:error, "unknown variable #{o}"}
  defp getp(v, [], _), do: {:ok, if(is_map(v) or is_list(v), do: Jason.encode!(v), else: v)}

  defp getp(v, [k | r], full) do
    m = if is_struct(v), do: Map.from_struct(v), else: v

    cond do
      is_map(m) and Map.has_key?(m, k) ->
        getp(Map.get(m, k), r, full)

      is_map(m) and Map.has_key?(m, String.to_atom(k)) ->
        getp(Map.get(m, String.to_atom(k)), r, full)

      true ->
        {:error, "unknown variable #{full}"}
    end
  end
end
