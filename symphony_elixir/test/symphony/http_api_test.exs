defmodule Symphony.Http.ApiTest do
  use ExUnit.Case, async: true

  alias Symphony.{Http.Api, Run}

  test "active run cards expose refiner attempt bounds" do
    card =
      Api.run_card(%Run{
        issue_id: "issue-refiner",
        issue_identifier: "TER-REFINER",
        phase: "refiner",
        status: :running,
        refiner_attempt: 1,
        refiner_max_attempts: 2,
        judge_verdict: %{verdict: "needs_refinement", path: "/tmp/judge-verdict.json"},
        agent_profile: %{
          id: "workflow-refiner",
          name: "Codex Refiner",
          role: "Refiner",
          section: "Brass",
          instrument_name: "French Horn",
          status: "idle"
        }
      })

    assert card.refiner_attempt == 1
    assert card.refiner_max_attempts == 2
    assert card.operator_status == "refining"
    assert card.agent_profile_id == "workflow-refiner"
    assert card.verdict == "needs_refinement"
    assert card.verdict_path == "/tmp/judge-verdict.json"
  end
end
