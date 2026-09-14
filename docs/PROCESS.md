# The pipeline, end to end

One founder sentence goes in; a verified, traceable spec bundle comes out. This
is the map: what each step consumes, what it produces, and which artifact
carries the work forward. Every artifact is a versioned `vmodel-contracts`
model, so each handoff is validated, not hoped for.

```
founder sentence
   |
   v
+---------------------------- INTERVIEW-ENGINE ----------------------------+
| 1. Classifying scope          submission text -> scope class + tiebreaks |
| 2. Interviewing (turn N)      adaptive Q&A with the founder              |
| 3. Distillation (4 phases)    transcript -> intent model parts:          |
|      1/4 Extracting interview-level needs   SN-1.. (founder language)    |
|      2/4 Building scope and framing         glossary, constraints,       |
|                                             assumptions, in/out of scope |
|      3/4 Drafting requirement preview       3 examples, display only     |
|      4/4 Validating intent model            deterministic assembly + QA  |
| 4. Founder review (interrupt) you approve or edit before anything moves  |
+-------------------------------------------------------------------------+
   |
   v   out/<session>/intent_model.json   (IntentModel contract)
   v   Concept of Operations stage: stakeholder context + operational scenarios
       + explicit founder concept comparison/decision
   v   out/<session>/conops.json          (ConOpsDocument contract)
+---------------------------- SPEC-GENERATOR ------------------------------+
| stage 1/6 Formalizing stakeholder needs   Intent Model + Concept of Operations -> StakeholderNeedsSet |
| stage 2/6 Authoring the SRS               needs + Intent Model + Concept of Operations -> SRSDocument |
| stage 3/6 Drafting architecture overview  SRS + Concept of Operations -> ArchitectureOverview |
| stage 4/6 Writing module specs            SRS+arch -> ItemSpec[]         |
| stage 5/6 Deriving test specifications    SRS+items -> AcceptanceTest[]  |
| stage 6/6 Cross-checking consistency      fix list, up to 2 rounds       |
| then: Assembling + validating bundle      deterministic, no LLM          |
+-------------------------------------------------------------------------+
   |
   v   artifacts-YYYY-MM-DD_HH-MM-SS/  (AGENTS.md, srs.md, needs.md, architecture.md, specs/*.md,
   |             traceability.json, manifest.json)
+--------------------------- VERIFICATION-LOOP -----------------------------+
| deterministic first: acceptance-test runner (in the founder's own env),  |
| embeddings traceability, Semgrep structure checks, JSON-schema checks,   |
| diff scoring. LLM judges ONLY the semantic residue the above cannot.     |
+-------------------------------------------------------------------------+
   |
   v   VerificationReport - every divergence labeled deterministic or llm_judged
+----------------------------- DELIVERY-API --------------------------------+
| the web shell: share links, run status, usage, artifact download.        |
| No LLM stages.                                                           |
+-------------------------------------------------------------------------+
```

## The naming that confused everyone (fixed)

Two steps used to share the label "Extracting stakeholder needs". They do
different jobs:

- **Interview distillation 1/4 - now "Extracting interview-level needs"** reads
  the raw transcript and captures what the founder actually said as
  interview-level needs (`SN-1`, `SN-2`, ...), in the founder's own words,
  classified functional / non-functional. This is extraction: transcript in,
  candidate needs out.
- **Spec-generator stage 1/6 - now "Formalizing stakeholder needs"** does NOT
  re-interview or re-extract. It promotes those SN-needs into the formal
  `StakeholderNeedsSet` (`N-1`, `N-2`, ...): every SN-id maps to at least one
  N-id (carried in `intent_need_ids`), the kind is preserved, the stakeholder
  is named, and needs the founder *implied* but never stated are added with
  `intent_need_ids: []` so they are visibly inference, not quotation.

Why two artifacts: SN-needs are evidence (what was said); N-needs are the
engineering anchor everything downstream traces to (requirements reference
N-ids, and the traceability matrix closes the loop back to them). The console
labels now say which is which. Machine stage names (`distill_needs`, `needs`)
are unchanged, so env overrides and checkpoints are untouched.

## spec-generator stage details

Each stage is ONE model call returning one JSON payload (streamed, so the
console shows each item as its JSON closes - observability only, the output
contract is unchanged).

