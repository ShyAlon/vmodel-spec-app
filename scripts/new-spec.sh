#!/usr/bin/env bash
# new-spec.sh - run the full spec pipeline against an interview's intent model.
#
#   scripts/new-spec.sh [session] --greenfield       # a NEW product (no existing system)
#   scripts/new-spec.sh [session] --baseline <path>  # an existing system's checked baseline
#
# The baseline is the architecture's anchor. It is an EXPLICIT choice, always:
# silently anchoring a new product to some other system's baseline produces a
# grounded-but-WRONG architecture (2026-09-12 review). Omit the session to use
# the newest interview.
#
# Writes a BRAND NEW timestamped bundle to artifacts/artifacts-<ts>/
# (AGENTS.md, srs.md, needs.md, architecture.md, specs/, traceability.json).
# Old bundles stay untouched; a crash resumes by rerunning the same command.
set -euo pipefail

usage() { echo "usage: $0 [session] (--greenfield | --baseline <path>)" >&2; exit 1; }

SESSION=""
BASELINE=""
GREENFIELD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --greenfield) GREENFIELD=1; shift ;;
    --baseline)   BASELINE="${2:?--baseline needs a path}"; shift 2 ;;
    -*)           usage ;;
    *)            [ -z "$SESSION" ] && SESSION="$1" || usage; shift ;;
  esac
done
[ "$GREENFIELD" -eq 1 ] && [ -n "$BASELINE" ] && usage
[ "$GREENFIELD" -eq 0 ] && [ -z "$BASELINE" ] && {
  echo "error: choose the architecture anchor explicitly:" >&2
  echo "  --greenfield        a brand-new product (no existing system)" >&2
  echo "  --baseline <path>   an existing system's checked baseline" >&2
  echo "This is deliberate: a wrong baseline is a grounded-but-wrong architecture." >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SG="$REQUIRE_ROOT/spec-generator"
IE="$REQUIRE_ROOT/interview-engine"
[ -d "$SG" ] || { echo "error: spec-generator not found at $SG" >&2; exit 1; }
# an explicit --baseline path is validated before anything else touches disk
if [ "$GREENFIELD" -eq 0 ]; then
  [ -f "$BASELINE" ] || { echo "error: system baseline not found at $BASELINE" >&2; exit 1; }
fi

if [ -z "$SESSION" ]; then
  SESSION="$(ls -t "$IE/out" 2>/dev/null | head -1 || true)"
  [ -n "$SESSION" ] || { echo "error: no interview sessions in $IE/out - run scripts/new-interview.sh first" >&2; exit 1; }
fi

INTENT="$IE/out/$SESSION/intent_model.json"
CONOPS="$IE/out/$SESSION/conops.json"
[ -f "$INTENT" ] || { echo "error: no approved intent model at $INTENT" >&2
  echo "Resume the interview with: scripts/new-interview.sh --session $SESSION" >&2; exit 1; }
[ -f "$CONOPS" ] || { echo "error: no approved Concept of Operations at $CONOPS" >&2
  echo "Resume the interview with: scripts/new-interview.sh --session $SESSION" >&2; exit 1; }

if [ "$GREENFIELD" -eq 1 ]; then
  # materialize a per-session greenfield baseline from the spec-generator
  # template; it lives next to the intent model and says out loud what it is
  TEMPLATE="$SG/examples/system-baseline.greenfield.json"
  [ -f "$TEMPLATE" ] || { echo "error: greenfield template not found at $TEMPLATE" >&2; exit 1; }
  BASELINE="$IE/out/$SESSION/greenfield-baseline.json"
  SESSION="$SESSION" python3 - "$TEMPLATE" "$BASELINE" <<'PY'
import json, os, sys
template, out = sys.argv[1], sys.argv[2]
d = json.load(open(template))
d["baseline_id"] = f"greenfield-{os.environ['SESSION']}"
d["system_name"] = f"Greenfield product (interview session {os.environ['SESSION']})"
json.dump(d, open(out, "w"), indent=2)
PY
fi
[ -f "$BASELINE" ] || { echo "error: system baseline not found at $BASELINE" >&2; exit 1; }

export OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"

echo "== spec generation for session $SESSION =="
echo "== baseline: $BASELINE =="
cd "$SG"
python -m spec_generator.cli "$INTENT" --conops "$CONOPS" --system-baseline "$BASELINE"

echo
echo "Done. Bundle: newest directory under $REQUIRE_ROOT/artifacts/ (printed above)."
echo "Redo one stage under newer code: python -m spec_generator.cli $INTENT --conops $CONOPS --system-baseline $BASELINE --from <stage>"
