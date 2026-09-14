# Shared scripts

Cross-repository commands for a checkout where the projects are siblings under
`~/development/require/`. This is the general scripts home for the V-model
workspace.

## Batch spec generation

`batch-specs.sh` can run the complete founder-driven batch flow: it opens the
native interactive interview repeatedly, queues each approved session, and
asks whether you want another. When you answer no (or `done` / `enough`), it
starts sequential spec generation automatically. You may
queue sessions over several days, then process them sequentially. Local Ollama
runs are intentionally never parallel: with phi4, plan on roughly 3.5-4 hours
per full spec on an unthrottled M4 Air. A resumed run with `tests.json` already
present scales the estimate from its actual test count. The runner prints the
run count and total estimate before it starts.

Each queued run gets a dedicated directory under spec-generator:

```text
~/development/require/artifacts/artifacts-YYYY-MM-DD_HH-MM-SS/
```

The entry point is Bash, so interactive stdin/stdout pass through unchanged.
It calls the adjacent Python helper for JSON state and report calculations;
rewriting those data operations in Bash would make them less safe and testable.

The queue and its state live in
`~/development/require/vmodel-spec-app/batch-specs.json`. Reports are written
next to it as `batch-report.json` and `batch-report.md`.

### 1. Run interviews, then generate every queued spec

This is the main workflow. If queued or interrupted spec runs already exist, bare invocation first asks whether to run that queue (the default) or start a fresh interview. Otherwise it starts the interview directly. Conduct and approve each interview normally. The
script queues it, then asks `Create another interview? [Y/n]`. Press Enter to
start another. Answer `n`, `done`, or `enough` to stop interviewing and begin
sequential spec generation immediately.

```bash
cd ~/development/require/vmodel-spec-app
bash scripts/batch-specs.sh
```

The script has a Bash shebang and also recovers if it is accidentally invoked as
`zsh scripts/batch-specs.sh` or `sh scripts/batch-specs.sh` by re-executing itself
under Bash. The explicit `bash` form above is the clearest macOS invocation.

To queue an interview you already completed, use the manual subcommand:

```bash
cd ~/development/require/vmodel-spec-app
scripts/batch-specs.sh add ../interview-engine/out/<session>/intent_model.json
```

Existing queue entries stay in the manifest, so you can add sessions over time.

### Contract versions heal themselves

`add` (and `run`, again right before each job starts) passes the intent model
through the validating migrator (`python -m vmodel_contracts.migrate`). An
intent from an older but compatible contract release is re-stamped to the
installed version - validated against the current schema first, never blindly -
and the old -> new version is recorded in `batch-specs.json` and in the run's
`run.log`. An intent with real schema drift is refused untouched, with the
migrator's field errors: re-run that interview instead. An intent NEWER than
the installed contracts means this checkout is behind: pull and reinstall the
repos, do not re-run the interview.

`run` also starts with a repo-consistency preflight: interview-engine and
spec-generator must pin the same vmodel-contracts release tag in their
`pyproject.toml`. On a mismatch it names the repo that is behind and prints
the exact `git pull && pip install -e ".[dev]"` fix, then stops before any
queued hours are burned.

### 2. Optional: repeat one interview to measure variance

A repeat uses the same approved intent model but generates a separate full
bundle and artifacts directory each time.

```bash
cd ~/development/require/vmodel-spec-app
scripts/batch-specs.sh add ../interview-engine/out/<session>/intent_model.json --repeat 3 --name booking
```

Use a unique `--name` if that session was already queued.

### 3. Run the queue

This processes queued entries one at a time and stops on the first real
failure. It captures `llm-calls.jsonl` and a terminal mirror in `run.log` inside each
artifacts directory, then refreshes both batch reports after every completed run.
A failed run prints that durable log path, so diagnostics do not depend on terminal scrollback.

```bash
cd ~/development/require/vmodel-spec-app
scripts/batch-specs.sh run
```

To run only the next queued entry:

```bash
cd ~/development/require/vmodel-spec-app
scripts/batch-specs.sh run --limit 1
```

If the process is interrupted, run the same command again. A run left in the
`running` state keeps its assigned artifacts directory, so spec-generator
resumes from that directory's checkpoint.

### Overnight runs on macOS

On macOS, the queue launches each spec-generator child under `caffeinate -dims`.
That keeps the system and display awake and prevents idle or disk sleep for the
life of the child; other platforms run the same command without a wrapper. Keep
the Mac plugged into power. Closing a MacBook lid can still force sleep, so
leave the lid open unless it is connected to an external display and power in a
supported closed-display setup.

A sleep or power-management throttle looks different from a larger model call:
`llm-calls.jsonl` shows roughly the same token counts as normal calls, but wall
latency and `ttft_s` jump from about 1-2 minutes to 20-30 minutes. Rising TTFT at
unchanged token counts points to host-side sleep, thermal pressure, or memory
pressure/swap rather than the model producing more work.

### 4. Retry a diagnosed failure

A nonzero exit marks the run `failed` and stops the queue. Fix the cause first,
then use the run id printed in the failure message:

```bash
cd ~/development/require/vmodel-spec-app
scripts/batch-specs.sh retry <run-id>
scripts/batch-specs.sh run
```

