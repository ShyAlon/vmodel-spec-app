# Architecture identity registry and projection design

## Problem

Architecture currently asks a model to state the same fact in several places: a stack value, an ADR title/body, and free-text gate evidence. A later string scan tries to prove they agree. This admits split-brain drafts and repair oscillation.

## Invariants

1. Cross-artifact facts have stable IDs. Requirements already do. CONOPS options gain `concept_id`; technologies resolve to canonical `technology_id` values from one alias registry.
2. Normalization is a boundary operation: Unicode case-fold, punctuation/spacing collapse, then exact alias lookup. Core gates compare IDs only. Unknown technology text becomes `off-list:<normalized-slug>` and requires a non-empty structured justification before it enters state.
3. Every stack choice is owned by exactly one ADR through a structured `technology_selections` field. `stack_entries` are generated projections of those selections. A stack value with no ADR cannot be assembled.
4. ADRs declare `executes_concept_ids`. CONOPS execution compares the selected concept ID to that list. Prose is never evidence for execution.
5. Fuzzy text comparison exists only in duplicate advisories. It uses normalized token Jaccard distance with published threshold 0.8. Advisories never mutate decisions.

## Compatibility

This is contracts 0.15.0 because required identity fields change producer/consumer expectations. Migration derives concept IDs from existing option names, resolves known stack values through the registry, and marks unknown values as off-list. Unknown values without a recoverable ADR justification cannot be migrated silently.

The current 0.14 supply-chain spec checkpoint contains pre-identity partial architecture state and cannot be resumed safely. Keep interview artifacts, migrate intent/CONOPS to 0.15, then start a fresh `spec-identity` generation. No interview answers are lost.
