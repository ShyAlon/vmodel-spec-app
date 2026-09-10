#!/usr/bin/env bash
set -euo pipefail
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/require"; mkdir -p "$ROOT/interview-engine/out/20260910-180000-ab12" "$ROOT/vmodel-spec-app/scripts"
cp "$SCRIPTS/batch-specs.sh" "$ROOT/vmodel-spec-app/scripts/"
printf '{}' > "$ROOT/vmodel-spec-app/scripts/batch-specs.py"
cat > "$TMP/python" <<'PY'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATCH_TEST_LOG"
if [[ "$*" == "-m interview_engine.cli" ]]; then
  echo 'session: 20260910-180000-ab12' >&2
  printf '{"session_id":"20260910-180000-ab12"}' > out/20260910-180000-ab12/intent_model.json
  echo 'Approved.'
fi
PY
chmod +x "$TMP/python"; export BATCH_TEST_LOG="$TMP/calls"
printf 'n\n' | REQUIRE_ROOT="$ROOT" BATCH_SPECS_PYTHON="$TMP/python" "$ROOT/vmodel-spec-app/scripts/batch-specs.sh" >/dev/null
[ "$(grep -c -- '-m interview_engine.cli' "$BATCH_TEST_LOG")" = 1 ]
grep -q 'batch-specs.py add .*intent_model.json' "$BATCH_TEST_LOG"
grep -q 'batch-specs.py run' "$BATCH_TEST_LOG"
: > "$BATCH_TEST_LOG"
REQUIRE_ROOT="$ROOT" BATCH_SPECS_PYTHON="$TMP/python" "$ROOT/vmodel-spec-app/scripts/batch-specs.sh" report >/dev/null
grep -q 'batch-specs.py report' "$BATCH_TEST_LOG"

# Keep the founder-facing entry point compatible with macOS' Bash 3.2.
# Reject the common Bash 4+ constructs that caused the original handoff crash.
if grep -Eq '\\$\{[^}]+(,,|\^\^)|(^|[[:space:]])(declare|typeset)[[:space:]]+-A|(^|[[:space:]])(mapfile|readarray|coproc)([[:space:]]|$)|wait[[:space:]]+-n' "$SCRIPTS/batch-specs.sh"; then
  echo 'batch-specs.sh uses a Bash 4+ construct' >&2
  exit 1
fi
