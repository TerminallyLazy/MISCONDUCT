---
schema_version: 1
name: "symphony-console-default"
description: Symphony Console default workflow for Direct Codex orchestration.
tracker:
  kind: none
  active_states: [Manual, Ready, In Progress]
  terminal_states: [Closed, Cancelled, Canceled, Duplicate, Done]
polling:
  interval_ms: 0
workspace:
  root: ./symphony_workspaces
hooks:
  timeout_ms: 30000
agent:
  max_concurrent_agents: 2
  max_turns: 20
  max_retry_backoff_ms: 300000
  profiles_path: ./agent_profiles.json
codex:
  command: codex app-server
  turn_timeout_ms: 3600000
  read_timeout_ms: 5000
  stall_timeout_ms: 300000
server:
  port: 4004
generator:
  provider: codex
  profile: "workflow-generator"
  instructions: Conduct operator movements into bounded implementation scores.
builder:
  provider: codex
  profile: "workflow-builder"
  instructions: Run scoped implementation work in the issue workspace.
judge:
  provider: codex
  profile: "workflow-judge"
  rubric: [tests_pass, implementation_matches_issue, no_unrequested_file_changes, no_embedded_secrets]
  pass_threshold: 0.8
refiner:
  provider: codex
  profile: "workflow-refiner"
  max_attempts: 3
  strategy: fix_judge_findings
stage_agents:
  - profile: "workflow-generator"
    name: "Workflow Conductor"
    role: "Generator"
    profile_key: "workflow-generator"
    enabled: "true"
    section: "Woodwinds"
    instrument: "Clarinet"
    description: "Opens the score by turning operator movements into bounded plans."
    instructions: "Conduct manual movement context and repository facts into scoped implementation plans."
    capabilities: ["workflow-generation", "planning", "manual-intake"]
    music:
      section: "Woodwinds"
      instrument: "Clarinet"
      motif: "Overture / Conductor Intake"
      dynamic: "mezzo-piano"
      register: "middle"
    stage:
      section: "woodwinds"
      seat: "front-left"
  - profile: "workflow-builder"
    name: "Codex Builder"
    role: "Builder"
    profile_key: "workflow-builder"
    enabled: "true"
    section: "Strings"
    instrument: "Violin"
    description: "Carries the implementation line through the active Codex workspace."
    instructions: "Run Codex against real movement workspaces and keep changes scoped."
    capabilities: ["implementation", "codex", "repository-work"]
    music:
      section: "Strings"
      instrument: "Violin"
      motif: "Movement I / Build"
      dynamic: "mezzo-forte"
      register: "upper-middle"
    stage:
      section: "strings"
      seat: "front-center"
  - profile: "workflow-judge"
    name: "Workflow Judge"
    role: "Judge"
    profile_key: "workflow-judge"
    enabled: "true"
    section: "Piano"
    instrument: "Piano"
    description: "Evaluates completed movements against quality, safety, and scope gates."
    instructions: "Judge work against tests, movement fit, changed-file scope, and secret-safety constraints."
    capabilities: ["review", "quality-gates", "safety"]
    music:
      section: "Piano"
      instrument: "Piano"
      motif: "Movement II / Judge"
      dynamic: "mezzo-piano"
      register: "middle"
    stage:
      section: "piano"
      seat: "center-right"
  - profile: "workflow-refiner"
    name: "Workflow Refiner"
    role: "Refiner"
    profile_key: "workflow-refiner"
    enabled: "true"
    section: "Brass"
    instrument: "French Horn"
    description: "Resolves judge findings with bounded, evidence-based correction passes."
    instructions: "Fix judge findings without inventing facts or expanding the task scope."
    capabilities: ["refinement", "review-fixes", "bounded-retry"]
    music:
      section: "Brass"
      instrument: "French Horn"
      motif: "Movement III / Refine"
      dynamic: "mezzo-forte"
      register: "lower-middle"
    stage:
      section: "brass"
      seat: "back-right"
---
# Workflow

## Identity
- Project: operator-supplied score
- Workspace: ./symphony_workspaces
- Workflow version: 1
- Source context: manual movement payload and repository files visible to the runner.

## Objective
Coordinate operator-supplied Symphony movements through Direct Codex builder, judge, and refiner stages.

## Inputs
- Movement identifier: {{ issue.identifier }}
- Movement title: {{ issue.title }}
- Movement state: {{ issue.state }}
- Movement brief: {{ issue.description }}
- Attempt number: {{ attempt }}

## Agents
- Generator: conducts the operator movement into scoped execution instructions.
- Builder: runs Direct Codex against the issue workspace.
- Judge: evaluates changed files, validation output, and issue fit.
- Refiner: resolves judge findings with bounded retry attempts.

## Phases
- Overture / Conductor Intake: accept an operator movement and claim it for the orchestra.
- Movement I / Build: perform scoped implementation in the workspace.
- Movement II / Judge: verify outputs against the rubric.
- Movement III / Refine: fix judge findings without expanding scope.
- Finale / Complete: mark work ready only after validation gates pass.

## Validation Gates
- Manual movement title and brief are present before conducting work.
- Active provider is Direct Codex and the local Codex CLI is authenticated.
- Stage agent profiles referenced in front matter are enabled.
- Secrets remain environment references and are never written literally.
- Changed files stay within the configured workspace/repository policy.

## Artifacts
- Workspace changes in ./symphony_workspaces/{{ issue.identifier }}
- Agent event ledger, judge verdict, and final operator summary.

## Location and Activation
- Target file: WORKFLOW.md
- Use the Rehearsal check before conducting live work.
- Runtime reload is supported from Symphony Console when no active runs are in flight.

## Guardrails
- Do not invent tasks, paths, credentials, commands, or integrations.
- Destructive operations require human approval.

## Escalation
- Block and ask the operator when repository context, assigned agents, or required inputs are unavailable.

## Change Log
- Initial Symphony Console default workflow generated by Symphony.
