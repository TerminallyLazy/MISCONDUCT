# MISCONDUCT Orchestration Confidence - Divergence Options

## HMW Question

How might we give operators confidence that complex agent work is connected, authorized, reviewed, refined, and legible across different orchestration modes as it moves from issue intake to completion?

## SCAMPER Options

### Option 1: Contract-First Event Bus

**Core idea**: A user sees Codex Hall update from a typed live stream where every backend heartbeat, issue transition, agent event, and command acknowledgement is visible without guessing whether the frontend is stale.
**Key mechanism**: Replace loose polling assumptions with a versioned frontend/backend contract, server-sent events or WebSocket updates, idempotent command endpoints, heartbeat state, and shared schemas generated from backend contracts.
**Key assumption**: The main frontend/backend failure mode is contract drift or missed state, and a single live event contract would expose and prevent most confusion.
**SCAMPER origin**: Substitute
**Closest competitor**: Temporal Web

### Option 2: Rehearsal Runbook Console

**Core idea**: A user runs a "rehearsal" that walks through backend health, frontend API base, Linear credentials, Codex CLI auth, agent profile storage, dispatch readiness, Judge metadata, and Refiner metadata as one guided checklist.
**Key mechanism**: Add a backend diagnostics endpoint and UI panel that executes bounded probes, returns redacted evidence, and links each failing item to the owning setting or route.
**Key assumption**: Operators do not need a different runtime first; they need a trustworthy end-to-end readiness proof that separates unavailable dependencies from broken code.
**SCAMPER origin**: Combine
**Closest competitor**: Kubernetes dashboard diagnostics

### Option 3: Movement State Machine

**Core idea**: A user sees each Linear issue progress through explicit movements: Intake, Build, Judge, Refine, Complete, or Escalate, with Judge and Refiner shown as real execution stages rather than passive metadata.
**Key mechanism**: Adapt CI pipeline semantics into the orchestrator by persisting run records, stage transitions, gate verdicts, retry bounds, and artifacts for Builder, Judge, and Refiner.
**Key assumption**: The current orchestration ambiguity exists because phases are implied in workflow text but not enforced as first-class runtime state.
**SCAMPER origin**: Adapt
**Closest competitor**: GitHub Actions

### Option 4: Agent Provenance Ledger

**Core idea**: A user can open any card and see why the agent was selected, which profile ran, what Codex command was used, which auth source was detected, what prompt was rendered, what Judge decided, and what Refiner changed.
**Key mechanism**: Magnify observability with an append-only, redacted run ledger exposed by API and rendered as a timeline in Codex Hall.
**Key assumption**: Trust improves when every orchestration decision and external dependency is explainable after the fact, even if some work still fails.
**SCAMPER origin**: Modify/Magnify
**Closest competitor**: LangSmith

### Option 5: Certification Harness

**Core idea**: A user or release process gets a single "ready to conduct" report proving that frontend commands, backend routes, Codex auth status, agent registry behavior, Judge/Refiner validation, and visual state rendering still work.
**Key mechanism**: Put the same orchestration contract to use as a test-only certification harness with isolated fixtures, Playwright checks, focused ExUnit tests, and no production demo data paths.
**Key assumption**: The same uncertainty testers report manually can be converted into repeatable release evidence without compromising production behavior.
**SCAMPER origin**: Put to other use
**Closest competitor**: Playwright test reports

### Option 6: Backend-Owned Hall

**Core idea**: A user opens one local MISCONDUCT service and never has to reason about whether the Tauri shell, Vite proxy, API base override, bundled backend, or Elixir service owns the truth.
**Key mechanism**: Eliminate the two-runtime ambiguity by making the backend the single owner of health, static UI serving, API base, contract generation, and packaged runtime startup.
**Key assumption**: Many connection failures come from split ownership between desktop shell, frontend runtime, and backend runtime rather than the orchestration algorithm itself.
**SCAMPER origin**: Eliminate
**Closest competitor**: Supabase Studio local dashboard

### Option 7: Agent Audition Registry

**Core idea**: A user sees available agents audition into the orchestra with live capability, auth, model, workspace, and heartbeat facts before MISCONDUCT assigns them real work.
**Key mechanism**: Reverse assignment flow so worker processes or Codex sessions register themselves, renew leases, declare capabilities, and are selected by the orchestrator based on measured availability.
**Key assumption**: Agent creation and assignment are questionable because configured profiles are not the same thing as live, runnable workers.
**SCAMPER origin**: Reverse
**Closest competitor**: Celery worker pools

