defmodule Symphony.Orchestrator.State do
  defstruct poll_interval_ms: 30_000,
            max_concurrent_agents: 10,
            running: %{},
            claimed: MapSet.new(),
            retry_attempts: %{},
            completed: MapSet.new(),
            completed_runs: %{},
            codex_totals: %{
              input_tokens: 0,
              output_tokens: 0,
              total_tokens: 0,
              seconds_running: 0.0
            },
            codex_rate_limits: nil,
            config: nil,
            worker_refs: %{},
            poll_timer_ref: nil,
            last_poll_at: nil,
            last_poll_count: 0,
            last_poll_error: nil
end
