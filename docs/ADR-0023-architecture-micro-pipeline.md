# ADR-0023 (ACCEPTED): The architecture stage is a micro-pipeline; stack grounding is typed entries, not parallel maps

Status: **ACCEPTED (2026-09-12) - implemented in vmodel-contracts 0.13.0 + spec-generator.**
Date: 2026-09-12
Owner call: Shy (2026-09-11, after the phi4 architecture failure): "Is there
a way to dumb it down for it? Maybe split it to smaller chunks that would
fit." - and on choosing it over stronger-model routing: "I'd rather solve
our problems than rely on stronger models... price might be an issue."

## Context

Quality fix 1 (contracts 0.12.0) grounded architecture in a versioned
SystemBaseline: a `stack` map plus a parallel `stack_baseline_refs` map,
with a stage guard requiring identical key sets. On 2026-09-11 phi4 failed
that stage twice in a row. The diagnosis was NOT schema wiring: the grammar
reached Ollama and phi4 emitted a schema-legal top-level structure - but it
also dropped a bogus `stack_baseline_refs` string key inside the free-form
`stack` map, and the two maps' key sets disagreed. Grammar enforces shape;
it cannot enforce the cross-field relation `keys(stack) ==
keys(stack_baseline_refs)`. Asking a small local model to hold two free-form
maps synchronized across a long completion is asking for exactly this
failure.

## Decisions

1. **Typed stack entries replace the parallel maps (contracts 0.13.0).**
   `ArchitectureOverview.stack_entries: list[StackEntry]` co-locates
   `{key, value, baseline_refs, migration_adr_id?}`. There is no second map,
   so the misplacement is structurally impossible. Pre-0.13.0 artifacts
   self-heal at the documented boundaries when the maps agree (`vmodel_contracts.migrate`);
   the phi4 failure shape (disagreeing maps) is refused loudly - no guessed
   co-location. `migration_adr_id` is a pipeline-assigned `ADR-n` reference,
   not model-authored title text: one more string-equality invariant removed.

2. **The stage is a micro-pipeline (ADR-0022 applied to architecture).**
   Code builds the canonical baseline/ref inventory deterministically.
   Three tiny planning calls propose SLOTS - stack keys, component slots,
   ADR slots. One shallow-schema call fills each slot: one stack entry, one
   component responsibility, one ADR body, one non-functional position.
   References are enum-constrained to code-computed truth (canonical refs,
   real requirement ids, real repo names, declared departures), so the
   model cannot cite what does not exist. Code assigns ADR ids, wires each
   departure to its authorizing ADR, assembles the contract artifact, and
   runs the unchanged whole-architecture semantic gate on the result.

3. **Per-slot partial persistence.** Completed slots land in
   `architecture.partial.json` the moment they close; a crash or a
   validation retry resumes the failed slot only, not the ~10-minute stage
   (same doctrine as the SRS fills).

4. **Raw completions are capturable, opt-in.** `SPEC_GENERATOR_LOG_RAW=1`
   (with `VMODEL_LLM_LOG` naming the sink) appends byte-exact
   `llm_call_raw` events, so a future structural failure leaves a real
   regression fixture. The 2026-09-11 completion was never logged; the
   shipped fixture reproduces the failure CLASS from the error evidence and
   is labeled as such - the byte-exact fixture lands when a capture exists.

5. **The acceptance gate is a real run, not unit tests.** Local models are
   viable on the architecture stage again only when a phi4
   `--only-stage architecture` run against the six-repo baseline completes
   and produces grounded output. Until then `deepseek:deepseek-flash` remains
   the documented fallback route for the stage.

## Consequences

- The stage costs more calls (3 plans + 1 per slot) and more wall-clock
  minutes; each call is small, visible, and independently retryable.
- DeepSeek routing stays available per stage but is no longer REQUIRED for
  architecture on local hardware - a cost/competitiveness property the
  owner explicitly wants for future customers.
- Consumer repos pin vmodel-contracts v0.13.0; wrong-minor payloads fail
  loudly at their existing version gates.
