# MISCONDUCT Orchestration Confidence - Recommendation

## Top 3 Options

### Option 1: Contract-First Event Bus - Score 4.42

**Why it scores well**: It makes the backend/frontend connection observable in real time, gives every operator action immediate acknowledgement, and creates the shared contract needed for direct Codex Agents, Agent Zero orchestration, Judge/Refiner stages, and OAuth status.
**Core trade-off**: It adds backend/frontend contract work before the richer orchestration model is fully implemented.
**Key risk**: The event schema must stay provider-neutral; otherwise it will hard-code today's direct Codex runner and make Agent Zero support harder later.
**Hire criteria**: Choose this when the first priority is proving the app is live, connected, and responding truthfully.

### Option 2: Agent Provenance Ledger - Score 4.35

**Why it scores well**: It gives users a familiar audit timeline, keeps complexity on demand, and makes questionable agent selection, Codex auth state, Judge verdicts, and Refiner changes inspectable.
**Core trade-off**: It explains what happened better than it prevents bad orchestration from happening.
**Key risk**: Redaction and retention must be correct from the start because prompts, auth evidence, and command output can contain sensitive data.
**Hire criteria**: Choose this when users already have runs happening but do not trust why they happened or what evidence backs them.

### Option 3: Orchestration Provider Switchboard - Score 4.32

**Why it scores well**: It satisfies the requirement that Agent Zero orchestration is available while Direct Codex Agents remains the default path for users who do not want Agent Zero.
**Core trade-off**: It adds an adapter boundary and provider status model before all provider-specific behavior is known.
**Key risk**: Agent Zero must be optional and late-disclosed; if users must understand it before using MISCONDUCT, the design loses taste quickly.
**Hire criteria**: Choose this when the product must support multiple orchestration backends without fragmenting the UI or workflow model.

## Recommendation

Proceed with Contract-First Event Bus as the implementation spine, with Orchestration Provider Switchboard as a required architectural constraint from the first slice.

That means the next design should define a provider-neutral event contract before adding more UI behavior: Direct Codex Agents is the default provider, Agent Zero is an optional provider adapter, and both must emit the same issue lifecycle, auth, agent, Judge, Refiner, and ledger events. This preserves the highest-scoring trust mechanism while avoiding the mistake of baking a single orchestration mode into the frontend.

## Dissenting Case

Agent Provenance Ledger nearly wins because it has excellent taste properties: a timeline is familiar, progressive, and useful for debugging. It should be included in the event model as event history, but it should not lead the work. If the ledger comes first without a live event contract, the system may still feel stale or disconnected while merely documenting that staleness afterward.

Golden Hall Stage System is the clearest visual direction, but it is not the architecture decision. Treat it as a parallel acceptance constraint: Codex Hall should evolve toward a grand concert-stage environment inspired by Carnegie Hall or the Vienna Musikverein Golden Hall, and every visual flourish should encode live orchestration state.

## Decision For Discuss Wave

Proceed with Contract-First Event Bus, assuming the event schema is provider-neutral from day one and Direct Codex Agents remains the default while Agent Zero orchestration is available as an optional adapter.
