# Architecture

Systems-Engineering Spec App - demo build. September 2026.

This document is the decision record. Every load-bearing choice is here with
its reasoning, its alternatives, and what would change our mind. Argue with
it by number.

Companions: `Spec_App_Definition_v2` (market + positioning), the Demo Scoping
doc (test-run experience + thin slice), the Cost Architecture Addendum (the
per-run cost model). Where this doc disagrees with itself, the ADR wins.

---

## 1. What we are building

An interview-to-specification service with a verification loop. The founder
talks to an adaptive interview for 30-60 minutes; the system produces the
full V-model artifact set - stakeholder needs, system requirements,
architecture, item-level specs, test hierarchy (unit, module, system,
acceptance), and a V&V traceability matrix - packaged as a repo-ready bundle
(AGENTS.md + numbered build plan + machine-checkable acceptance criteria)
that a coding agent executes against. When the founder has a build, the
verification loop checks it against the spec and issues a verdict report
with a traceable punch list.

The demo exists to answer four questions with 5-10 real runs: do founders
complete the interview, do they hand the spec to their agent unmodified,
does verification catch divergences they care about, do they come back.
**Success criterion: a founder completes the flow, uses the spec unmodified,
and verification finds at least one real divergence they care about.**

The demo's second job: it is the instrument that converts the "under $5 per
spec" belief into a measured number. Per-stage token logging is a launch
requirement, not later telemetry.

---

## 2. The modules and the rule that makes them modular

Five repositories. The modularity lives in the **contracts**, not the repo
count: modules never import each other; they exchange versioned payloads
from `vmodel-contracts` and nothing else.

```
                        +--------------------+
  founder's idea  ----> |  interview-engine  | ----> IntentModel (founder-reviewed)
                        +--------------------+            |
                                                          v
                        +--------------------+     +-------------+
  VerificationReport <- |  verification-loop | <== | spec-generator |
                        +--------------------+     +-------------+
                             ^    build artifact          |  SpecBundle + tests
                             |                            v
                        +------------------------------------------+
                        |  delivery-api: links, state, jobs,       |
                        |  budgets, storage, cost rollup           |
                        +------------------------------------------+
```

| Module | Owns | Produces | Consumes |
|---|---|---|---|
| interview-engine | scope gate, adaptive interview, intent distillation, review gate | `ScopeVerdict`, `InterviewTranscript`, `IntentModel` | `IntakeSubmission` |
| spec-generator | needs -> SRS -> architecture -> item specs -> tests, staged drafts, review passes | `StakeholderNeedsSet`, `SRSDocument`, `RequirementSet` (flat view), `ArchitectureOverview`, `SpecBundle`, `SpecManifest`, `AcceptanceTest` set | `IntentModel` |
| verification-loop | founder-side test package, deterministic checks, semantic-residue judging, verdict report | `VerificationReport`, runner artifact | `SpecBundle` + build artifact ref |
| delivery-api | run links, run state machine, background jobs, storage, budget hard stop, cost ledger | `RunLink`, `RunStatus`, `RunCostReport`, `DeliveryBundle` | everything, through contracts |
| vmodel-contracts | the boundary itself | versioned models + JSON Schemas | - |

---

## 3. Decision records

### ADR-0001: Separate repositories, versioned contracts from day one

**Decision.** Five repositories, not a monorepo. The contracts between
modules are real versioned artifacts: `vmodel-contracts` is a published
package; each module pins an exact release
(`vmodel-contracts @ git+https://github.com/ShyAlon/vmodel-contracts.git@v0.2.0`).

**Reasoning.** The owner wants repos that can live separately, and the repo
boundary *forces* interface discipline - the strongest argument for
splitting. The monorepo's real benefit (atomic contract+consumer changes)
is bought differently here: contract changes are SemVer-released
(ADR-0002), consumers bump pins deliberately, and the JSON Schema diff
between releases is the compatibility review.

**Cost accepted.** N pipelines, coordinated version bumps, no atomic
cross-module commits. This is paid deliberately.

**Changes our mind.** Cross-repo coordination measurably slowing iteration
during the demo (the classic drift source). Escape hatch: the contracts stay
identical in a monorepo; merging repos is mechanical if the boundary held.

### ADR-0002: The contracts package is the architecture

