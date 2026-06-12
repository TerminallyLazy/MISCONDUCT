# MISCONDUCT Orchestration UX Reset - Implementation Spec

## Scope

Ship a first runtime-evidence release that makes MISCONDUCT usable without guessing. This release prioritizes evidence visibility over deeper worker-pool architecture.

## Files Expected To Change

Backend:

- `symphony_elixir/lib/symphony/run.ex`
- `symphony_elixir/lib/symphony/orchestrator.ex`
- `symphony_elixir/lib/symphony/http/api.ex`
- focused backend tests under `symphony_elixir/test/symphony/`

Frontend:

- `src/main.tsx`
- `src/styles.css`

Docs/version/release:

- `README.md`
- `RELEASE_WORKFLOW_NOTE.md`
- `package.json`
- `package-lock.json`
- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `src-tauri/Cargo.lock`

## Data Model

Add `runtime_evidence` to `%Symphony.Run{}`.

Shape:

```elixir
%{
  workspace_path: String.t() | nil,
  score_path: String.t() | nil,
  verdict_path: String.t() | nil,
  changed_files: [String.t()],
  command_spans: [
    %{
      phase: String.t() | nil,
      agent: String.t() | nil,
      kind: String.t(),
      label: String.t(),
      status: String.t(),
      message: String.t() | nil,
      at: DateTime.t() | nil
    }
  ],
  artifact_paths: [String.t()],
  last_checked_at: DateTime.t() | nil
}
```

Rules:

- Evidence must be JSON encodable.
- Changed files are relative to the workspace when possible.
- Artifact paths are included only when known or present.
- Command spans are redacted summaries, not full prompts or secrets.
- Evidence is kept with running, retrying, and completed movement cards.

## Backend Behavior

1. On dispatch:
   - Initialize evidence with workspace, score path, artifact paths, and empty changed files/spans.

2. On agent events:
   - Append command spans for `session_started`, `stdout`, `stderr`, `turn_completed`, and `turn_failed`.
   - Preserve only a bounded recent span list.

3. On phase completion/failure/retry/finale:
   - Refresh changed files with git status when the workspace is a git repo.
   - Refresh artifact paths for score/verdict files.
   - Publish refreshed evidence in card payloads.

4. On manual movement creation:
   - Accept optional fields:
     - `expected_evidence`
     - `validation_commands`
     - `file_focus`
   - Append readable sections to the movement description so prompts and cards expose the operator's expected evidence.

## Frontend Behavior

1. Parse `runtime_evidence` into card state.

2. Selected movement plan:
   - Add a runtime evidence summary before decorative score art.
   - Show changed file count, command span count, artifacts, and latest evidence check.

3. Movement ledger:
   - Add an evidence section with changed files and command spans.
   - Keep the agent conversation.
   - Keep debug JSON as secondary.

4. Main console:
   - Add a plain pipeline table below or beside the stage.
   - Show movement, phase/status, agent, workspace, changed files, spans, and evidence health.

5. Movement intake:
   - Add fields for expected evidence, validation commands, and file focus.
   - Preserve current title/workspace/notes behavior.

6. Stage:
   - Add a small runtime legend:
     - musician = configured/assigned agent profile
     - score = movement artifact
     - cue line = active phase routing
     - notes/spans = runner events
     - evidence = files/artifacts/commands

## Tests

Backend:

- Add/update tests that verify `Api.run_card/1` includes `runtime_evidence`.
- Add/update orchestration tests for changed-file evidence on completed/retry cards when feasible.
- Add/update manual movement API tests to verify expected evidence fields are folded into the movement description.

Frontend:

- `npm run build` must pass.

Release:

- `SYMPHONY_HTTP_ENABLED=false mix test`
- `npm run build`
- `cargo check` in `src-tauri`
- `npm run build:backend`
- local debug Tauri bundle smoke as practical
- push branch, merge to `main`, tag new version, push tag
- monitor `release-desktop.yml`
- verify GitHub release assets include macOS DMG, Windows installer, Linux AppImage, Linux DEB, and checksums

## Sub-Agent Slices

1. Backend evidence implementation
   - Owns backend files and tests.

2. Frontend evidence implementation
   - Owns `src/main.tsx` and `src/styles.css`.

3. Spec compliance review
   - Reviews final diff against this spec and design spec.

4. Code quality review
   - Reviews final diff for maintainability, boundedness, data safety, and release risk.
