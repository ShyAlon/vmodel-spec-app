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
| spec-generator | needs -> requirements -> architecture -> item specs -> tests, staged drafts, review passes | `StakeholderNeedsSet`, `RequirementSet`, `ArchitectureOverview`, `SpecBundle`, `SpecManifest`, `AcceptanceTest` set | `IntentModel` |
| verification-loop | founder-side test package, deterministic checks, semantic-residue judging, verdict report | `VerificationReport`, runner artifact | `SpecBundle` + build artifact ref |
| delivery-api | run links, run state machine, background jobs, storage, budget hard stop, cost ledger | `RunLink`, `RunStatus`, `RunCostReport`, `DeliveryBundle` | everything, through contracts |
| vmodel-contracts | the boundary itself | versioned models + JSON Schemas | - |

---

## 3. Decision records

### ADR-0001: Separate repositories, versioned contracts from day one

**Decision.** Five repositories, not a monorepo. The contracts between
modules are real versioned artifacts: `vmodel-contracts` is a published
package; each module pins an exact release
(`vmodel-contracts @ git+https://github.com/ShyAlon/vmodel-contracts.git@v0.1.0`).

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
