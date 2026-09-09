#!/usr/bin/env bash
# run-full-flow.sh - interview to spec bundle in one command.
#
#   scripts/run-full-flow.sh "a marketplace for surf lessons in Tel Aviv"
#   scripts/run-full-flow.sh --session <id>     # resume an interrupted interview first
#
# Runs the interview (interactive: Q&A + the approve gate), captures the
# session id it prints, then runs spec-generator against that session's
# intent_model.json with the review gates. Nothing to copy by hand.
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 \"<product idea>\" | --session <id>" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
IE="$REQUIRE_ROOT/interview-engine"
SG="$REQUIRE_ROOT/spec-generator"
[ -d "$IE" ] || { echo "error: interview-engine not found at $IE" >&2; exit 1; }
[ -d "$SG" ] || { echo "error: spec-generator not found at $SG" >&2; exit 1; }

SESSION=""
if [ "$1" = "--session" ] || [ "$1" = "-s" ]; then
  SESSION="${2:?--session needs an id}"
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
if [ ! -f "$INTENT" ]; then
  echo "Interview for session $SESSION ended without an approved intent model -" >&2
  echo "nothing was generated. Resume it with: $0 --session $SESSION" >&2
  exit 1
fi

# 2. SPEC GENERATION. Not piped: the --review gates (accept/edit/feedback/
# reject) read from the terminal.
echo
echo "== spec generation for session $SESSION (review gates on) =="
cd "$SG"
python -m spec_generator.cli "$INTENT" -o bundle/ --review

echo
echo "Done. Bundle: $SG/bundle/  (AGENTS.md, srs.md, needs.md, architecture.md, specs/, traceability.json)"
echo "Redo one stage under newer code: python -m spec_generator.cli $INTENT -o bundle/ --from <stage>"