**Decision.** A field that crosses a module boundary exists in
`vmodel-contracts` first. No ad-hoc JSON anywhere. Every payload carries
`contract_version`. SemVer: MAJOR breaks consumers, MINOR is additive,
PATCH is docs/validation. `vmodel-contracts-export` dumps JSON Schemas;
the schema diff IS the release review.

**Reasoning.** "Modules talk only through versioned contracts" is the
sentence that makes separate repos safe. If the contracts are clean,
splitting (or merging) code is a mechanical move, not a redesign.

### ADR-0003: LangGraph where it earns, plain code where it doesn't

**Decision.** LangGraph runs the interview engine and the generation
pipeline: both are stateful, resumable, branching flows with
human-in-the-loop gates (founder review) - what a graph runtime is for.
Deterministic stages (scope classification, assembly, traceability,
rendering, static checks) are plain code *called from graph nodes*, not
wrapped in orchestration ceremony.

**Model-agnostic layer.** Each module has a `model_config.py` mapping stage
-> (provider, model), env-overridable. DeepSeek is the default at demo
prices; OpenAI-compatible and Anthropic providers slot in by config.
Swapping providers is never a refactor.

**DeepSeek flags.** (a) Quality on the moat stages (probing, requirement
authoring) must be eyeballed before founder-facing runs - the env override
exists exactly so a stage can move to Sonnet-class without code changes.
(b) Some testers will ask where their data goes; the one-line answer and
the swap path must both be ready.

**Ollama for local runs.** A fourth provider, `ollama`, runs every LLM stage
locally (OpenAI-compatible endpoint at `localhost:11434/v1`, embeddings via
`nomic-embed-text`): offline, $0, logged as such in telemetry. This is the
development and test loop - quality judgments about the demo, especially the
interview and the verdicts, are made on the real provider, because those
stages are the moat and local models visibly under-perform there.

### ADR-0004: Hybrid cost design - the LLM owns judgment, code owns structure

**Decision.** Design B from the cost addendum, pushed as far toward
deterministic as quality allows (the B/C hybrid). The line is measurable:
**LLM only where removing it visibly drops output quality.**

| Stage | Owner | Why |
|---|---|---|
| Scope classification | Deterministic + LLM tiebreak | Signals settle most cases; ambiguous wording is semantic |
| Interview probing turns | **LLM, strong model** | The moat. Which question next depends on the semantics of everything said |
| Intent distillation | **LLM, strong model** | Open-ended summarization with judgment |
| Requirement authoring | **LLM, strong model** | Generic requirements are the free competitors' product |
| Id numbering, traceability matrix, manifest, milestones, AGENTS.md render | Deterministic | Structure. LLM adds cost and drift, not quality |
| Bundle validation (orphans, untested criteria) | Deterministic, hard-failing | A violated invariant is a punch-list item, not a shrug |
| Acceptance-test execution | Founder's environment | $0: their compute, their agent's tokens (ADR-0007) |
| Requirement-to-code traceability | Embeddings (~$0.01/run) | 500k tokens embedded = 1 cent |
| Structure/interface checks | Semgrep rules derived from spec constraints | compute, cents |
| Schema conformance | JSON Schema validation | negligible |
| Iteration scoring | diff | negligible |
| Semantic residue ("does this satisfy the *intent* of R-12?") | **LLM judge of last resort** | Irreducibly a judgment call - and it is the product |

**The one tradeoff not to make:** do not move the interview's probing turns
or the requirement-authoring pass to a smaller model or a script to chase
the $0.35-0.85 aggressive-deterministic floor. Those two stages are why a
founder pays instead of using Spec Kit free. Cheapen verification and
generation plumbing first; the interview last, if ever.

**Machine-checkability is a spec-authoring decision.** Acceptance criteria
are written as executable assertions (HTTP status, DOM assertion, CLI
result, schema conformance) *at authoring time* - that single discipline is
what collapses verification cost. Design the spec format for the verifier.

### ADR-0005: Web applications only, with a polite exit

**Decision.** Scope is web applications - including apps that consume web
APIs and services. The intake gate classifies: deterministic signal matching
first, LLM tiebreak only when signals are mixed or silent. Out of scope
(native mobile, desktop, hardware/firmware, CLI tooling, games) gets a
specific, polite decline and the run ends: `declined_out_of_scope`.

