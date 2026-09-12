#!/usr/bin/env bash
# new-interview.sh - start a BRAND NEW interview session (or resume one).
#
#   scripts/new-interview.sh "a marketplace for surf lessons in Tel Aviv"
#   scripts/new-interview.sh --session <id>    # resume an interrupted interview
#
# Interactive: the engine asks, you answer, then an approve gate renders the
# intent model. Artifacts land in interview-engine/out/<session>/ (timestamp-
# hash id like 20260912-201837-bd17): intent_model.json, intent_model.md,
# usage.jsonl. Nothing is reused from older sessions.
set -euo pipefail

[ $# -ge 1 ] || { echo "usage: $0 \"<product idea>\" | --session <id>" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
IE="$REQUIRE_ROOT/interview-engine"
[ -d "$IE" ] || { echo "error: interview-engine not found at $IE" >&2; exit 1; }

export OLLAMA_NUM_PARALLEL="${OLLAMA_NUM_PARALLEL:-1}"  # one model in memory on 16GB

LOG="$(mktemp "${TMPDIR:-/tmp}/vmodel-interview.XXXXXX")"
echo "== new interview (log: $LOG) =="
cd "$IE"
# stdout+stderr tee'd to the log; stdin stays on the terminal for the Q&A.
python -m interview_engine.cli "$@" 2>&1 | tee "$LOG"

SESSION="$(grep -m1 -oE 'session: [A-Za-z0-9-]+' "$LOG" | awk '{print $2}' || true)"
if [ -n "$SESSION" ] && [ -f "$IE/out/$SESSION/intent_model.json" ]; then
  echo
  echo "Interview approved. Session: $SESSION"
  echo "Intent model: $IE/out/$SESSION/intent_model.json"
  echo "Next: scripts/new-spec.sh            (auto-picks this newest session)"
elif [ -n "$SESSION" ]; then
  echo
  echo "Interview ended without an approved intent model." >&2
  echo "Resume it with: $0 --session $SESSION" >&2
  exit 1
fi
