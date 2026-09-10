# Shared scripts

Cross-repository commands for a checkout where the projects are siblings under
`~/development/require/`. This is the general scripts home for the V-model
workspace.

## Batch spec generation

`batch-specs.py` takes over after you finish and approve interviews. You may
queue sessions over several days, then process them sequentially. Local Ollama
runs are intentionally never parallel: with phi4, plan on roughly 2.5-3 hours
per full spec. The runner prints the run count and total estimate before it
starts.

Each queued run gets a dedicated directory under spec-generator:

```text
~/development/require/spec-generator/artifacts-YYYY-MM-DD_HH-MM-SS/
```

The queue and its state live in
`~/development/require/vmodel-spec-app/batch-specs.json`. Reports are written
next to it as `batch-report.json` and `batch-report.md`.

### 1. Queue an approved interview

Replace `<session>` with the session directory printed by interview-engine.
The intent model must already have passed your interactive approval step.

```bash
cd ~/development/require/vmodel-spec-app
python scripts/batch-specs.py add ../interview-engine/out/<session>/intent_model.json
```

Run that command after each interview. Existing queue entries stay in the
manifest, so you can build the queue over time.

### 2. Optional: repeat one interview to measure variance

A repeat uses the same approved intent model but generates a separate full
bundle and artifacts directory each time.

```bash
cd ~/development/require/vmodel-spec-app
python scripts/batch-specs.py add ../interview-engine/out/<session>/intent_model.json --repeat 3 --name booking
```

Use a unique `--name` if that session was already queued.

### 3. Run the queue

This processes queued entries one at a time and stops on the first real
failure. It also captures `llm-calls.jsonl` inside each artifacts directory
and refreshes both batch reports after every completed run.

```bash
cd ~/development/require/vmodel-spec-app
python scripts/batch-specs.py run
```

To run only the next queued entry:

```bash
cd ~/development/require/vmodel-spec-app
python scripts/batch-specs.py run --limit 1
```

If the process is interrupted, run the same command again. A run left in the
`running` state keeps its assigned artifacts directory, so spec-generator
resumes from that directory's checkpoint.

### 4. Retry a diagnosed failure

A nonzero exit marks the run `failed` and stops the queue. Fix the cause first,
then use the run id printed in the failure message:

```bash
cd ~/development/require/vmodel-spec-app
python scripts/batch-specs.py retry <run-id>
python scripts/batch-specs.py run
```

Retry keeps the same artifacts directory and checkpoint. It does not silently
start over.

### 5. Rebuild reports without generating

```bash
cd ~/development/require/vmodel-spec-app
python scripts/batch-specs.py report
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
python scripts/batch-specs.py --manifest batches/checkout.json add ../interview-engine/out/<session>/intent_model.json
python scripts/batch-specs.py --manifest batches/checkout.json run
python scripts/batch-specs.py --manifest batches/checkout.json report
```

## Full interactive flow

Runs interview-engine and, after approval, spec-generator with review gates:

```bash
cd ~/development/require/vmodel-spec-app
scripts/run-full-flow.sh "a marketplace for surf lessons in Tel Aviv"
```

Resume an interrupted interview:

```bash
cd ~/development/require/vmodel-spec-app
scripts/run-full-flow.sh --session <session>
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