| stage | consumes | produces |
|---|---|---|
| 1/6 Formalizing stakeholder needs | IntentModel | StakeholderNeedsSet (N-1..) |
| 2/6 Authoring the SRS | needs + intent | SRSDocument body. Code builds the skeleton: one requirement slot per need (R-n in need order, kind + need/SN trace links carried 1:1, ADR-0020). The LLM fills PROSE per slot: title, statement, priority, acceptance statements. Code assigns AC-ids, sections, and validates. |
| 3/6 Drafting architecture overview | SRS | ArchitectureOverview: stack + components + decisions proposed by the model (structure is analysis here); code assigns ADR-ids in order and validates (ADR-0020) |
| 4/6 Writing module specs | SRS + architecture | ItemSpec[] (SPEC-...) covering every requirement |
| 5/6 Deriving test specifications | SRS + items | Code builds the skeleton: one acceptance slot per SRS criterion + one unit slot per item spec (T-n continuous, criterion/spec links owned, ADR-0020). The LLM fills description, runner, and runner definition per slot. |
| 6/6 Cross-checking consistency | SRS + items + tests | JSON fix list, or `[]` (stops early) |

Mechanical guards, not prompt discipline (ADR-0015): the SRS stage flags
solution language and ungrounded text (no founder vocabulary); glossary,
constraints, assumptions and open questions are carried from the intent model
deterministically at assembly - the LLM never re-copies them.

Who owns structure (ADR-0020): code owns ids, kinds, ordering, and trace
links; the LLM authors natural language only (statements, titles, rationale,
descriptions). Where structure IS analysis - splitting a complex need into
several requirements, adding a component or a test, linking a trace - the
model PROPOSES via typed tool calls and code DISPOSES (validate, normalize,
assign ids). The tool path is opt-in (`SPEC_GENERATOR_TOOLS=1`) until the
qwen2.5-coder:14b tool-calling probe (`scripts/probe_tools.py`) reads well on
the founder's machine; the fallback is the 1:1 skeleton, always valid.

Review loop: after 6/6, non-empty fixes are applied by re-running the SRS
prompt with the fix list, then module specs re-derive; at most 2 rounds. An
empty fix list short-circuits to assembly.

Assembly is deterministic: every artifact is validated against
`vmodel-contracts`, the traceability matrix (need -> requirement -> spec ->
test) is computed, milestones are ordered, and every violation lands on the
punch list. Nothing ships with an orphan trace.

Crash? Rerun the same command - the checkpointer resumes, no stage is paid
for twice. Cost per stage is in `usage.jsonl` ($0.0000 for local Ollama runs;
ADR-0018: local-first until production).

## Contracts and versioning

All four modules pin the same `vmodel-contracts` version. Old payloads are
rejected loudly by design; `python -m vmodel_contracts.migrate <file>` re-stamps
compatible ones. The full rationale is in ARCHITECTURE.md (ADR-0002 contracts,
ADR-0011 phased distillation, ADR-0015 mechanical guards, ADR-0017 SRS
redesign, ADR-0018 local-first).


## Batch generation after approved interviews

The Bash entry point can loop through native interactive interviews, queue
each approved intent, and start sequential generation when the founder says
there are no more interviews:

```bash
cd ~/development/require/vmodel-spec-app
scripts/batch-specs.sh
```

Or run each interview separately and queue completed sessions one at a time;
the queue survives across days:

```bash
cd vmodel-spec-app
scripts/batch-specs.sh add ../interview-engine/out/<session>/intent_model.json
# optional variance run of one approved interview:
scripts/batch-specs.sh add ../interview-engine/out/<session>/intent_model.json --repeat 3 --name booking
scripts/batch-specs.sh run
```

The runner is deliberately sequential for local Ollama. It prints an honest
2.5-3 hour estimate per run and the total before starting. Each queue entry
has its own `spec-generator/artifacts-YYYY-MM-DD_HH-MM-SS/` directory and the
manifest records that mapping before generation starts. If interrupted, rerun `scripts/batch-specs.sh run`; the running
entry reuses its directory and spec-generator resumes from its checkpoint.
A real nonzero failure stops the queue for diagnosis. After fixing the cause,
run `scripts/batch-specs.sh retry <run-id>` and then `run`; retry keeps
the same artifacts directory and checkpoint.

`batch-report.json` and `batch-report.md` are refreshed after every completed
run. They summarize contract-shaped artifact counts, requirement/spec and
criterion/test gaps, canonical test-definition compliance, runner mix,
tokens/cost/time, and content hashes. Repeated entries from the same interview
also get a variance summary. Rebuild without generating via:

```bash
scripts/batch-specs.sh report
```

The queue starts only from founder-approved `intent_model.json` files. Fully
automated brief import is intentionally not part of this half-automated mode.
