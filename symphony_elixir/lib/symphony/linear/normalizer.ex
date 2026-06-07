defmodule Symphony.Linear.Normalizer do
  alias Symphony.Linear.Issue

  def normalize_issue(n),
    do: %Issue{
      id: g(n, "id"),
      identifier: g(n, "identifier"),
      title: g(n, "title"),
      description: g(n, "description"),
      priority: pri(g(n, "priority")),
      state: gi(n, ["state", "name"]),
      branch_name: g(n, "branchName") || g(n, "branch_name"),
      url: g(n, "url"),
      labels: labels(gi(n, ["labels", "nodes"])),
      blocked_by: blockers(gi(n, ["relations", "nodes"])),
      created_at: g(n, "createdAt"),
      updated_at: g(n, "updatedAt")
    }

  defp g(m, k), do: Map.get(m || %{}, k, Map.get(m || %{}, String.to_atom(k), nil))
  defp gi(m, ks), do: Enum.reduce(ks, m, fn k, a -> g(a, k) end)
  defp pri(i) when is_integer(i), do: i
  defp pri(_), do: nil
  defp labels(nil), do: []

  defp labels(nodes),
    do: nodes |> Enum.map(&(g(&1, "name") || &1)) |> Enum.map(&String.downcase(to_string(&1)))

  defp blockers(nil), do: []

  defp blockers(nodes),
    do:
      nodes
      |> Enum.filter(&(String.downcase(to_string(g(&1, "type"))) == "blocks"))
      |> Enum.map(fn n ->
        i = g(n, "relatedIssue") || g(n, "issue") || %{}
        %{id: g(i, "id"), identifier: g(i, "identifier"), state: gi(i, ["state", "name"])}
      end)
end
