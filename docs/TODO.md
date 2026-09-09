# TODO - deferred work and its re-open triggers

Parked decisions live in ADRs; this list is the working memory of what we
deliberately did NOT build yet, and the specific event that re-opens each
item. Keep it lean: if an item has no conceivable trigger, it does not
belong here.

## Deferred

1. **Retrieval-grounded verification (ADR-0019 Part 3).**
   A local 14b's library knowledge has a training cutoff. Verify
   architecture rationale claims ("most mature ecosystem", library
   currency, "use X v3") against live public data at architecture time.
   Zero-cost constraint stands: direct fetches of public docs / registries
   + the local embeddings already in verification-loop - no paid search,
   no paid vector DB.
   *Re-open trigger:* the first stale-library or wrong-rationale miss the
   G3 architecture gate does not catch, or Shy schedules the phase.

2. **Prose-call shim for tool calling (ADR-0020, parked).**
   qwen2.5-coder:14b writes well-formed tool calls as fenced JSON prose
   instead of emitting native calls. A shim would tolerant-extract those
   blocks (existing `_extract_json` machinery) into the same validating
   handlers. Not built: syntax was never the bottleneck - judgment was.
   *Re-open trigger:* a future local model passes the split_expected
   judgment half of `scripts/probe_tools.py` while still failing native
   emission. The shim converts exactly that gap and nothing else.

3. **intent_need_ids vs intent_fields prompt nuance.**
   The SRS fill schema carries both; the prompt wording around which the
   model touches caused confusion once. Clarify the wording or drop one
   from the grammar.
   *Re-open trigger:* next observed mis-linked requirement in a run, or
   the next prompt audit.

4. **Structured output for interview-engine.**
   spec-generator is schema-first (structured output per stage);
   interview-engine still runs free-mode + repair on its extraction
   calls. Same rollout applies: schema-first with a free-mode fallback.
   *Re-open trigger:* the next interview-engine failure attributable to
   format drift, or a planned interview quality pass.

5. **Wire add_component into the architecture stage (ADR-0020).**
   The tool is defined and probe-covered but not wired into
   `node_architecture` - held back by the SILENT tool-calling verdict on
   qwen2.5-coder:14b (SPEC_GENERATOR_TOOLS stays default-off).
   *Re-open trigger:* a tool-calling probe verdict strong enough to flip
   the tools path on for a future model.

6. **ADR-0021 driver grounding (depends on item 1).**
   Decision drivers ("ecosystem_maturity", ...) render as "model judgment
   - unverified" at the gate. Once retrieval (item 1) lands, driver
   reasons gain citations and the honesty gap closes at the source.
   *Re-open trigger:* ADR-0021 approved AND item 1 scheduled.
