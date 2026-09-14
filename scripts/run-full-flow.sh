#!/usr/bin/env bash
# run-full-flow.sh - interview to spec bundle in one command.
#
#   scripts/run-full-flow.sh "a marketplace for surf lessons in Tel Aviv" --greenfield
#   scripts/run-full-flow.sh "improve the spec pipeline" --baseline vmodel-spec-app/system-baseline.json
#   scripts/run-full-flow.sh --session <id> --greenfield     # resume an interrupted interview first
#
# Runs the interview (interactive: Q&A + the approve gate), captures the
# session id it prints, then runs spec-generator against that session's
# intent_model.json with the review gates. The baseline is an EXPLICIT choice
# (--greenfield for a new product, --baseline <path> for an existing system) -
# a silent default would anchor a new product to the wrong system's
# architecture (2026-09-12 review).
set -euo pipefail

usage() { echo "usage: $0 (\"<product idea>\" | --session <id>) (--greenfield | --baseline <path>)" >&2; exit 1; }
[ $# -ge 1 ] || usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
IE="$REQUIRE_ROOT/interview-engine"
SG="$REQUIRE_ROOT/spec-generator"
[ -d "$IE" ] || { echo "error: interview-engine not found at $IE" >&2; exit 1; }
[ -d "$SG" ] || { echo "error: spec-generator not found at $SG" >&2; exit 1; }

SESSION=""
IDEA_ARGS=()
BASELINE=""
GREENFIELD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --session|-s) SESSION="${2:?--session needs an id}"; shift 2 ;;
    --greenfield) GREENFIELD=1; shift ;;
    --baseline)   BASELINE="${2:?--baseline needs a path}"; shift 2 ;;
    -*)           usage ;;
    *)            IDEA_ARGS+=("$1"); shift ;;
  esac
done
[ "$GREENFIELD" -eq 1 ] && [ -n "$BASELINE" ] && usage
[ "$GREENFIELD" -eq 0 ] && [ -z "$BASELINE" ] && {
  echo "error: choose the architecture anchor explicitly:" >&2
  echo "  --greenfield        a brand-new product (no existing system)" >&2
  echo "  --baseline <path>   an existing system's checked baseline" >&2
  exit 1
}
if [ -z "$SESSION" ] && [ ${#IDEA_ARGS[@]} -eq 0 ]; then usage; fi
if [ -n "$SESSION" ]; then
  set -- --session "$SESSION"          # resume form for the interview leg
else
  set -- ${IDEA_ARGS[@]+"${IDEA_ARGS[@]}"}
fi

# 1. INTERVIEW. stdout+stderr go to the log AND the terminal; stdin stays on
# the terminal, so the Q&A prompts and the 'Approve this intent model? [y/N]'
# gate stay fully interactive.
LOG="$(mktemp "${TMPDIR:-/tmp}/vmodel-interview.XXXXXX")"
echo "== interview (log: $LOG) =="
cd "$IE"
python -m interview_engine.cli "$@" 2>&1 | tee "$LOG"

if [ -z "$SESSION" ]; then
  SESSION="$(grep -m1 -oE 'session: [A-Za-z0-9-]+' "$LOG" | awk '{print $2}' || true)"
fi
[ -n "$SESSION" ] || { echo "error: no session id found in the interview output (see $LOG)" >&2; exit 1; }

INTENT="$IE/out/$SESSION/intent_model.json"
CONOPS="$IE/out/$SESSION/conops.json"
if [ ! -f "$INTENT" ] || [ ! -f "$CONOPS" ]; then
  echo "Interview for session $SESSION ended without an approved Intent Model and Concept of Operations -" >&2
  echo "nothing was generated. Resume it with: $0 --session $SESSION" >&2
  exit 1
fi

# 2. SPEC GENERATION. Not piped: the --review gates (accept/edit/feedback/
# reject) read from the terminal.
echo
echo "== spec generation for session $SESSION (review gates on) =="
if [ "$GREENFIELD" -eq 1 ]; then
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
echo "== baseline: $BASELINE =="
cd "$SG"
python -m spec_generator.cli "$INTENT" --conops "$CONOPS" --system-baseline "$BASELINE" --review

# Interview-generated session ids begin YYYYMMDD-HHMMSS. Mirror the CLI's
# human-readable, stable default so this handoff points to the resumable run.
if [[ "$SESSION" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
  ARTIFACTS="artifacts-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]}_${BASH_REMATCH[4]}-${BASH_REMATCH[5]}-${BASH_REMATCH[6]}"
else
  ARTIFACTS="artifacts directory printed above"
fi

echo
echo "Done. Artifacts: $REQUIRE_ROOT/artifacts/$ARTIFACTS/  (AGENTS.md, srs.md, needs.md, architecture.md, specs/, traceability.json)"
echo "Redo one stage under newer code: python -m spec_generator.cli $INTENT --conops $CONOPS --system-baseline $BASELINE --from <stage>"
