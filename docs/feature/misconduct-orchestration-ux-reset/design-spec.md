# MISCONDUCT Orchestration UX Reset - Design Spec

## Problem

MISCONDUCT currently presents an orchestra stage before proving that orchestration is real. Operators can see movements, roles, cue lines, and agent-like labels, but they cannot quickly answer the operational questions that matter:

- Which agents are actually working?
- What exact phase is active?
- Did an agent run tools or commands?
- Did it touch files?
- Where are the score, verdict, and final evidence artifacts?
- What should the operator do next?

The result is a decorative control surface that forces the operator to infer truth from animation and raw ledger events.

## Design Principle

Every orchestra visual must map to a runtime fact. If MISCONDUCT cannot prove the fact, the UI must say that explicitly instead of implying work happened.

## Target Experience

### 1. Evidence-First Movement Selection

When an operator selects a movement, the first visible surface should be a runtime brief:

- phase and status
- assigned agent
- workspace/repository path
- score/verdict artifact paths
- changed file count
- command/tool span count
- latest actionable message

The existing score/staff art can remain, but evidence must outrank decoration.

### 2. Movement War Room

The movement ledger should read as a chronological conversation and evidence thread:

- Operator actions
- Conductor/Builder/Judge/Refiner handoffs
- runner session start/failure/completion
- command/tool outputs
- generated artifacts
- file-change snapshots

Raw debug JSON remains available, but it is not the primary view.

### 3. Plain Pipeline Mode

The app needs a non-metaphorical operations view alongside the stage:

- one row per movement
- explicit phase chain: Conductor, Builder, Judge, Refiner, Finale
- current status
- workspace
- changed files
- tool/command spans
- evidence health

This gives operators a trustable fallback when the stage metaphor is not enough.

### 4. Guided Score Builder

Movement creation should ask for the inputs the runtime needs:

- movement title
- target directory/repo
- objective/notes
- expected evidence
- validation commands
- optional file focus

The submitted movement brief should preserve those fields so Builder/Judge/Refiner prompts have concrete expectations.

### 5. Agent Roster Truth

The roster must clearly separate:

- configured profiles
- live assigned profiles
- idle profiles
- unavailable/disabled profiles

Adding a roster member means creating or enabling a profile. It does not imply a live process unless a movement is assigned to it.

## Runtime Evidence Contract

Each movement card should expose a `runtime_evidence` object:

```json
{
  "workspace_path": "/repo-or-managed-workspace",
  "score_path": "/repo/.symphony/conductor-score.md",
  "verdict_path": "/repo/.symphony/judge-verdict.json",
  "changed_files": ["src/main.tsx"],
  "command_spans": [
    {
      "phase": "build",
      "agent": "Codex Builder",
      "kind": "runner",
      "label": "codex exec",
      "status": "completed",
      "message": "Turn completed",
      "at": "2026-06-11T00:00:00Z"
    }
  ],
  "artifact_paths": [
    "/repo/.symphony/conductor-score.md",
    "/repo/.symphony/judge-verdict.json"
  ],
  "last_checked_at": "2026-06-11T00:00:00Z"
}
```

The first implementation does not need deep shell tracing. It must at least derive evidence from existing runner events, score/verdict artifacts, and git file status in the workspace.

## Implementation Slices

1. Backend evidence model
   - Add `runtime_evidence` to `Symphony.Run`.
   - Capture artifact paths and git changed files at phase completion, failure, retry, and final completion.
   - Convert existing agent events into lightweight command spans.
   - Include evidence in running, retrying, and completed cards.

2. Movement intake shape
   - Add optional `expected_evidence`, `validation_commands`, and `file_focus` fields to manual movements.
   - Include them in movement descriptions/prompts using readable labels.

3. Frontend evidence surfaces
   - Parse `runtime_evidence`.
   - Add an evidence summary to selected movement plan.
   - Add an evidence panel in the ledger tab.
   - Add a plain pipeline view in the main console.
   - Replace ambiguous “cue dash” messaging with a small legend that states what is runtime-backed.

4. Documentation and release
   - Add implementation spec.
   - Update README/release notes/version.
   - Verify backend tests, frontend build, Tauri check, local package, and GitHub release assets.

## Non-Goals

- Do not build a full Munder-Difflin clone in this slice.
- Do not introduce a separate long-running worker pool yet.
- Do not require Agent Zero.
- Do not rename internal `Symphony` modules.
- Do not remove the stage. Make it secondary to evidence and pipeline truth.

## Acceptance Criteria

- A movement card can show changed files and artifact paths without opening debug JSON.
- A movement can show command/runner spans derived from live orchestration events.
- The operator can create a movement with expected evidence and validation commands.
- The console includes a non-metaphorical pipeline view.
- The stage includes a clear runtime legend explaining what is evidence-backed.
- Backend and frontend tests/builds pass.
- Desktop release artifacts are published for the new version.
