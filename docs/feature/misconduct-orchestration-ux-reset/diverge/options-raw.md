# MISCONDUCT Orchestration UX Reset - Divergence Options

## HMW Question

How might we let an operator confidently direct a team of coding agents in a repository and verify, live and after the fact, who worked, what they did, what changed, and what needs human attention?

## Grounding Notes

- The current stage metaphor is not earning trust because it shows roles, movement labels, cue dashes, and decorative activity before it proves that live agents are running, using tools, changing files, or communicating.
- The Munder-Difflin reference treats each agent as a real process with identity, memory, inbox/outbox, hook events, terminal stream, command history, telemetry spans, cost/context gauges, task ledger, pause/steer/halt controls, and durable event logs.
- MISCONDUCT needs the orchestra metaphor to sit on top of those runtime facts, not replace them. A violinist on stage should correspond to an actual runnable worker, its current cue, its tool calls, and its artifacts.

## SCAMPER Options

### Option 1: Terminal-First Agent Workbench

**Core idea**: A user opens MISCONDUCT and sees live agent sessions as first-class workbenches, each with a terminal stream, current repo, assigned movement, controls, and evidence tabs.
**Key mechanism**: Substitute the stage-card abstraction with a process-backed agent workbench model: each roster member maps to a live subprocess/session record, command stream, environment, workspace, last heartbeat, and lifecycle state.
**Key assumption**: Operators will trust orchestration only after they can see and control the underlying worker sessions directly.
**SCAMPER origin**: Substitute
**Closest competitor**: Munder-Difflin Command Center

### Option 2: Movement War Room

**Core idea**: A user clicks a movement and gets a conversation-style room where the Conductor, Builder, Judge, Refiner, and operator speak in one chronological thread with linked tool calls, artifacts, and decisions.
**Key mechanism**: Combine the plan, ledger, phase history, tool output, file diffs, verdicts, and operator actions into one movement-scoped thread instead of splitting them across stage map, side panel, ledger, and raw JSON.
**Key assumption**: The operator wants to follow one movement from request to evidence without mentally stitching together separate UI panels.
**SCAMPER origin**: Combine
**Closest competitor**: Linear issue activity plus GitHub Actions logs

### Option 3: Munder-Style Hive Runtime

**Core idea**: A user adds agents to a roster, watches them become live workers, and sees messages move through inbox/outbox channels with a Conductor agent routing and escalating work.
**Key mechanism**: Adapt Munder-Difflin's durable hive pattern: registry, per-agent identity, memory, inbox/outbox, append-only event log, task ledger, single committer, hook-based telemetry, and an always-on supervisor/conductor.
**Key assumption**: MISCONDUCT should model orchestration as real worker coordination, not as a sequential backend job with themed labels.
**SCAMPER origin**: Adapt
**Closest competitor**: Munder-Difflin

### Option 4: Diff-First Evidence Center

**Core idea**: A user can tell at a glance whether agents touched the repo because every movement card foregrounds changed files, command runs, test results, created artifacts, and uncommitted diff summary.
**Key mechanism**: Magnify the evidence layer: every agent turn records pre/post git status, changed paths, command spans, exit codes, artifact paths, and verdict links, then displays that evidence before decorative stage state.
**Key assumption**: The clearest proof of agent work is repository evidence, not animation or natural-language status.
**SCAMPER origin**: Modify/Magnify
**Closest competitor**: GitHub Desktop changes view plus CI logs

### Option 5: Rehearsal Harness

**Core idea**: A user can run the same orchestration flow in a safe rehearsal mode that proves agent spawning, tool telemetry, file-change capture, Judge verdicts, and Refiner retries without touching the target repo.
**Key mechanism**: Put the orchestration engine to use as a certification harness with fixture repos, disposable workspaces, simulated failures, golden transcripts, and pass/fail readiness reports.
**Key assumption**: Operators need a low-risk way to learn the system and prove the runtime before trusting it with real repository work.
**SCAMPER origin**: Put to other use
**Closest competitor**: Playwright trace viewer plus CI smoke harness

### Option 6: Plain Pipeline Mode

**Core idea**: A user can switch off the stage and see movements as a strict pipeline: queued, conducting, building, judging, refining, blocked, complete, with exact timestamps and evidence at every gate.
**Key mechanism**: Eliminate the orchestral map from the primary workflow until the runtime facts are solid; use a dense operations table where every row maps to a persisted backend state.
**Key assumption**: When trust is low, direct operational clarity beats metaphor, even if the metaphor remains available as a secondary view.
**SCAMPER origin**: Eliminate
**Closest competitor**: GitHub Actions run list

