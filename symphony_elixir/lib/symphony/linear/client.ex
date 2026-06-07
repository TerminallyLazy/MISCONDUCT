defmodule Symphony.Linear.Client do
  @callback fetch_candidate_issues(Symphony.Config.t()) :: {:ok, list()} | {:error, term()}
  @callback fetch_issues_by_states([String.t()], Symphony.Config.t()) ::
              {:ok, list()} | {:error, term()}
  @callback fetch_issue_states_by_ids([String.t()], Symphony.Config.t()) ::
              {:ok, list()} | {:error, term()}
end
