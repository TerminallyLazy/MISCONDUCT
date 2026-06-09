defmodule Symphony.EventsTest do
  use ExUnit.Case, async: true

  alias Symphony.Events

  test "publishes bounded provider-neutral events to subscribers and history" do
    name = :"events_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Events.start_link(name: name, max_events: 2)

    :ok = Events.subscribe(name)

    Events.publish(
      %{
        type: "issue.stage.started",
        provider: "direct_codex",
        source: "test",
        issue_id: "issue-1",
        issue_identifier: "LIN-1",
        stage: "build",
        status: "running",
        message: "Started",
        data: %{secretish: "token=abc123", nested: %{provider: :direct_codex}}
      },
      name
    )

    assert_receive {:symphony_event, event}
    assert event.type == "issue.stage.started"
    assert event.provider == "direct_codex"
    assert event.issue_identifier == "LIN-1"
    assert event.data["secretish"] == "token=[REDACTED]"
    assert event.data["nested"]["provider"] == "direct_codex"

    Events.publish(%{type: "agent.event", message: "second"}, name)
    Events.publish(%{type: "tracker.poll.completed", message: "third"}, name)

    assert [%{type: "agent.event"}, %{type: "tracker.poll.completed"}] = Events.list(10, name)
  end
end
