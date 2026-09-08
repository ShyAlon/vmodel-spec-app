# vmodel-spec-app

*You talk to it for an hour about your product idea; it hands your coding agent
a spec rigorous enough that the agent stops guessing.*

An interview-to-specification service: a founder's rough idea in, a complete
systems-engineering artifact set out (stakeholder needs, system requirements,
architecture, item-level specs, unit-to-acceptance test hierarchy, V&V
traceability), packaged as machine-readable input for coding agents - plus the
verification loop no competitor ships: does the build actually match the spec?

**Start here: [ARCHITECTURE.md](ARCHITECTURE.md)** - every decision, with reasoning.

## The repositories

| Repo | Role | Boundary artifacts |
|---|---|---|
| [vmodel-contracts](https://github.com/ShyAlon/vmodel-contracts) | The versioned contract bundle. **The actual architecture.** Every module pins an exact release. | All models |
| [interview-engine](https://github.com/ShyAlon/interview-engine) | Adaptive systems-engineering interview. The moat. | `ScopeVerdict`, `InterviewTranscript`, `IntentModel` |
| [spec-generator](https://github.com/ShyAlon/spec-generator) | IntentModel -> V-model artifact bundle. | `SpecBundle`, `SpecManifest`, `AcceptanceTest` set |
| [verification-loop](https://github.com/ShyAlon/verification-loop) | Deterministic-first build-vs-spec verification. | `VerificationReport`, founder-side runner |
| [delivery-api](https://github.com/ShyAlon/delivery-api) | Orchestration: links, run state, jobs, budgets, cost ledger. | `RunLink`, `RunStatus`, `RunCostReport` |

## Current state

Runnable skeletons: every repo has a passing test suite, pinned contract
dependency, and a CLI or HTTP entry point. LLM stages default to DeepSeek
(config-swappable per stage). Deterministic stages work today without any API
key.

## Scope (v1)

Web applications only - including apps that consume web APIs and services.
Anything else (native mobile, desktop, hardware, CLI tooling) gets a polite,
specific decline at intake. Five archetypes named; one opinionated stack for
the demo. One target agent: Claude Code. Step 2 (physical systems) is
deliberately out.
