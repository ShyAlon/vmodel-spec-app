#!/usr/bin/env bash
# new-spec.sh - run the full spec pipeline against an interview's intent model.
#
#   scripts/new-spec.sh              # newest interview session (ls -t)
#   scripts/new-spec.sh <session>    # an explicit session id
#
# Writes a BRAND NEW timestamped bundle to artifacts/artifacts-<ts>/
# (AGENTS.md, srs.md, needs.md, architecture.md, specs/, traceability.json).
# Old bundles stay untouched; a crash resumes by rerunning the same command.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SG="$REQUIRE_ROOT/spec-generator"
IE="$REQUIRE_ROOT/interview-engine"
BASELINE="$REQUIRE_ROOT/vmodel-spec-app/system-baseline.json"
[ -d "$SG" ] || { echo "error: spec-generator not found at $SG" >&2; exit 1; }
[ -f "$BASELINE" ] || { echo "error: system baseline not found at $BASELINE" >&2; exit 1; }

if [ $# -ge 1 ]; then
  SESSION="$1"
else
  SESSION="$(ls -t "$IE/out" 2>/dev/null | head -1 || true)"
  [ -n "$SESSION" ] || { echo "error: no interview sessions in $IE/out - run scripts/new-interview.sh first" >&2; exit 1; }
fi

INTENT="$IE/out/$SESSION/intent_model.json"
[ -f "$INTENT" ] || { echo "error: no approved intent model at $INTENT" >&2
  echo "Resume the interview with: scripts/new-interview.sh --session $SESSION" >&2; exit 1; }

export OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"

echo "== spec generation for session $SESSION =="
cd "$SG"
python -m spec_generator.cli "$INTENT" --system-baseline "$BASELINE"

echo
echo "Done. Bundle: newest directory under $REQUIRE_ROOT/artifacts/ (printed above)."
echo "Redo one stage under newer code: python -m spec_generator.cli $INTENT --system-baseline $BASELINE --from <stage>"
