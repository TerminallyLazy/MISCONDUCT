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
        runtime_evidence: %{
          workspace_path: "/tmp/workspace",
          score_path: "/tmp/workspace/.symphony/conductor-score.md",
          verdict_path: "/tmp/judge-verdict.json",
          changed_files: ["lib/example.ex"],
          command_spans: [
            %{
              phase: "refiner",
              agent: "Codex Refiner",
              kind: "runner",
              label: "runner turn",
              status: "completed",
              message: "Turn completed",
              at: ~U[2026-06-11 00:00:00Z]
            }
          ],
          artifact_paths: [
            "/tmp/workspace/.symphony/conductor-score.md",
            "/tmp/judge-verdict.json"
          ],
          last_checked_at: ~U[2026-06-11 00:01:00Z]
        },
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
    assert card.runtime_evidence.changed_files == ["lib/example.ex"]
    assert [%{label: "runner turn", status: "completed"}] = card.runtime_evidence.command_spans
    assert card.runtime_evidence.verdict_path == "/tmp/judge-verdict.json"
  end
end