Retry keeps the same artifacts directory and checkpoint. It does not silently
start over.

### 5. Rebuild reports without generating

```bash
cd ~/development/require/vmodel-spec-app
scripts/batch-specs.sh report
```

The reports include artifact counts; requirement-to-spec and
criterion-to-test coverage gaps; test-definition shape checks; runner mix;
wall time; token/cost totals; LLM latency and time-to-first-token when logged;
and hashes for SRS, items, and tests. Repeats of the same interview get a
variance summary. Different sessions appear as side-by-side coverage runs.

### Use a different manifest

The default manifest is `batch-specs.json` in your current directory. To keep
separate queues, pass the same explicit manifest to every command:

```bash
cd ~/development/require/vmodel-spec-app
scripts/batch-specs.sh --manifest batches/checkout.json add ../interview-engine/out/<session>/intent_model.json
scripts/batch-specs.sh --manifest batches/checkout.json run
scripts/batch-specs.sh --manifest batches/checkout.json report
```

## One new interview, one new spec bundle

Two single-purpose commands for the from-zero flow (fresh session, fresh
timestamped artifacts - nothing reused):

```bash
cd ~/development/require/vmodel-spec-app
scripts/new-interview.sh "a marketplace for surf lessons in Tel Aviv"
# Interview produces paired Intent Model + Concept of Operations artifacts.
scripts/new-spec.sh --greenfield                       # a NEW product (auto-picks the newest session)
scripts/new-spec.sh <session> --greenfield             # name the session explicitly
scripts/new-spec.sh --baseline vmodel-spec-app/system-baseline.json   # the V-model system itself
```

The baseline is always an explicit choice - a new product anchored to some
other system's baseline produces a grounded-but-wrong architecture.
--greenfield materializes a per-session greenfield baseline next to the
session's intent model.

Resume an interrupted interview or Concept of Operations decision with `scripts/new-interview.sh --session <id>`. The Concept of Operations stage compares product concepts and records the founder's explicit choice in `conops.json`; `new-spec.sh` always passes that artifact downstream.

## Full interactive flow

Runs interview-engine and, after approval, spec-generator with review gates:

```bash
cd ~/development/require/vmodel-spec-app
scripts/run-full-flow.sh "a marketplace for surf lessons in Tel Aviv" --greenfield
scripts/run-full-flow.sh "improve the spec pipeline" --baseline vmodel-spec-app/system-baseline.json
```

Resume an interrupted interview:

```bash
cd ~/development/require/vmodel-spec-app
scripts/run-full-flow.sh --session <session> --greenfield
```

## Switch every process to one model

Ollama remains the zero-cost default:

```bash
cd ~/development/require/vmodel-spec-app
scripts/switch-model.sh ollama
```

Switch to current DeepSeek V4.1 Flash or OpenAI. The script asks for the API
key through a hidden prompt when it is not already exported.

```bash
cd ~/development/require/vmodel-spec-app
scripts/switch-model.sh deepseek
```

```bash
cd ~/development/require/vmodel-spec-app
scripts/switch-model.sh openai
```


## Collecting run analysis

`collect-analysis.sh` packs one run's analysis data into a single bundle to
send for review. With no argument it picks the newest COMPLETED run
(`manifest.json` present) across both roots - the workspace-sibling
`artifacts/` folder (the default since 2026-09-12) and `spec-generator/`
(explicit `-o` and pre-change runs); newer stage experiments are skipped with
a note, and an experiments-only tree falls back to the newest experiment with
an honest label. Pass `--artifacts <dir>` (or the dir alone) to pick a
specific run. It includes the LLM call log, usage log, run.log, every stage
artifact that exists, `specs/`, any `*.partial.json` resume state, and the
batch report, plus a `MANIFEST.json` saying exactly what was found, included,
and missing. It prints a one-look summary - run status, per-stage call
counts, models, wall time, token totals - and the exact bundle path to send:

```bash
bash vmodel-spec-app/scripts/collect-analysis.sh
bash vmodel-spec-app/scripts/collect-analysis.sh --artifacts spec-generator/artifacts-2026-09-10_20-55-21
```

The bundle lands next to the run as `<artifacts-dir>-analysis-<timestamp>.tar.gz`.
Binary run state (`checkpoints.sqlite`) is excluded by design.

## Experiments (MEDIUM speed tier)

Scope-capped end-to-end smoke runs, minutes instead of hours, with a
per-item quality report at the end:

```bash
scripts/experiments/run-smoke.sh                                  # fixture intent, default caps
scripts/experiments/run-smoke.sh --cap-needs 2 --cap-stack 4 --cap-tests 6
scripts/experiments/run-smoke.sh --intent <intent_model.json>     # a real interview's intent
```

Caps resolve: flag > shared .env (VMODEL_CAP_NEEDS / VMODEL_CAP_STACK_SLOTS /
VMODEL_CAP_TESTS) > defaults (3/6/12). The script exports caps for its own
process only and NEVER writes the shared .env - a real run cannot inherit an
experiment's scope. Bundles land in artifacts/experiment-<ts>/, clearly
separate from real product bundles, and include llm-calls.jsonl so the
closing report shows first-pass rate, retries, provider errors, stage
timings and cost. Compare experiment runs on those numbers; validate real
conclusions with an uncapped FULL run.