### Option 7: Agents Pull Cues

**Core idea**: A user writes movements into a score queue and live agents pull eligible cues based on their capabilities, budgets, tool gates, and current load, then report back with evidence.
**Key mechanism**: Reverse orchestration from command-push to worker-pull: agents self-register, advertise capabilities, lease movements, renew heartbeats, and return completion or escalation packets.
**Key assumption**: A system feels more believable when live workers claim work themselves instead of the UI pretending static role cards are already doing work.
**SCAMPER origin**: Reverse
**Closest competitor**: Celery worker queues

## Crazy 8s Supplements

### Option 8: Score Builder Wizard

**Core idea**: A user creates a movement through a compact wizard: choose repo, describe goal, pick agents, set acceptance evidence, preview generated prompt, then conduct.
**Key mechanism**: Replace the ambiguous right-panel form with an explicit dispatch flow that validates repo path, available agents, workspace mode, allowed tools, required tests, and success artifacts before enqueueing.
**Key assumption**: Users will create better movements when the app asks for the operational inputs the agents actually need.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: GitHub issue form plus CI workflow dispatch

### Option 9: Operator Control Tower

**Core idea**: A user can pause, steer, resume, halt, or gate tools for any agent mid-run, and those actions appear in the same movement conversation as operator messages.
**Key mechanism**: Add explicit control primitives backed by hook or runner boundaries: pause denies tool calls, steer injects context, halt requests graceful stop, and tool gates record approvals or denials.
**Key assumption**: Operators need active control over autonomous agents, not just retry/archive buttons after failure.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: Munder-Difflin HITL gate and mid-run control

### Option 10: Tool Span Waterfall

**Core idea**: A user watches each agent's tool calls as a compact waterfall showing command, file read/write, search, test, duration, result, and failure reason.
**Key mechanism**: Instrument pre/post tool boundaries or runner command spans and render them per agent and per movement, with filters for writes, tests, failures, and human approvals.
**Key assumption**: Tool-level observability is the missing layer between "agent said something" and "repo changed."
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: LangSmith traces

### Option 11: Orchestra Legend That Teaches The Runtime

**Core idea**: A user sees a small always-visible legend that maps every orchestral element to a real runtime fact: player equals live worker, music stand equals movement, note equals tool call, envelope equals message, spotlight equals active turn, applause equals verified artifact.
**Key mechanism**: Make the metaphor self-explaining and data-bound by adding visual contracts, hover details, and empty states that say what runtime fact is missing.
**Key assumption**: The orchestra metaphor can work if every visual element has a stable operational meaning and no decorative status is allowed.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: Observable notebook legends

## All Generated Options

1. Terminal-First Agent Workbench
2. Movement War Room
3. Munder-Style Hive Runtime
4. Diff-First Evidence Center
5. Rehearsal Harness
6. Plain Pipeline Mode
7. Agents Pull Cues
8. Score Builder Wizard
9. Operator Control Tower
10. Tool Span Waterfall
11. Orchestra Legend That Teaches The Runtime

## Curated 6

### Option 1: Munder-Style Hive Runtime

**Core idea**: A user adds agents to a roster, watches them become live workers, and sees messages move through inbox/outbox channels with a Conductor agent routing and escalating work.
**Key mechanism**: Adapt Munder-Difflin's durable hive pattern: registry, per-agent identity, memory, inbox/outbox, append-only event log, task ledger, single committer, hook-based telemetry, and an always-on supervisor/conductor.
**Key assumption**: MISCONDUCT should model orchestration as real worker coordination, not as a sequential backend job with themed labels.
**SCAMPER origin**: Adapt
**Closest competitor**: Munder-Difflin

Diversity test:
- Different mechanism: Yes, durable worker registry and mailbox runtime.
- Different assumption about user behavior: Yes, users trust live workers and message routing more than static role cards.
- Different cost/effort profile: Yes, largest backend/runtime investment.

### Option 2: Movement War Room

**Core idea**: A user clicks a movement and gets a conversation-style room where the Conductor, Builder, Judge, Refiner, and operator speak in one chronological thread with linked tool calls, artifacts, and decisions.
**Key mechanism**: Combine the plan, ledger, phase history, tool output, file diffs, verdicts, and operator actions into one movement-scoped thread instead of splitting them across stage map, side panel, ledger, and raw JSON.
**Key assumption**: The operator wants to follow one movement from request to evidence without mentally stitching together separate UI panels.
**SCAMPER origin**: Combine
**Closest competitor**: Linear issue activity plus GitHub Actions logs