**Reasoning.** Narrowing is load-bearing for the demo: it narrows the
verification environment (headless HTTP/DOM checks), narrows the archetypes
(five named, one opinionated stack), and makes the exit criterion crisp.
The gate never re-runs on a resumed thread - re-paying for a settled
decision is a leak.

### ADR-0006: Background jobs, never request/response

**Decision.** Generation and verification are background jobs (queued,
resumable, polled) from line one. Vercel Hobby caps functions at 300
seconds; a full generation is a multi-minute pipeline. The LangGraph
checkpointer makes jobs resumable; delivery-api owns the queue seam.

**Reasoning.** Retrofitting async onto a synchronous demo is exactly the
rework the module boundaries exist to prevent. Batch-API pricing (50% off
at both vendors) becomes genuinely available, not theoretical.

### ADR-0007: Verification executes in the founder's own environment

**Decision.** Acceptance tests are generated as a dependency-free runner
that the founder's *own agent* executes in the founder's environment;
verification-loop scores the output. Tester code never executes on our
infrastructure at demo stage.

**Reasoning.** No sandbox security project, but real executable
verification - a static-only demo under-proves the one thing competitors
don't ship. Sandboxed execution on our infra is the first post-demo
investment and is a security project, not a feature.

### ADR-0008: Links, not accounts; budgets with hard stops

**Decision.** One personal link per tester; the token gates the run, ties
interview/spec/verification together, and rate-limits. One active run per
link. Per-run spend cap (default $6) enforced per stage at delivery-api's
ledger; a call that would cross the cap stops the run
(`budget_stopped`). Global cap (default $100) gates new links. Link
creation is admin-only.

**Reasoning.** Abuse protection is what lets a public demo exist. The cost
claim stays honest only if a runaway run dies instead of running up the
card.

### ADR-0009: Spec Kit-compatible bundle, one target agent

**Decision.** The bundle layout (specs/, plan, AGENTS.md, manifest) is Spec
Kit-compatible so testers already in that ecosystem adopt without
conversion. Demo target agent: Claude Code only; testers in other agents
are told "Claude Code for this test."

**Open (carried from scoping doc).** Proprietary layout would be cleaner
for the verifier. Compatibility won for adoption; revisit after the first
ten runs.

---

## 4. Run lifecycle

```
created -> in_interview -> intent_review (founder gate) -> generating
        -> delivered -> verifying -> reported
        -> declined_out_of_scope | budget_stopped   (terminal, honest)
```

The `intent_review` gate is deliberate: it is the cheapest place to catch a
misunderstanding, and it teaches the founder what the system understood.
Nothing generates without founder approval of the intent model.

## 5. Cost model (estimates until the logging says otherwise)

All figures are arithmetic on estimated token counts, **not measurements**
- the per-stage logging (below) is how they become measurements.

| Design | Per full run | Verdict |
|---|---|---|
| A: LLM-everything | $2.50-4.50 | $5 claim holds with zero engineering (Sonnet 5 stayed at $2/$10 - the Sept 1 increase never took effect, re-verified 2026-09-08) |
| B: Hybrid (built here) | ~$1.50-2.50 | 2-3x headroom under $5; the pricing room free-first-spec needs |
| C: Aggressive-deterministic | $0.35-0.85 | Not worth collecting: cheapens interview + authoring, the two paid differentiators |

**Token logging plan.** Every LLM call records a `StageTokenUsage`
(stage, provider, model, prompt/completion/cached tokens, price-at-call-time).
delivery-api rolls up per run, per tester, cumulative against the cap.
The price table is a versioned config (`PRICE_TABLE_VERSION = "2026-09-08"`),
not a constant - two price changes this month already. Deterministic costs
are logged even when they round to zero (embedding tokens, compute seconds),
because the point is a *complete* per-run number. When ten runs are in, the
hybrid column gets replaced by measurements and pricing stops being a belief.

## 6. How a repo earns a split (further)

Current repos split further only when a named condition fires:

1. **A second owner** - one person can't review their own boundary.
2. **Its own release cadence** - it genuinely ships on a different clock.
3. **Open-sourcing** - a public repo needs its own hygiene, license, CI.
4. **A different scaling/deployment profile** - e.g. verification-loop
   moving to dedicated compute while delivery-api stays serverless.

