# ADR-0020 (ACCEPTED): Code owns document structure; the LLM authors prose only - "model proposes, code disposes"

Status: **ACCEPTED (2026-09-09) - founder directive.**
Date: 2026-09-09
Owner call: Shy, verbatim: "Let's code the structure of the documents and ask
the LLM only for the text."

Tool-calling addendum (same directive, via the main thread): structural
operations are implemented as typed LangChain/LangGraph TOOL CALLS whose
handlers are the pipeline's own validation and id-assignment code, so
malformed structure is impossible by construction. Same discipline as the
structured-output rollout (ADR-0018 follow-up): probe tool-calling
reliability on qwen2.5-coder:14b via Ollama FIRST, report the probe results,
keep a non-tool fallback, flip the default only if the probe reads well.

## Context

Until now every stage asked the model to maintain STRUCTURE (ids, numbering,
kinds, ordering, traceability links) AND write prose in the same call. Two
problems with that:

1. Structure is not language. Ids, ordering, and the need -> requirement
   mapping are deterministic facts: in practice the mapping is mechanical
   1:1 (kind, stakeholder, SN-links all preserved). Spending model budget
   and attention on numbering buys nothing and creates a flake surface.
2. The failure class is real and already bit us: the schema-keyword collision
   crash (a grammar that forbade a contract-required field), and earlier
   free-mode runs drifting top-level keys and dropping required fields. Every
   structural field the model must emit is a structural field it can drop,
   rename, or renumber.

## Decision

**The pipeline deterministically owns every document skeleton; LLM calls
shrink to producing natural-language content.**

- **SRS stage.** Code builds the requirement skeleton from the
  `StakeholderNeedsSet`: one slot per need, `R-1..R-n` in need order, with
  kind, `need_ids`, `intent_fields`, and section (functional /
  non_functional) carried 1:1. The model fills prose ONLY, per slot:
  `title`, `statement`, `priority` (must/should/could), and acceptance
  statements (strings). Code assigns `AC-n` ids sequentially, verifies every
  slot was filled exactly once (unknown or missing ids are a retryable model
  error), and assembles the contract `SRSDocument` body.
- **Tests stage.** Code builds the test skeleton: one acceptance-level slot
  per SRS acceptance criterion (`criterion_id` linked) and one unit/module
  slot per item spec (`spec_id` linked), `T-n` assigned in order. The model
  fills `description`, `runner`, and the runner `definition` per slot.
- **Architecture stage** keeps more freedom - structure there genuinely IS
  analysis - under the same propose/dispose rule: the model proposes stack,
  components, and decisions in bulk; code assigns `ADR-n` ids in order and
  validates component-name uniqueness and requirement-id references.

**The escape hatch - model proposes, code disposes.** Where structure is
genuinely analysis (decomposing a complex need into several requirements,
adding a component, adding a test, linking a trace), the model may PROPOSE
the operation as a typed tool call - `split_requirement`, `add_component`,
`add_test`, `link_trace`. The tool HANDLERS are pipeline code: they validate
the proposal (target exists, parts are non-empty prose, links resolve),
normalize it, assign the new ids, and return the assigned ids so the model
can write prose for the slots it just created. Malformed structure is
impossible by construction: there is no path by which model output becomes
an id, an ordering, or a link without passing through a validating handler.

**Rollout.** The deterministic skeletons (SRS, tests, ADR-id assignment) ship
as the default immediately - they strictly reduce what the model can get
wrong and need no new model capability. The tool-calling path is OPT-IN
(`SPEC_GENERATOR_TOOLS=1`) until `scripts/probe_tools.py` demonstrates on
the founder's machine that qwen2.5-coder:14b via Ollama emits well-formed,
schema-conformant tool calls reliably (and how it degrades when it can't).
The non-tool fallback is the 1:1 skeleton: no splits, no additions - a
complete, valid document every time.

## Consequences

- `vmodel-contracts` is UNCHANGED (stays 0.7.0): the artifacts are identical;
  only WHO assigns ids/links changes. No migration, no re-stamp.
- Stage output schemas shrink: ids, kinds, and links leave the grammar; the
  model's schema is prose fields plus the slot id it is filling.
- Prompts shrink to prose instructions; the "use the placeholder ids given"
  line in the methodology becomes literally true (code hands the ids).
- The review stage and assembly are untouched: state remains contract-shaped.
- What the LLM still owns: every word a human reads - statements, titles,
  rationale, descriptions, runner definitions. The authoring quality bar
  (grounded, solution-agnostic, no invented detail, text_qa guards) is
  unchanged.
