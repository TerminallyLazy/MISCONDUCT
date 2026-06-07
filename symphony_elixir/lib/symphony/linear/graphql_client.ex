defmodule Symphony.Linear.GraphQLClient do
  @behaviour Symphony.Linear.Client
  alias Symphony.Linear.Normalizer
  def fetch_candidate_issues(c), do: query_issues(c, c.active_states)
  def fetch_issues_by_states([], _c), do: {:ok, []}
  def fetch_issues_by_states(states, c), do: query_issues(c, states)
  def fetch_issue_states_by_ids(ids, c), do: graphql(c, state_query(), %{ids: ids}) |> normalize()

  defp query_issues(c, states),
    do:
      graphql(c, candidate_query(), %{
        projectSlug: c.tracker_project_slug,
        states: states,
        first: 50
      })
      |> normalize()

  defp graphql(c, q, vars),
    do:
      Req.post(c.tracker_endpoint,
        json: %{query: q, variables: vars},
        headers: [{"authorization", c.tracker_api_key || ""}],
        receive_timeout: 30000
      )

  defp normalize({:ok, %{status: 200, body: %{"errors" => e}}}),
    do: {:error, {:linear_graphql_errors, e}}

  defp normalize({:ok, %{status: 200, body: b}}),
    do:
      {:ok, Enum.map(get_in(b, ["data", "issues", "nodes"]) || [], &Normalizer.normalize_issue/1)}

  defp normalize({:ok, %{status: s}}), do: {:error, {:linear_api_status, s}}
  defp normalize({:error, r}), do: {:error, r}

  defp candidate_query,
    do:
      "query($projectSlug:String!,$states:[String!],$first:Int){ issues(first:$first, filter:{project:{slugId:{eq:$projectSlug}}, state:{name:{in:$states}}}) { nodes { id identifier title description priority branchName url createdAt updatedAt state { name } labels { nodes { name } } relations { nodes { type relatedIssue { id identifier state { name } } } } } } }"

  defp state_query,
    do:
      "query($ids:[ID!]){ issues(filter:{id:{in:$ids}}){ nodes { id identifier title state { name } updatedAt } } }"
end