First candidate to watch: verification-loop, if sandboxed execution
(ADR-0007's sequel) lands - it will want isolation, its own deploy
pipeline, and probably its own infra budget. Until a condition fires, the
boundary work goes into the contracts, not into more repositories.

## 7. Security, privacy, abuse

- Tester code never executes on our infrastructure (ADR-0007).
- Links are unguessable tokens; one active run each; admin-only minting.
- Per-run and global spend hard stops (ADR-0008).
- Founder data: interview transcripts and specs are the tester's IP; the
  DeepSeek data-residency answer must be ready before founder-facing runs
  (ADR-0003). Founder PII is not collected; links carry labels, not identity.
- Secrets in env vars, never in repos. CI runs tests only - no deployment,
  no paid infra, without an explicit decision.

### ADR-0010: Progress is a structured event stream; printers are consumers

**Decision.** Every long-running stage (scope gate, each interview turn,
distillation, all six generation stages, assembly) emits `ProgressEvent`s to
an in-process `ProgressBus`:

```
stage:     machine name, stable per pipeline step ('distill_intent')
label:     human present-tense phrase ('Distilling intent model')
status:    'started' | 'completed' | 'failed'
ts:        epoch seconds
elapsed_s: stage duration (completed/failed only)
detail:    optional context ('turn 4', 'stage 3/6')
```

The CLI's stderr printer is ONE consumer. delivery-api and the web UI will
subscribe to (or receive) the same event stream - the founder watches a live
step list, not a spinner. The shape is deliberately identical in
interview-engine and spec-generator (duplicated modules, like errors.py).
**Promotion rule:** when events cross a process boundary to the UI, the shape
moves into vmodel-contracts with a MINOR version bump (ADR-0002). Until then
it is intra-module and documented here.

**Why not print statements:** prints can't feed a UI. **Why not a shared
package now:** nothing crosses a boundary yet; premature contract surface is
its own cost.

### ADR-0011: Checkpoints live on disk; a crash is a resume, not a loss

**Decision.** The CLIs use LangGraph's `SqliteSaver` at
`out/<session>/checkpoints.sqlite` (thread id = session id). A crash
mid-interview, mid-generation, or even at final validation resumes with
`python -m interview_engine.cli --session <id>` (interview) or by rerunning
the same command (spec-generator). Completed stages are never re-paid: the
checkpoint short-circuits them on resume.

**State is JSON-native.** Models and enums enter state via
`model_dump(mode="json")` so the msgpack serde never hits an unregistered
type across LangGraph upgrades (`AppArchetype` is additionally allow-listed
in the serde as belt-and-braces).

**Distillation validates in-node.** The intent model is schema-validated
inside the distill node, with mechanical shape-drift repair
(`source_turns: {}` and friends) plus ONE retry that feeds the validation
error back to the model. A contract-invalid intent model never leaves the
graph. Root cause of the first field crash (2026-09-08): a 14B local model
emitted `source_turns` values as `{}` instead of lists, and validation used
to happen only in the CLI, outside any retry loop.

### ADR-0012: The intent model speaks systems engineering (v0.2.0)

**Decision.** IntentModel now carries `stakeholder_needs[]`: SN-ids, founder
language, each classified `functional` | `non_functional`, each traced to
transcript turns. Needs are distinct from the scope boundary (in/out) and
from requirements - verifiable shall-statements stay downstream in
spec-generator (RequirementSet), which now tags every requirement with the
same `kind` and carries SN->N->R traceability (`intent_need_ids`).

**Classification discipline (taught to the distillation prompt, with his
run-1 counterexamples):** "MFA with a common provider" is a non-functional
security need, not an integration. "No limitation" is not a constraint.
Constraints limit the design space; everything else is a need or scope.

**Version policy refinement (ADR-0002).** Required-field additions may ride
a MINOR bump ONLY because consumers call `check_compatible()` (contracts
compat.py) before reading: a wrong-minor payload fails loudly with the
migration path named, never silently misreads. The approval render now shows
the needs split and says plainly that requirements are derived next.

**Why needs at intent time AND at spec time:** they are different artifacts.
SN = what the founder said they need (approval gate). N = analyzed
stakeholder needs with stakeholder attribution. R = verifiable requirements.
Collapsing them is how PRD generators pretend to be systems engineering.

### ADR-0013: Distillation is phased and visible; assumptions are not needs

**Decision.** Distillation runs as four visible phases on the ProgressEvent
stream (ADR-0010): extract needs -> build scope/framing -> requirement preview
-> assemble/validate. Each LLM phase is small (local-14B friendly), validated
independently, retried once with schema feedback. The preview phase drafts 2-3
SAMPLE derived requirements for the approval gate (the founder sees the SN->R
chain before approving); it is presentation-only and degrades gracefully - the
system of record never depends on it. Preview samples are persisted
(requirement_preview.json) but are NOT contracts; spec-generator derives the
real RequirementSet.

**Quality rules taught to the prompts from run-2 review:** the interviewer
presses ONCE with a concrete counterexample when a founder waves away a
conflict/consistency question, then captures the dismissal as an ASSUMPTION
(IntentModel.assumptions, v0.3.0) - asserted, validated later, never built as
a need. out_of_scope may not be empty (an empty boundary is an unverified
boundary; the renderer says so explicitly if it happens anyway). Constraints
limit the design space only (budget caps, mandated stack, deadlines, team,
external compliance); a quality the system must HAVE is a non-functional need
- no statement appears in two sections.

## 8. What the demo does NOT do (the cut list)

No accounts, no payments, no dashboards, no run-history UI, no multiple
archetypes or target agents, no physical-systems specs, no guarantee of a
working product. The honest claim is "the agent stops guessing," not "the
app ships itself."

## 9. Open decisions carried from the scoping doc

Wizard-of-Oz allowance for the first five runs (decide explicitly so
results are read honestly); magic-link return path if testers need to come
back; Spec Kit layout vs proprietary (ADR-0009, revisit after ten runs);
DeepSeek quality check on moat stages before founder-facing runs.

### ADR-0014: Tier-a method pack - curated static SE knowledge (SWEBOK v4.0a), sectioned per stage

**Decision.** Knowledge augmentation starts with a curated METHOD pack, not
RAG: `method_pack.md` in vmodel-contracts (shipped with the package since
0.3.1, loaded via `load_method_pack(sections=[...])`). The pack is SE
interview/requirements knowledge RESTATED in our own words from the IEEE
SWEBOK Guide v4.0a (Software Requirements KA), with attribution - IEEE's
license permits educational/personal use with citation but not wholesale
redistribution, so no verbatim excerpts ship in the repo. Size is a hard
contract: METHOD_PACK_TOKEN_CAP = 2000, enforced by tests; the pack ships
sectioned ("1".."5") and each stage loads only its slice (interviewer +
distill-needs take taxonomy+elicitation; distill-scope takes conflict/scope;
preview takes well-formed-requirement rules) because prompt tokens on a local
14B are the scarce resource. The pack shapes QUESTIONS and QUALITY BAR only;
it never answers for the founder and never becomes a need by itself.

**Memorization probe.** `tools/swebok_probe/probe_swebok.py` (meta repo)
answers "was the model already trained on SWEBOK v4?" empirically: it samples
distinctive passages from the user's LOCAL PDF copy (no book text in the
repo), asks the local model to complete them, and scores verbatim n-gram
overlap. Stdlib-only, Ollama-only, zero cost.