## Crazy 8s Supplements

### Option 8: Golden Hall Stage System

**Core idea**: A user sees Codex Hall as a grand concert stage inspired by Carnegie Hall or the Vienna Musikverein Golden Hall, with balconies, acoustic shell depth, warm brass lighting, carved wood, and status cues embedded into the architecture.
**Key mechanism**: Create a visual system with venue-inspired layout tokens, layered stage scenery, responsive depth, section seating, podium lighting, and state overlays for active, review, retry, blocked, and completed work.
**Key assumption**: The orchestral metaphor can carry operational meaning if it looks like a real performance venue instead of a flat pixel map.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: Fantastical calendar's polished skeuomorphic moments

### Option 9: OAuth Flight Recorder

**Core idea**: A user can replay the Codex connection attempt as a redacted sequence: CLI discovered, version checked, login command launched, status probe attempted, session file detected, account label redacted, and final state classified.
**Key mechanism**: Add a dedicated auth event recorder with sanitized probe outputs, state transitions, retry guidance, and UI affordances for manual CLI fallback.
**Key assumption**: Codex OAuth feels questionable because the UI collapses too many auth states into "connected" or "sign-in needed."
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: Stripe CLI login diagnostics

### Option 10: Issue Intake Airlock

**Core idea**: A user sees each candidate Linear issue wait in an airlock until workflow validity, credentials, agent availability, workspace creation, and Judge/Refiner readiness are all checked.
**Key mechanism**: Insert a pre-dispatch gate between polling and execution that records readiness checks and prevents half-started runs.
**Key assumption**: A visible preflight gate would reduce failed dispatches and make blocked dependency states less surprising.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: Argo CD sync preflight checks

### Option 11: Orchestration Provider Switchboard

**Core idea**: A user can start with Direct Codex Agents by default, optionally switch to Agent Zero orchestration, and still see the same issue lifecycle, Judge/Refiner gates, auth status, and run evidence in either mode.
**Key mechanism**: Add a provider interface with two first-class adapters: the default adapter launches and tracks Codex Agents directly through MISCONDUCT, while the Agent Zero adapter delegates orchestration to Agent Zero.
**Key assumption**: Agent Zero is valuable for users who already want its orchestration layer, but MISCONDUCT should remain useful without requiring Agent Zero as a dependency.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: LangGraph provider adapters

## All Generated Options

1. Contract-First Event Bus
2. Rehearsal Runbook Console
3. Movement State Machine
4. Agent Provenance Ledger
5. Certification Harness
6. Backend-Owned Hall
7. Agent Audition Registry
8. Golden Hall Stage System
9. OAuth Flight Recorder
10. Issue Intake Airlock
11. Orchestration Provider Switchboard

## Curated 6

### Option 1: Contract-First Event Bus

**Core idea**: A user sees Codex Hall update from a typed live stream where every backend heartbeat, issue transition, agent event, and command acknowledgement is visible without guessing whether the frontend is stale.
**Key mechanism**: Replace loose polling assumptions with a versioned frontend/backend contract, server-sent events or WebSocket updates, idempotent command endpoints, heartbeat state, and shared schemas generated from backend contracts.
**Key assumption**: The main frontend/backend failure mode is contract drift or missed state, and a single live event contract would expose and prevent most confusion.
**SCAMPER origin**: Substitute
**Closest competitor**: Temporal Web

Diversity test:
- Different mechanism: Yes, live contract and event transport.
- Different assumption about user behavior: Yes, users need immediate state truth while operating the app.
- Different cost/effort profile: Yes, medium backend/frontend contract work with high verification surface.

### Option 2: Movement State Machine

**Core idea**: A user sees each Linear issue progress through explicit movements: Intake, Build, Judge, Refine, Complete, or Escalate, with Judge and Refiner shown as real execution stages rather than passive metadata.
**Key mechanism**: Adapt CI pipeline semantics into the orchestrator by persisting run records, stage transitions, gate verdicts, retry bounds, and artifacts for Builder, Judge, and Refiner.
**Key assumption**: The current orchestration ambiguity exists because phases are implied in workflow text but not enforced as first-class runtime state.
**SCAMPER origin**: Adapt
**Closest competitor**: GitHub Actions

Diversity test:
- Different mechanism: Yes, deterministic stage model and persisted run lifecycle.
- Different assumption about user behavior: Yes, users trust visible workflow phases more than generic running/retrying cards.
- Different cost/effort profile: Yes, larger backend model change with moderate frontend visualization work.

