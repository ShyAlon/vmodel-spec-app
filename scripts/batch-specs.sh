#!/usr/bin/env bash
# Founder-facing batch workflow. Bash owns the interactive UX; the Python
# helper owns durable JSON state and deterministic report calculations.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
IE="$REQUIRE_ROOT/interview-engine"
DRIVER="$SCRIPT_DIR/batch-specs.py"
PYTHON_BIN="${BATCH_SPECS_PYTHON:-python}"

fail() { echo "error: $*" >&2; exit 1; }
[ -d "$IE" ] || fail "interview-engine not found at $IE"
[ -f "$DRIVER" ] || fail "batch helper not found at $DRIVER"

usage() {
  cat <<'EOF'
usage:
  scripts/batch-specs.sh                 interactive interviews, then run queue
  scripts/batch-specs.sh interview       same as above
  scripts/batch-specs.sh add <intent_model.json> [--repeat N] [--name NAME]
  scripts/batch-specs.sh run [--limit N]
  scripts/batch-specs.sh report
  scripts/batch-specs.sh retry <run-id>

The durable queue is batch-specs.json in vmodel-spec-app unless --manifest is
passed before the subcommand.
EOF
}

# Manual queue lifecycle stays available behind the Bash entry point.
case "${1:-interview}" in
  add|run|report|retry)
    cd "$SCRIPT_DIR/.."
    exec "$PYTHON_BIN" "$DRIVER" "$@"
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  interview)
    [ "$#" -le 1 ] || fail "interview mode takes no arguments"
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

queued=0
while true; do
  log="$(mktemp "${TMPDIR:-/tmp}/vmodel-batch-interview.XXXXXX")"
  echo
  echo "== interactive interview $((queued + 1)) =="
  echo "Finish and approve it normally; it will then join the batch queue."
  set +e
  (
    cd "$IE"
    "$PYTHON_BIN" -m interview_engine.cli
  ) 2>&1 | tee "$log"
  interview_rc=${PIPESTATUS[0]}
  set -e
  if [ "$interview_rc" -ne 0 ]; then
    echo "Interview exited with status $interview_rc; nothing was queued." >&2
    rm -f "$log"
    exit "$interview_rc"
  fi

  session="$(grep -m1 -oE 'session: [A-Za-z0-9-]+' "$log" | awk '{print $2}' || true)"
  rm -f "$log"
  if [ -z "$session" ]; then
    fail "interview finished but no session id was printed"
  fi
  intent="$IE/out/$session/intent_model.json"
  if [ -f "$intent" ]; then
    (
      cd "$SCRIPT_DIR/.."
      "$PYTHON_BIN" "$DRIVER" add "$intent"
    )
    queued=$((queued + 1))
  else
    echo "Interview $session was not approved; no intent model exists, so it was not queued."
  fi

  printf 'Create another interview? [Y/n] '
  IFS= read -r answer || answer="n"
  case "${answer,,}" in
    ""|y|yes) ;;
    n|no|done|enough) break ;;
    *) echo "Please answer y or n."; continue ;;
  esac
done

if [ "$queued" -eq 0 ]; then
  echo "No interviews were queued; spec generation was not started."
  exit 0
fi

echo
echo "== sequential spec generation for $queued newly queued interview(s) =="
cd "$SCRIPT_DIR/.."
exec "$PYTHON_BIN" "$DRIVER" run