**Rejected.** True RAG (domain packs with local embeddings + sqlite-vec) is
deferred until a real domain interview proves the method pack insufficient
(user decision 2026-09-08). ISO/IEC/IEEE 29148 and INCOSE are paywalled and
not used; NASA SE Handbook / SWEHB / MITRE SEG remain fallback corpora.

### ADR-0015: Distillation discipline is MECHANICAL, not prompted (run-3 defects)

**Decision.** Prompt-level discipline failed twice (run 2 and run 3), so the
rules moved into deterministic code (`distill_qa.py` in interview-engine,
contracts 0.4.0):

1. **Grounded assumptions.** New `Assumption{statement, source_turns}`
   (min one turn). After distillation, `ground_assumptions` drops any
   assumption whose turns are out of range, whose statement shares no
   vocabulary with its source turns, or that echoes prompt wording (the run-3
   "fabrication" was the model echoing the prompt's own EXAMPLES - the
   concrete examples were removed from prompts AND an echo guard was added).
   The legacy flat `assumptions` field is deprecated and always dropped.
2. **Constraint dedup.** `dedup_constraints` mechanically drops any constraint
   whose content vocabulary is already a classified need (SSO/MFA, no-PII,
   simple, scale in run 3). Constraints limit the design space; the code now
   enforces what the prompt could not.
