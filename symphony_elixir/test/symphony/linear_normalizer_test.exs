defmodule Symphony.LinearNormalizerTest do
  use ExUnit.Case, async: true

  test "normalizes Linear issue payload" do
    issue =
      Symphony.Linear.Normalizer.normalize_issue(%{
        "id" => "uuid",
        "identifier" => "LIN-7",
        "title" => "Fix",
        "priority" => 1,
        "state" => %{"name" => "In Progress"},
        "labels" => %{"nodes" => [%{"name" => "Bug"}]},
        "relations" => %{
          "nodes" => [
            %{
              "type" => "blocks",
              "relatedIssue" => %{
                "id" => "b",
                "identifier" => "LIN-1",
                "state" => %{"name" => "Todo"}
              }
            }
          ]
        }
      })

    assert issue.identifier == "LIN-7"
    assert issue.labels == ["bug"]
    assert [%{identifier: "LIN-1", state: "Todo"}] = issue.blocked_by
  end
end
