# MISCONDUCT Orchestration Confidence - Taste Evaluation

## DVF Filter

Elimination rule: any option with DVF total below 6 is eliminated before taste scoring.

| Option | Desirability | Feasibility | Viability | DVF Total | DVF Avg | Decision |
|--------|--------------|-------------|-----------|-----------|---------|----------|
| Contract-First Event Bus | 5 | 4 | 5 | 14 | 4.67 | Pass |
| Movement State Machine | 5 | 3 | 5 | 13 | 4.33 | Pass |
| Agent Provenance Ledger | 4 | 4 | 4 | 12 | 4.00 | Pass |
| Orchestration Provider Switchboard | 5 | 4 | 5 | 14 | 4.67 | Pass |
| Backend-Owned Hall | 4 | 2 | 4 | 10 | 3.33 | Pass |
| Golden Hall Stage System | 4 | 5 | 2 | 11 | 3.67 | Pass |

No curated option was eliminated by DVF. Backend-Owned Hall has a lower feasibility score because it changes packaging/runtime ownership. Golden Hall Stage System has a lower viability score because it improves perception and usability but does not directly solve the backend, orchestration, Judge/Refiner, or OAuth reliability issues.

## Weights

Selected weights: Developer Tool profile.

Rationale: MISCONDUCT is an operator/developer tool. Trust depends heavily on responsiveness and clear state, so Speed-as-Trust uses the developer-tool weight.

| Criterion | Weight |
|-----------|--------|
| DVF average | 25% |
| T1 Subtraction | 15% |
| T2 Concept Count | 20% |
| T3 Progressive Disclosure | 15% |
| T4 Speed-as-Trust | 25% |

## Scoring Matrix

| Option | DVF | T1 Sub | T2 Concept | T3 Prog | T4 Speed | Weighted Total |
|--------|-----|--------|------------|---------|----------|----------------|
| Contract-First Event Bus | 4.67 | 4 | 4 | 4 | 5 | 4.42 |
| Agent Provenance Ledger | 4.00 | 4 | 5 | 5 | 4 | 4.35 |
| Orchestration Provider Switchboard | 4.67 | 4 | 4 | 5 | 4 | 4.32 |
| Movement State Machine | 4.33 | 4 | 4 | 4 | 4 | 4.08 |
| Backend-Owned Hall | 3.33 | 5 | 5 | 4 | 3 | 3.93 |
| Golden Hall Stage System | 3.67 | 3 | 5 | 5 | 3 | 3.87 |

## Criterion Breakdown

### Contract-First Event Bus

- DVF: 4.67. Directly addresses backend/frontend uncertainty and supports the operational value proposition.
- T1 Subtraction: 4. The transport, schemas, heartbeat, and acknowledgements are all useful, but contract generation could be deferred.
- T2 Concept Count: 4. Users do not need to understand the event bus, but operators may learn heartbeat and acknowledgement states.
- T3 Progressive Disclosure: 4. Live state appears naturally; deeper event detail can stay behind card/debug views.
- T4 Speed-as-Trust: 5. Immediate live updates are the clearest speed and trust signal.

### Agent Provenance Ledger

- DVF: 4.00. Strong trust mechanism, but more after-the-fact than live.
- T1 Subtraction: 4. The ledger needs redaction, prompts, agent selection, auth source, and verdicts; some metadata can be phased.
- T2 Concept Count: 5. A timeline/audit trail is familiar.
- T3 Progressive Disclosure: 5. The user only opens the ledger when investigating a card.
- T4 Speed-as-Trust: 4. Does not make execution faster, but every event can acknowledge progress immediately.

### Orchestration Provider Switchboard

- DVF: 4.67. It preserves Agent Zero as an option while keeping MISCONDUCT usable with Direct Codex Agents by default.
- T1 Subtraction: 4. Two adapters are justified by the stated requirement; extra provider configuration should be avoided.
- T2 Concept Count: 4. "Orchestration provider" is one new concept, but Direct Codex Agents can be the default.
- T3 Progressive Disclosure: 5. First-run can start direct; Agent Zero lives in advanced settings or workflow configuration.
- T4 Speed-as-Trust: 4. Direct Codex Agents can stay fast; Agent Zero may add handoff latency but can expose progress events.

### Movement State Machine

- DVF: 4.33. Strongly addresses questionable orchestration and Judge/Refiner behavior.
- T1 Subtraction: 4. Intake, Build, Judge, Refine, Complete, and Escalate are useful, but some stage detail can be hidden.
- T2 Concept Count: 4. Pipeline phases are familiar, but the movement language adds a product-specific layer.
- T3 Progressive Disclosure: 4. The board can show the current phase while details stay behind the selected card.
- T4 Speed-as-Trust: 4. State transitions give responsive feedback, though they do not solve transport freshness by themselves.

### Backend-Owned Hall

- DVF: 3.33. It reduces connection ambiguity but is harder to build and does not by itself solve provider orchestration or Judge/Refiner semantics.
- T1 Subtraction: 5. One runtime owner is a clean simplification.
- T2 Concept Count: 5. Users lose concepts rather than gain them.
- T3 Progressive Disclosure: 4. The user sees one service, but backend startup and logs still need a secondary surface.
- T4 Speed-as-Trust: 3. Startup/restart can feel slower unless carefully masked.

### Golden Hall Stage System

- DVF: 3.67. It satisfies the visual request and is straightforward to build, but reliability value is indirect.
- T1 Subtraction: 3. Venue detail can easily become decorative unless every element encodes state.
- T2 Concept Count: 5. A grand orchestra hall is immediately legible.
- T3 Progressive Disclosure: 5. The visual layer is passive and can reveal detail through selection/hover.
- T4 Speed-as-Trust: 3. Rich visuals must be optimized; otherwise they can make the app feel slower.