3. **Provenance-carried exclusions.** New `ScopeExclusion{item, source_turns,
   explicit}`: founder-said exclusions render as boundary; inferred ones
   render as CANDIDATES for confirmation; a deterministic flag marks any
   exclusion sharing vocabulary with the problem statement / core value /
   in-scope (run-3 "excluded predictive analytics from a predict-and-preempt
   product").
4. **Preview solution language.** `is_solution_language` strips criteria that
   name endpoints/status codes/JSON/UI widgets; prompt updated to require
   observable outcomes.
5. **Done-criteria and operational concepts** are first-class captures
   (IntentModel.done_criteria / .operational_concepts), not needs.

Contracts 0.4.0 is additive (new optional models/fields; the deprecated flat
assumptions field still parses) - a MINOR bump per ADR-0002/0012. All module
pins move together because the version gate requires major.minor equality.

### ADR-0016: Coverage model - the interview aims at a checklist, ends on saturation

**Decision.** The probing stage carries an explicit coverage model
(`coverage.py`): 11 fixed elicitation areas (goal, users+stakeholder classes,
flows, data, integrations, QUANTIFIED NFRs, failure modes, constraints, risks,
done-criteria, glossary), each uncovered/thin/covered/skipped in session
state. The interviewer self-reports coverage in a structured JSON turn
(option a: one call per turn, no latency growth) with the
concrete-answers-only closure rule (numbers for NFRs, named systems for
integrations); parse failure degrades to a plain question with coverage
unchanged. Founder control is deterministic: "skip" marks the current target
skipped (never re-asked), "enough" ends without burning a call. The interview
ends on SATURATION (complete=true when everything is covered/skipped), not
turn drift. Per-turn progress line on the ProgressEvent stream; the approval
gate renders the honest coverage map (covered / thin / skipped / not
covered). Glossary is contracts 0.5.0 (additive): IntentModel.glossary pins
the founder's terms to founder meanings.

### ADR-0017: The SRS is a standalone, solution-agnostic artifact - downstream references, never absorbs

**Decision.** spec-generator's requirements stage produces an SRSDocument
(contracts 0.6.0): purpose, scope summary, definitions (carried
DETERMINISTICALLY from the intent glossary - never re-asked of the LLM),
sectioned functional/non-functional requirements, constraints, assumptions,
open questions. Doctrine: the SRS says WHAT is verifiably true, never HOW -
requirement statements and acceptance criteria are observable
shall-statements with no endpoints, status codes, UI widgets, or named
technologies, and no invented artifacts or numbers (the run-5 interview
guards - text_qa, now shared in the contracts package - run mechanically
over SRS output; violations land in the punch list). The executable HOW
(AcceptanceCriterion.executable_hint: http probes, DOM selectors, db checks)
is authored at the TEST stage, where the architecture exists. Architecture
and item specs REFERENCE requirement ids through the traceability matrix;
restating requirement text downstream is a defect the review prompt names.
requirements.md is retired outright; the bundle ships srs.md (manifest
bundle_version 0.2.0). Each V level keeps its own pairing: acceptance tests
pair with SRS criteria, unit/module tests pair with item specs.

**Why.** Run-5 review: the old METHODOLOGY prompt literally taught
solution-flavored criteria ("GET /health returns 200") at the requirements
level, and item specs were told to absorb requirements - the two failure
modes (invented tech, regrouping) the founder flagged. A standalone SRS is
also the artifact a prospect recognizes.


### ADR-0018: Local-first model defaults - Ollama everywhere until production

**Decision.** Every LLM stage in every module (interview-engine probing /
distillation / phrasing / scope_tiebreak, spec-generator needs / srs /
architecture / items / tests / review, verification-loop residue_judge)
defaults to local Ollama (`qwen2.5-coder:7b`; the 14b upgrade is one env
block). Remote providers (DeepSeek, OpenAI, Anthropic) are OPT-IN per stage
via the existing `<MODULE>_MODEL_<STAGE>` env overrides. This reverses the
original DeepSeek-first default.

**Why.** The product owner's standing call, verbatim: "It should all be
ollama by default. We'll change it once we go to production." The demo loop
must run keyless at $0; a default that crashes without an API key (run-5,
spec-generator stage 'needs') is a default pointed the wrong way. Remote
quality for founder-facing runs stays one export away per stage.

