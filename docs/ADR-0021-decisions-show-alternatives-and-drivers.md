# ADR-0021 (PROPOSED): Architecture decisions show their alternatives and their driver - no arbitrary stack picks

Status: **PROPOSED (2026-09-09) - awaiting founder decision.**
Date: 2026-09-09
Owner call: Shy, verbatim: "When selecting a stack, I think we need to show
the leading options and explain why the one chosen was chosen (why React and
not Angular?). It can be as simple as a restriction by the user, the most
common solution, most mature ecosystem, etc. But we need to provide
something so it won't be arbitrary."

## Context

The architecture stage names a stack and records ADRs (`decision`,
`rationale`, `rejected: list[str]`). Three gaps against the founder's ask:

1. `rejected` is a flat string list - options and their rejection reasons
   crammed into unstructured prose. Nothing forces an alternative to exist:
   a decision with empty `rejected` is contract-valid and reads arbitrary.
2. Nothing classifies WHY the winner won. "The founder mandated it" and
   "the model happens to prefer it" render identically today - but they
   deserve very different scrutiny at the review gate.
3. Where a founder constraint drives the choice (ADR-0019 Part 2), the
   citation rule lives in the PROMPT ("every ADR names the constraint that
   drove it") - prompt discipline, the one thing the doctrine says never to
   trust (mechanical guards over prompt discipline, ADR-0020).

## Decision (proposed)

### Contract impact - vmodel-contracts 0.7.0 -> 0.8.0 (MINOR)

Additive optional on `ArchitectureDecision`; existing payloads keep parsing
and `vmodel_contracts.migrate` re-stamps them (ADR-0002: all four module
pins move together, one tag per bump):

```
driver: Literal["founder_constraint", "ecosystem_maturity", "community_adoption",
                "team_fit", "simplicity"] | None     # ADDED 0.8.0 - why the winner won
options_considered: list[ConsideredOption]           # ADDED 0.8.0 - the losers, structured
  ConsideredOption: { option: str,                   # "Angular", "Vue"
                      reason: str }                  # why it lost - one prose sentence
rejected: list[str]   # DEPRECATED 0.8.0 - kept so 0.7.x payloads parse; new producers
                      # leave it empty. Same dual-form precedent as
                      # assumptions -> assumption_items, out_of_scope -> scope_exclusions.
```

The contract keeps both fields OPTIONAL (backward compatibility); the
REQUIREMENT lives in the architecture-stage validator, mechanically:

- Every NEW decision carries a `driver` from the closed enum.
- Unless `driver == "founder_constraint"`, at least one `ConsideredOption`
  with a non-empty reason is required. Under a genuine founder mandate zero
  alternatives are allowed - inventing strawman alternatives to fill the
  list is its own dishonesty.
- `driver == "founder_constraint"` must cite a `TechPreference` that EXISTS
  in the intent model (the stage validator has it in scope - a cross-check,
  not a prompt hope). This lands ADR-0019's "ADRs record the constraint as
  their driver" as a mechanical rule.
- The chosen option (named in `decision`) must not also appear in
  `options_considered`.

### Prompt / skeleton impact - ADR-0020 propose/dispose unchanged

Architecture keeps its bulk-propose freedom (structure there genuinely is
analysis); code still assigns `ADR-n` ids and ids stay out of the grammar.
The model's per-decision fill grows by `driver` + `options_considered`.
Code owns: id assignment, enum membership, the founder-constraint citation
cross-check, the chosen-not-also-rejected check. The prompt gains the
driver taxonomy with one-line definitions and one instruction: "name the
real leading alternatives for this archetype, not strawmen."

### Gate rendering - the G3 gate gets something to bite on

`render_architecture` decisions section becomes:

```
- **ADR-1 Frontend framework** - React
  Driver: ecosystem maturity (model judgment - unverified; challenge here)
  Why: ...
  Considered: Angular - rejected: ...; Vue - rejected: ...
```

The founder can now veto the driver, veto the reasoning, or demand an
option the model never listed - the existing feedback action re-runs the
stage with that line.

### Honesty boundary

Driver classifications and option reasons from a local 14b are UNVERIFIED
ASSERTIONS with a training cutoff: "most mature ecosystem" is a claim, not
a fact. This ADR does not fix currency - it makes the claim STRUCTURED and
VISIBLE so the G3 gate can veto it. Verification belongs to
retrieval-grounded library selection (ADR-0019 Part 3, deferred); when that
lands, driver reasons gain citations and the honesty gap closes at the
source. Until then the gate renderer labels every driver "model judgment -
unverified" - same kept-but-warned posture as unrecognized ecosystem names
in ADR-0019.

## Consequences

- Contracts 0.7.0 -> 0.8.0 MINOR; four module pins + tag; migrate re-stamps
  old payloads (driver None, options empty, `rejected` carried).
- SRS guards untouched - architecture output names technology by design;
  the SRS stays solution-agnostic.
- interview-engine unchanged: `TechPreference` is already the constraint
  source; this ADR consumes it.
- One founder-visible behavior change: an architecture draft missing
  drivers/options fails stage validation and re-asks (same retry path as
  any contract failure), so a bare stack pick can no longer reach the gate.

## Open questions for Shy

1. **Driver taxonomy**: founder_constraint / ecosystem_maturity /
   community_adoption / team_fit / simplicity - the right five? Candidate
   additions: "cost" (the zero-cost doctrine drives real choices in this
   very project), "performance". And: closed enum, or free-text with the
   five as guidance?
2. **Enforcement layer**: contract-optional + stage-required (proposed -
   preserves compat, MINOR bump), or contract-required (MAJOR bump,
   migration synthesizes empty values for old payloads)?
3. **Options floor**: >=1 rejected option per decision except under
   founder_constraint (proposed) - or stricter (>=2)?
4. **Stack traceability**: should the validator also require every `stack`
   dict entry to trace to a decision (no un-ADR'd stack picks), or is that
   over-fitting?

## Decision points needed before implementation

- Approve/adjust the `ConsideredOption` shape, the driver enum, and the
  0.8.0 minor bump.
- Pick the enforcement layer (Q2) and the options floor (Q3).
- Confirm retrieval stays deferred - drivers remain unverified model
  judgment until ADR-0019 Part 3.
