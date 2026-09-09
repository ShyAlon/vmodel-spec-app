# ADR-0019 (PROPOSED): Human review gates between generation stages, ecosystem capture in the interview, retrieval-grounded library selection (deferred)

Status: **ACCEPTED (2026-09-09) with the founder's decisions - implemented.**
Date: 2026-09-09
Owner call: Shy, verbatim: "We can skip the gate after needs, gates should be
opt-in, edit n JSON, Eco system should be open but verified, cloud should be
mentioned but not forced."

Decisions applied:
1. G1 (needs gate) is OUT - gates only after the SRS and the architecture.
2. Gates are OPT-IN: `python -m spec_generator.cli ... --review`. Default runs are ungated.
3. Edit surface: raw JSON, contract-validated on save (invalid edits reopen the editor).
4. Ecosystem question is OPEN-worded ("any technology constraints - language/ecosystem,
   cloud affinity?"), and every captured preference is VERIFIED mechanically:
   source_turns required (ungrounded = dropped, same rule as assumptions) and
   unrecognized ecosystem names kept but warned at the approval gate.
5. Cloud is captured as a preference (strength preferred); it binds ONLY when the
   founder explicitly mandates it - never forced.

Two founder observations drive this:

1. "We'll need a human in the loop in between phases. We don't want to specify
   the modules just to realize we had an error in the requirements' generation."
2. "We need to discuss the modules in terms of infrastructure and libraries
   selection - the interview should ask python/node/agnostic and cloud
   affinity, then suggest libraries from that ecosystem. This is where RAG
   (or simply querying web interfaces) can come into play."

---

## Part 1 - Human-in-the-loop review gates between spec-generator stages

### Goal
Never generate module specs on top of unreviewed requirements. A wrong SRS
today cascades into architecture, item specs, tests, and two review rounds
before a human sees anything.

### Precedent that already exists
The interview-engine has exactly this gate: distillation finishes, the CLI
renders the intent model as markdown, asks `Approve this intent model? [y/N]`,
and a rejection abandons the run while the checkpoint preserves everything for
a resume-with-corrections. spec-generator already runs on a disk checkpointer
(SqliteSaver keyed by session id) where rerunning the same command resumes
from the last completed stage with no stage paid for twice.

### Proposed gates
Three gates, at the boundaries where a human decision changes everything
downstream:

| gate | after stage | what the founder reviews | why here |
|---|---|---|---|
| G1 | 1/6 Formalizing stakeholder needs | needs.md (N-ids, stakeholders, implied-vs-stated marks) | wrong needs = wrong everything; cheapest catch |
| G2 | 2/6 Authoring the SRS | srs.md (requirements + acceptance criteria, guard flags visible) | his stated case: module specs must never rest on unreviewed requirements |
| G3 | 3/6 Drafting architecture overview | architecture.md (stack, components, ADRs) | last point where a technology direction can change cheaply |

Stages 4-6 (items, tests, review) run ungated once G3 passes: they are
downstream of approved artifacts, and the existing punch list + review loop
already surfaces their defects.

### What "review" means concretely (CLI)
At each gate the CLI renders the stage artifact as markdown (the same
renderers the bundle uses) and offers four actions:

- **accept** - continue to the next stage.
- **edit** - the artifact's JSON file opens in `$EDITOR`; on save it is
  re-validated against the contract. Invalid edits are refused with the exact
  validation error and the editor reopens - a hand edit can never push
  contract-breaking state downstream. (Markdown is display-only; JSON is the
  edit surface because markdown->JSON re-parsing is lossy.)
- **feedback** - one line of founder language ("the SRS misses offline mode").
  The stage re-runs with the feedback appended to its prompt; downstream
  stages are still checkpoint-valid and re-derive from the new artifact.
- **reject** - abandon the run; the checkpoint is preserved for
  `--session`-style resume exactly like the interview's gate.

### Resume behavior mid-gate
The graph stops after the gated stage (the gate lives in the CLI loop, not
inside the graph - same shape as the interview gate, no dependence on
LangGraph interrupt semantics). A crash or Ctrl-C at a gate: rerun the same
command, the checkpoint restores the completed stage, the gate re-renders and
re-asks. Nothing is paid for twice.

### Cost / risk
Zero model cost added (gates are local I/O). Feedback re-runs cost one stage
call, local = $0. The one new risk is demo flow: a live demo wants the gates,
a scripted smoke run does not - so a `--auto` flag skips all gates (explicitly
opt-out, gates are the default).

---

## Part 2 - Ecosystem and cloud capture in the interview

### The distinction that keeps the doctrine intact
The SRS must stay solution-agnostic (ADR-0015; the mechanical guards flag
named technology in requirements). A founder's ecosystem preference is NOT
solution language - it is a **constraint**: "constraints limit design space"
is the existing doctrine, and constraints are already a first-class
IntentModel field. The preference confines the *architecture* stage (where
naming technologies is its job); it never leaks into the SRS, and the
text_qa guards stay exactly as they are.

### Contract impact (small, additive)
New OPTIONAL field on IntentModel, proposed shape:

```
tech_preferences: list[TechPreference]   # additive optional -> contracts MINOR bump 0.6.1 -> 0.7.0, all four module pins move together (ADR-0002)
  TechPreference: { area: "language" | "framework" | "cloud" | "database" | "infrastructure",
                    preference: str,            # founder's words: "python", "node", "agnostic", "AWS", "no cloud"
                    strength: "required" | "preferred",
                    source_turns: list[int] }   # same provenance discipline as scope_exclusions / assumption_items
```

Because it is optional and additive, existing intent models keep parsing;
`vmodel_contracts.migrate` re-stamps them. The current flat
`constraints: list[str]` stays as the rendered form (the preference lands
there too, e.g. "language: python (founder, required)") - same dual-form
pattern as scope_exclusions/out_of_scope.

### Interview behavior
One coverage-checklist item, asked once, never inferred: "Any technology
constraints - language/ecosystem (python, node, agnostic?), cloud affinity,
existing infra?" An "agnostic" answer is recorded as agnostic (strength
preferred), not treated as silence. Grounding guards are unaffected: the
answer comes from transcript turns, so `source_turns` is real. The
distillation prompt gains one extraction instruction for tech_preferences.