### Option 3: Agent Provenance Ledger

**Core idea**: A user can open any card and see why the agent was selected, which profile ran, what Codex command was used, which auth source was detected, what prompt was rendered, what Judge decided, and what Refiner changed.
**Key mechanism**: Magnify observability with an append-only, redacted run ledger exposed by API and rendered as a timeline in Codex Hall.
**Key assumption**: Trust improves when every orchestration decision and external dependency is explainable after the fact, even if some work still fails.
**SCAMPER origin**: Modify/Magnify
**Closest competitor**: LangSmith

Diversity test:
- Different mechanism: Yes, audit ledger and timeline rather than transport or state-machine enforcement.
- Different assumption about user behavior: Yes, users need forensic confidence after a run, not only live status during a run.
- Different cost/effort profile: Yes, incremental instrumentation with data-retention and redaction concerns.

### Option 4: Orchestration Provider Switchboard

**Core idea**: A user can start with Direct Codex Agents by default, optionally switch to Agent Zero orchestration, and still see the same issue lifecycle, Judge/Refiner gates, auth status, and run evidence in either mode.
**Key mechanism**: Add a provider interface with two first-class adapters: the default adapter launches and tracks Codex Agents directly through MISCONDUCT, while the Agent Zero adapter delegates orchestration to Agent Zero.
**Key assumption**: Agent Zero is valuable for users who already want its orchestration layer, but MISCONDUCT should remain useful without requiring Agent Zero as a dependency.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: LangGraph provider adapters

Diversity test:
- Different mechanism: Yes, provider adapters and mode selection.
- Different assumption about user behavior: Yes, users split between Agent Zero-centered orchestration and lighter direct Codex Agents usage.
- Different cost/effort profile: Yes, medium-to-large interface design with separate integration paths and shared UI contracts.

### Option 5: Backend-Owned Hall

**Core idea**: A user opens one local MISCONDUCT service and never has to reason about whether the Tauri shell, Vite proxy, API base override, bundled backend, or Elixir service owns the truth.
**Key mechanism**: Eliminate the two-runtime ambiguity by making the backend the single owner of health, static UI serving, API base, contract generation, and packaged runtime startup.
**Key assumption**: Many connection failures come from split ownership between desktop shell, frontend runtime, and backend runtime rather than the orchestration algorithm itself.
**SCAMPER origin**: Eliminate
**Closest competitor**: Supabase Studio local dashboard

Diversity test:
- Different mechanism: Yes, runtime ownership simplification.
- Different assumption about user behavior: Yes, users should not have to configure or diagnose multiple local app origins.
- Different cost/effort profile: Yes, packaging/runtime architecture work with a simpler long-term support burden.

### Option 6: Golden Hall Stage System

**Core idea**: A user sees Codex Hall as a grand concert stage inspired by Carnegie Hall or the Vienna Musikverein Golden Hall, with balconies, acoustic shell depth, warm brass lighting, carved wood, and status cues embedded into the architecture.
**Key mechanism**: Create a visual system with venue-inspired layout tokens, layered stage scenery, responsive depth, section seating, podium lighting, and state overlays for active, review, retry, blocked, and completed work.
**Key assumption**: The orchestral metaphor can carry operational meaning if it looks like a real performance venue instead of a flat pixel map.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: Fantastical calendar's polished skeuomorphic moments

Diversity test:
- Different mechanism: Yes, visual architecture and state encoding.
- Different assumption about user behavior: Yes, users understand orchestration faster when the venue metaphor is beautiful and operationally meaningful.
- Different cost/effort profile: Yes, frontend-heavy design work with limited backend impact.

## Eliminated Or Merged Options

- Rehearsal Runbook Console was not removed as weak; it was merged into Agent Provenance Ledger and Backend-Owned Hall because diagnostics overlap with both audit evidence and runtime ownership.
- Certification Harness was held back from the curated six because it is a release-proof companion to the selected options rather than a primary product mechanism.
- OAuth Flight Recorder was merged into Agent Provenance Ledger because both depend on redacted event history and explanatory state transitions.
- Issue Intake Airlock was merged into Movement State Machine because pre-dispatch readiness is one stage in the broader lifecycle model.
- Agent Audition Registry was merged into Orchestration Provider Switchboard because live capability discovery belongs inside the provider contract for both Agent Zero and Direct Codex Agents modes.