Diversity test:
- Different mechanism: Yes, movement-scoped conversation and artifact thread.
- Different assumption about user behavior: Yes, users reason through one work item at a time.
- Different cost/effort profile: Yes, medium UI/data-model work with high immediate payoff.

### Option 3: Diff-First Evidence Center

**Core idea**: A user can tell at a glance whether agents touched the repo because every movement card foregrounds changed files, command runs, test results, created artifacts, and uncommitted diff summary.
**Key mechanism**: Magnify the evidence layer: every agent turn records pre/post git status, changed paths, command spans, exit codes, artifact paths, and verdict links, then displays that evidence before decorative stage state.
**Key assumption**: The clearest proof of agent work is repository evidence, not animation or natural-language status.
**SCAMPER origin**: Modify/Magnify
**Closest competitor**: GitHub Desktop changes view plus CI logs

Diversity test:
- Different mechanism: Yes, repository evidence capture and display.
- Different assumption about user behavior: Yes, users trust files, diffs, commands, and tests first.
- Different cost/effort profile: Yes, medium instrumentation with lower orchestration-model risk.

### Option 4: Score Builder Wizard

**Core idea**: A user creates a movement through a compact wizard: choose repo, describe goal, pick agents, set acceptance evidence, preview generated prompt, then conduct.
**Key mechanism**: Replace the ambiguous right-panel form with an explicit dispatch flow that validates repo path, available agents, workspace mode, allowed tools, required tests, and success artifacts before enqueueing.
**Key assumption**: Users will create better movements when the app asks for the operational inputs the agents actually need.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: GitHub issue form plus CI workflow dispatch

Diversity test:
- Different mechanism: Yes, pre-dispatch movement creation and validation.
- Different assumption about user behavior: Yes, users need guided task definition before orchestration starts.
- Different cost/effort profile: Yes, frontend-heavy with bounded backend validation endpoints.

### Option 5: Operator Control Tower

**Core idea**: A user can pause, steer, resume, halt, or gate tools for any agent mid-run, and those actions appear in the same movement conversation as operator messages.
**Key mechanism**: Add explicit control primitives backed by hook or runner boundaries: pause denies tool calls, steer injects context, halt requests graceful stop, and tool gates record approvals or denials.
**Key assumption**: Operators need active control over autonomous agents, not just retry/archive buttons after failure.
**SCAMPER origin**: Crazy 8s supplement
**Closest competitor**: Munder-Difflin HITL gate and mid-run control

Diversity test:
- Different mechanism: Yes, runtime intervention controls.
- Different assumption about user behavior: Yes, users will intervene during work, not only before or after it.
- Different cost/effort profile: Yes, medium-to-large depending on runner hook support.

### Option 6: Plain Pipeline Mode

**Core idea**: A user can switch off the stage and see movements as a strict pipeline: queued, conducting, building, judging, refining, blocked, complete, with exact timestamps and evidence at every gate.
**Key mechanism**: Eliminate the orchestral map from the primary workflow until the runtime facts are solid; use a dense operations table where every row maps to a persisted backend state.
**Key assumption**: When trust is low, direct operational clarity beats metaphor, even if the metaphor remains available as a secondary view.
**SCAMPER origin**: Eliminate
**Closest competitor**: GitHub Actions run list

Diversity test:
- Different mechanism: Yes, direct operational pipeline view.
- Different assumption about user behavior: Yes, some operators need non-metaphorical state before accepting the stage view.
- Different cost/effort profile: Yes, lower-to-medium effort and can be delivered incrementally.

## Eliminated Or Merged Options

- Terminal-First Agent Workbench was merged into Munder-Style Hive Runtime because live sessions, terminals, and lifecycle state are part of that runtime model.
- Rehearsal Harness was held back because it is a verification companion to the selected options rather than the primary operator experience.
- Agents Pull Cues was merged into Munder-Style Hive Runtime because worker leasing and self-registration belong inside the durable roster/runtime contract.
- Tool Span Waterfall was merged into Diff-First Evidence Center because tool spans are one evidence lane alongside files, commands, tests, and artifacts.
- Orchestra Legend That Teaches The Runtime was held back because it depends on the selected runtime/evidence model; it is useful only after every visual element has a real data binding.
