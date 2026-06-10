# MISCONDUCT Backend

Local Elixir backend for the MISCONDUCT desktop app. It owns workflow loading,
agent orchestration, safe workspace paths, Codex auth/status checks, and the
operator HTTP API consumed by the Tauri frontend.

## Installation

The OTP app is still named `symphony_elixir` internally. Build and test it from
this directory:

```bash
mix test
```
