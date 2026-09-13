#!/usr/bin/env bash
# run-smoke.sh - MEDIUM-speed experiment: a scope-capped end-to-end pipeline
# run in minutes, with the per-item quality report at the end.
#
#   scripts/experiments/run-smoke.sh                       # fixture intent, default caps
#   scripts/experiments/run-smoke.sh --cap-needs 2 --cap-stack 4 --cap-tests 6
#   scripts/experiments/run-smoke.sh --intent <intent_model.json>
#   scripts/experiments/run-smoke.sh --out <dir>           # reuse a dir (resume)
#
# Caps come from VMODEL_CAP_NEEDS / VMODEL_CAP_STACK_SLOTS / VMODEL_CAP_TESTS -
# flags win, then the shared .env, then the defaults below (his one-config-file
# rule: the pipeline reads the shared .env itself; the script never hardcodes
# them INTO the pipeline, only sets its own process env). Caps are exported
# for THIS run only - the shared .env is never written, so a real run can
# never inherit an experiment's scope by accident.
#
# Output goes to artifacts/experiment-<ts>/ - clearly separated from real
# bundles so an experiment is never mistaken for a product spec.
set -euo pipefail

usage() {
  echo "usage: $0 [--intent <intent_model.json>] [--out <dir>]" >&2
  echo "          [--cap-needs N] [--cap-stack N] [--cap-tests N]" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
SG="$REQUIRE_ROOT/spec-generator"
SHARED="$REQUIRE_ROOT/.env"
FIXTURE="$SCRIPT_DIR/fixtures/intent-model.smoke.json"

INTENT="$FIXTURE"
OUT=""
CAP_NEEDS=""; CAP_STACK=""; CAP_TESTS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --intent)    INTENT="${2:?--intent needs a path}"; shift 2 ;;
    --out)       OUT="${2:?--out needs a directory}"; shift 2 ;;
    --cap-needs) CAP_NEEDS="${2:?--cap-needs needs a number}"; shift 2 ;;
    --cap-stack) CAP_STACK="${2:?--cap-stack needs a number}"; shift 2 ;;
    --cap-tests) CAP_TESTS="${2:?--cap-tests needs a number}"; shift 2 ;;
    *) usage ;;
  esac
done

[ -d "$SG" ] || { echo "error: spec-generator not found at $SG" >&2; exit 1; }
[ -f "$INTENT" ] || { echo "error: intent model not found at $INTENT" >&2
  echo "Pass --intent <path>, or restore the fixture at scripts/experiments/fixtures/." >&2; exit 1; }
BASELINE="$SG/examples/system-baseline.greenfield.json"
[ -f "$BASELINE" ] || { echo "error: greenfield baseline template not found at $BASELINE" >&2; exit 1; }

# env-value helper: flag > shared .env > default
conf() { # conf <flag-value> <env-name> <default>
  if [ -n "$1" ]; then printf '%s' "$1"; return; fi
  v=$(grep -E "^$2=" "$SHARED" 2>/dev/null | tail -1 | cut -d= -f2- || true)
  if [ -n "$v" ]; then printf '%s' "$v"; return; fi
  printf '%s' "$3"
}
CAP_NEEDS="$(conf "$CAP_NEEDS" VMODEL_CAP_NEEDS 3)"
CAP_STACK="$(conf "$CAP_STACK" VMODEL_CAP_STACK_SLOTS 6)"
CAP_TESTS="$(conf "$CAP_TESTS" VMODEL_CAP_TESTS 12)"
for n in "$CAP_NEEDS" "$CAP_STACK" "$CAP_TESTS"; do
  case "$n" in (*[!0-9]*|'') echo "error: caps must be positive integers (got '$n')" >&2; exit 1 ;; esac
done

if [ -z "$OUT" ]; then
  ART_ROOT="${VMODEL_ARTIFACTS_DIR:-$REQUIRE_ROOT/artifacts}"
  OUT="$ART_ROOT/experiment-$(date +%Y-%m-%d_%H-%M-%S)"
fi
mkdir -p "$OUT"

export VMODEL_CAP_NEEDS="$CAP_NEEDS" VMODEL_CAP_STACK_SLOTS="$CAP_STACK" VMODEL_CAP_TESTS="$CAP_TESTS"
export VMODEL_LLM_LOG="$OUT/llm-calls.jsonl"
export OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"

echo "== experiment smoke run =="
echo "intent:   $INTENT"
echo "caps:     needs<=$CAP_NEEDS stack<=$CAP_STACK tests<=$CAP_TESTS (FULL runs stay uncapped)"
echo "bundle:   $OUT"
cd "$SG"
python -m spec_generator.cli "$INTENT" --system-baseline "$BASELINE" -o "$OUT"

echo
python -m spec_generator.experiment_report "$OUT"