### Architecture-stage behavior
The architecture prompt gains the constraint block: "The founder's technology
constraints: ... - choose stack, libraries, and infrastructure INSIDE this
ecosystem; where the founder is agnostic, state that the choice is yours and
why." ADRs record the constraint as their driver, so the choice is auditable
rather than silent. The existing invented-tech guard for the SRS is
untouched; architecture output is allowed (expected) to name technology.

---

## Part 3 - Retrieval-grounded library selection (DEFERRED phase)

### What it would add
Currency. A local 14b model's library knowledge has a training cutoff: it
will confidently name a deprecated package or a stale version. Retrieval
(fetching the library's current docs / llms.txt / package-registry metadata
at architecture time) grounds "use X v3" claims in something checked today,
and gives the ADR a citation.

### What it costs
Moving parts: a fetch layer (rate limits, flaky sites, bot walls), a
freshness policy, a citation format in the contract, and a fallback path when
the network is down (local-first means the pipeline must still run offline).
None of it is free-tier *money*, but it is real complexity on the critical
path of the demo.

### Why deferred
Parts 1 and 2 change what the founder approves and constrain what the model
may choose - they fix correctness errors, which compound downstream. Part 3
fixes currency errors, which are visible, citeable, and cheap to correct at
the G3 gate (the founder reads the architecture before anything builds on
it). Land gates + ecosystem capture first; add retrieval when a real run
shows a stale-library miss that the G3 gate did not catch. When it lands,
stay zero-cost: direct fetches of public docs/registries and the local
embeddings already in verification-loop - no paid vector DB, no paid search
API.

---

## Open questions for Shy

1. **Gate set**: DECIDED - G1 skipped, gates after SRS + architecture only.
2. **Default posture**: DECIDED - opt-in `--review`.
3. **Edit surface**: DECIDED - raw JSON in $EDITOR, contract-validated.
4. **Feedback blast radius**: when G2 feedback re-runs the SRS, downstream
   stages re-derive automatically (checkpoint-invalidated). Acceptable, or
   should feedback be scoped tighter?
5. **Ecosystem question wording**: DECIDED - open-worded, with mechanical verification of what gets captured.
6. **Cloud as constraint vs decision**: DECIDED - mentioned, recorded as preferred, never forced; binding only on explicit mandate.
7. **Retrieval trigger**: what evidence should open Part 3 - first observed
   stale-library miss, or a scheduled phase after the demo?

## Decision points needed before implementation
- Approve/adjust the gate set and default posture (Q1, Q2).
- Approve the TechPreference contract shape and the 0.7.0 minor bump (Part 2).
- Confirm Part 3 stays deferred and what re-opens it (Q7).
