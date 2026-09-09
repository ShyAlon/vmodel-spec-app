# ADR-0022 (ACCEPTED): The deterministic harness - the model owns prose, code owns everything enumerable

Status: **ACCEPTED (2026-09-09) - implemented in spec-generator.**
Date: 2026-09-09
Owner call: Shy (after three same-day live failures all rooted in model
freedom): the model has too much freedom and responsibility - make the
harness more deterministic.

## Context

Every structural failure of 2026-09-09 was the same shape: something
ENUMERABLE (a slot id, a requirement reference, a session id) was left for
the model to produce, and a 14b local model eventually produced it wrong:

- `R-5: slot not filled` (generic fills grammar permitted missing slots) -
  fixed earlier the same day with per-skeleton grammars.
- Invented requirement references: items claimed `R-001..R-005`, leaving all
  ten real requirements uncovered and every traceability entry broken.
- The session id (`20260909-094216-e900`) leaked into spec names - the model
  reused the only identifier-shaped string it could see.
- Prompt contamination: the format contract buried mid-prompt, so the model
  followed the last frame it read - our methodology text.

ADR-0020 established "code owns the structure, the LLM authors prose." This
ADR extends it from document structure to the whole HARNESS: anything whose
value space is enumerable at runtime - ids, references, slot sets, retry
policy, sampling parameters - belongs to code. The model is consulted only
where the value space is genuinely open: prose, grouping, judgment.

## Decisions

1. **Reproducibility: temperature 0 + fixed seed everywhere.**
   All stages default to `temperature=0` and `seed=42`
   (`SPEC_GENERATOR_SEED` overrides), so a failure replays exactly. No stage
   is granted entropy; if one ever needs it, that deviation is documented
   here. Provider note: Ollama and the OpenAI-compatible path accept a seed;
   Anthropic exposes none - temperature 0 is the only lever there. Seeds make
   runs reproducible on the same model+driver version, not across versions.

2. **Granularity: per-slot micro-calls for the prose stages.**
   - SRS fills: one micro-call for purpose/scope_summary, then one call per
     requirement slot (slot + its need + slim intent context; on revision,
     only that slot's previous fill). A bad fill fails one cheap call instead
     of poisoning a long composite payload.
   - Items: split into PLAN (one call: spec ids, kinds, titles,
     requirement_ids, depends_on - the module grouping, which IS the
     analysis) then one body call per spec. References in the plan are
     enum-constrained to the real requirement ids; coverage (every
     requirement under >=1 spec) is validated at the stage with named retry
     feedback, not as a punch-list surprise after assembly.
   - Wall-time trade, stated honestly: micro-calls multiply prompt prefill
     (~N+1 calls vs 1 per stage). Payloads are deliberately slimmed (one
     need, trimmed intent) to keep prefill small; the expected net on a local
     14b is roughly par, paid back in failure isolation and per-item console
     lines. SPEC_GENERATOR_BULK=1 restores the composite calls if measured
     wall time says otherwise. The tests stage STAYS bulk-but-keyed: its 22
     fills are small, the per-skeleton grammar already closed its failure
     class, and 22 prefill cycles is real wall time for no structural gain.
   - Spec slots are NOT skeleton-derived from requirements (a conscious
     deviation from the srs/tests pattern): the requirement->module grouping
     is genuine design analysis - many-to-many by nature - so it stays
     model-proposed, code-validated, like architecture decisions.

3. **Nothing pipeline-owned reaches the model.** Prompt payloads are built
   from a scrubbed view of state (`_prompt_view`): session_id,
   intent_model_ref, contract_version are plumbing and are stripped
   recursively. What the model cannot see, it cannot regurgitate.

4. **Checkpoint state is plain JSON.** Assembly dumps with `mode="json"`;
   the remaining enum-carrying checkpoints (pre-fix runs) are covered by
   registering the vmodel_contracts enums in the checkpointer's
   `allowed_msgpack_modules`, which also future-proofs resume against
   LangGraph's coming strict msgpack mode.

## What remains model-owned, deliberately

Human gates and propose/dispose stay for genuine judgment - determinism is
not the goal there, reviewability is: need extraction (needs stage),
architecture proposals (code assigns ids and enforces drivers per ADR-0021),
module grouping (items plan), review findings, and all prose.

Enumerable-but-still-model-produced, with the code-owned replacement named:

- **Need ids (N-n).** Still model-assigned. Replacement: a propose/dispose
  pass (model proposes needs without ids, code assigns N-n in order), the
  same pattern as ADR ids. Deferred: the needs stage legitimately ADDS
  implied needs, so the count is not knowable pre-call; re-open when needs
  id drift is observed in a live run.
- **Spec id slugs (SPEC-...).** Still model-proposed, because depends_on
  needs model-visible ids to reference. Constrained instead: slug pattern,
  uniqueness, and resolvable deps validated at the stage.
- **Architecture component names.** Same reasoning as spec slugs; duplicates
  already rejected.

## Consequences

- A whole failure class (wrong/missing ids and references) is now impossible
  by construction, not caught by validation.
- Retries are cheap and local: one slot, one spec body - never a stage.
- Console observability improves again: one line per slot/spec as it lands.
- Wall time per stage is the open empirical question (see the BULK flag);
  the founder's next full run provides the numbers.
