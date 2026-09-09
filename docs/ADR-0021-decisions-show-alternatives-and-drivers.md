# ADR-0021 (ACCEPTED): Architecture decisions show their alternatives and their driver - no arbitrary stack picks

Status: **ACCEPTED (2026-09-09) with the founder's decisions - implemented.**
Date: 2026-09-09
Owner call: Shy, verbatim: "When selecting a stack, I think we need to show
the leading options and explain why the one chosen was chosen (why React and
not Angular?). It can be as simple as a restriction by the user, the most
common solution, most mature ecosystem, etc. But we need to provide
something so it won't be arbitrary."

Decisions applied (Shy, verbatim): "The five drivers seem like an excellent
start. Let's enforce it by contract and do the migration sooner rather than
later. No floor. If no options make sense - no options is fine. We don't
need to trace stack entries to ADRs for now."
1. Driver taxonomy: the five as drafted - closed enum.
2. Enforcement: CONTRACT-REQUIRED, migration shipped with the bump. (Rides
   MINOR 0.7.0 -> 0.8.0 per the standing doctrine: required-field additions
   may ride MINOR because consumers enforce contract_version equality on
   minor before reading - wrong-minor payloads fail loudly, never silently.)
3. Options floor: NONE - zero options is fine (this also moots the proposed
   founder_constraint exemption; the citation cross-check stays).
4. Stack-entry-to-ADR traceability: NOT now.

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

Required-present on `ArchitectureDecision` (driver nullable only for legacy
migration); `vmodel_contracts.migrate` synthesizes the honest legacy form
(driver null, options empty, `rejected` carried) and re-stamps (ADR-0002:
all four module pins move together, one tag per bump):

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

Enforcement is two-layer, mechanically:

- The contract REQUIRES both fields present on every decision (founder
  call: enforce by contract). `driver` is nullable at the contract level
  ONLY so pre-0.8.0 artifacts migrate honestly (null = no retroactive
  driver); the stage validator requires a real enum value on every NEW
  decision.
- NO options floor (founder call): `options_considered` may be empty -
  under a genuine mandate, inventing strawman alternatives is its own
  dishonesty.
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

## Open questions for Shy - all DECIDED (2026-09-09)

1. **Driver taxonomy**: DECIDED - the five as drafted, closed enum.
2. **Enforcement layer**: DECIDED - contract-required; migration shipped
   with the bump (synthesizes driver null + empty options for pre-0.8.0
   artifacts). Rides MINOR per the standing version doctrine.
3. **Options floor**: DECIDED - none. "If no options make sense - no
   options is fine."
4. **Stack traceability**: DECIDED - not now.

Retrieval stays deferred (TODO.md item 1): drivers remain unverified model
judgment, labeled as such at the gate, until ADR-0019 Part 3 lands.
