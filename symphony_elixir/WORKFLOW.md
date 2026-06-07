---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: $LINEAR_PROJECT_SLUG
  active_states: [Todo, In Progress]
  terminal_states: [Closed, Cancelled, Canceled, Duplicate, Done]
polling:
  interval_ms: 30000
workspace:
  root: ./symphony_workspaces
hooks:
  timeout_ms: 60000
agent:
  max_concurrent_agents: 10
  max_turns: 20
  max_retry_backoff_ms: 300000
codex:
  command: codex app-server
server:
  port: 4004
---
You are a Symphony coding agent working on Linear issue {{ issue.identifier }}: {{ issue.title }}.
Issue state: {{ issue.state }}
Attempt: {{ attempt }}
Operate only inside the issue workspace and hand off to Human Review when ready.
