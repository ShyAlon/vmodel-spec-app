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

## Run it locally

Prereqs: Python 3.10+, git, and (for offline runs) [Ollama](https://ollama.com).

```bash
# 1. Clone what you need
git clone https://github.com/ShyAlon/vmodel-spec-app.git       # docs (this repo)
git clone https://github.com/ShyAlon/vmodel-contracts.git      # always required
git clone https://github.com/ShyAlon/interview-engine.git      # core loop
git clone https://github.com/ShyAlon/spec-generator.git        # core loop
git clone https://github.com/ShyAlon/verification-loop.git     # verify a build
git clone https://github.com/ShyAlon/delivery-api.git          # only for the hosted API layer

# 2. One venv at the parent folder
python3 -m venv .venv && source .venv/bin/activate
pip install -e "./vmodel-contracts[dev]"
pip install -e "./interview-engine[dev]"
pip install -e "./spec-generator[dev]"
pip install -e "./verification-loop[dev]"
```

Modules pin `vmodel-contracts` from its GitHub tag; pip uses your local git
credentials for that fetch. If the pin fetch fails, fall back per module:
`pip install -e . --no-deps && pip install langgraph langchain-core langchain-openai httpx pytest`.

```bash
# 3. Tests (no API key needed for the deterministic suites)
cd interview-engine && pytest -q && cd ..

# 4. Ollama for local LLM runs (offline, $0)
Model size: `qwen2.5-coder:7b` is the default recommendation and runs fine on
a 16GB machine. `qwen2.5-coder:14b` is better but wants 32GB+ RAM. Set
`OLLAMA_NUM_PARALLEL=1` so Ollama never loads two models at once (the chat
model plus `nomic-embed-text` would otherwise compete for RAM).

ollama pull qwen2.5-coder:7b && ollama pull nomic-embed-text

# 5. First end-to-end pass: interview -> intent model (you approve it)
export INTERVIEW_ENGINE_MODEL_PROBING=ollama:qwen2.5-coder:7b
export INTERVIEW_ENGINE_MODEL_DISTILLATION=ollama:qwen2.5-coder:7b
export INTERVIEW_ENGINE_MODEL_PHRASING=ollama:qwen2.5-coder:7b
export INTERVIEW_ENGINE_MODEL_SCOPE_TIEBREAK=ollama:qwen2.5-coder:7b
python -m interview_engine.cli "a marketplace for surf lessons in Tel Aviv"
# -> out/<session>/intent_model.json (+ .md for review, usage.jsonl for cost)

# 6. Intent -> full spec bundle
for s in NEEDS REQUIREMENTS ARCHITECTURE ITEMS TESTS REVIEW; do
  export SPEC_GENERATOR_MODEL_$s=ollama:qwen2.5-coder:7b
done
python -m spec_generator.cli out/<session>/intent_model.json -o bundle/
# -> bundle/AGENTS.md, specs/, manifest.json, traceability.json, tests.json
```

To run against DeepSeek instead of Ollama: skip the `*_MODEL_*` exports and
`export DEEPSEEK_API_KEY=...`. Every stage's model is an env override; see
`model_config.py` in each module. Caveat from ADR-0003: local models are the
dev loop - judge demo quality on the real provider, because the interview and
the verdicts are the moat.
