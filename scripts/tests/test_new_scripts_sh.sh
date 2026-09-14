#!/usr/bin/env bash
# Sanity tests for new-interview.sh / new-spec.sh (standing rule: tests before ship).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(dirname "$HERE")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

# Fake require-root: stub repos, two interview sessions, a stub `python` that
# just echoes its arguments (no real LLM calls in a shell test).
ROOT="$TMP/require"
IE="$ROOT/interview-engine"; SG="$ROOT/spec-generator"; APP="$ROOT/vmodel-spec-app"
mkdir -p "$IE/out/20260910-203404-7bd9" "$IE/out/20260912-201837-bd17" "$SG" "$APP"
printf '{}' > "$IE/out/20260910-203404-7bd9/intent_model.json"
printf '{}' > "$IE/out/20260910-203404-7bd9/conops.json"
printf '{}' > "$IE/out/20260912-201837-bd17/intent_model.json"
printf '{}' > "$IE/out/20260912-201837-bd17/conops.json"
touch -t 202609100000 "$IE/out/20260910-203404-7bd9"   # distinct mtimes: ls -t must pick the newer
touch -t 202609120000 "$IE/out/20260912-201837-bd17"
printf '{"baseline_id":"b"}' > "$APP/system-baseline.json"
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/python" <<'SH'
#!/usr/bin/env bash
echo "PYTHON-CALLED: $*"
SH
chmod +x "$BIN/python"
export PATH="$BIN:$PATH"

# new-spec.sh with no args picks the NEWEST session and passes the baseline.
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/new-spec.sh" --baseline "$APP/system-baseline.json" 2>&1)"
echo "$OUT" | grep -q 'session 20260912-201837-bd17' && ok "new-spec defaults to the newest session" || bad "new-spec newest session"
echo "$OUT" | grep -q -- "--conops $IE/out/20260912-201837-bd17/conops.json --system-baseline $APP/system-baseline.json" && ok "new-spec passes --system-baseline" || bad "new-spec baseline flag"
echo "$OUT" | grep -q "spec_generator.cli $IE/out/20260912-201837-bd17/intent_model.json --conops $IE/out/20260912-201837-bd17/conops.json" && ok "new-spec targets the intent model" || bad "new-spec intent path"

# Explicit session id wins.
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/new-spec.sh" 20260910-203404-7bd9 --baseline "$APP/system-baseline.json" 2>&1)"
echo "$OUT" | grep -q 'session 20260910-203404-7bd9' && ok "new-spec accepts an explicit session" || bad "new-spec explicit session"

# Missing intent model is a human-readable error, not a traceback.
mkdir -p "$IE/out/20260913-090000-ffff"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/new-spec.sh" 20260913-090000-ffff --baseline "$APP/system-baseline.json" 2>&1)" && bad "new-spec missing intent exits non-zero" || true
echo "$OUT" | grep -q 'no approved intent model' && ok "new-spec missing intent is human-readable" || bad "new-spec missing intent message"

# Intent without its paired Concept of Operations fails before spec generation.
rm "$IE/out/20260910-203404-7bd9/conops.json"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/new-spec.sh" 20260910-203404-7bd9 --baseline "$APP/system-baseline.json" 2>&1)" && bad "new-spec missing CONOPS exits non-zero" || true
echo "$OUT" | grep -q 'no approved Concept of Operations' && ok "missing CONOPS is human-readable" || bad "missing CONOPS message"
printf '{}' > "$IE/out/20260910-203404-7bd9/conops.json"

# No sessions at all: clear error pointing at new-interview.sh.
rm -rf "$IE/out"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/new-spec.sh" --baseline "$APP/system-baseline.json" 2>&1)" && bad "new-spec empty out/ exits non-zero" || true
echo "$OUT" | grep -q 'new-interview.sh first' && ok "new-spec with no sessions points at new-interview.sh" || bad "new-spec no-session message"

# Usage errors.
bash "$SCRIPTS/new-interview.sh" >/dev/null 2>&1 && bad "new-interview without args exits non-zero" || ok "new-interview requires an idea or --session"
OUT="$(bash "$SCRIPTS/new-interview.sh" 2>&1)"
echo "$OUT" | grep -q 'usage:' && ok "new-interview usage is printed" || bad "new-interview usage text"

# Missing baseline is caught before any model call.
rm "$APP/system-baseline.json"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/new-spec.sh" 20260910-203404-7bd9 --baseline "$APP/system-baseline.json" 2>&1)" && bad "new-spec missing baseline exits non-zero" || true
echo "$OUT" | grep -q 'system baseline not found' && ok "new-spec missing baseline is human-readable" || bad "new-spec baseline message"

# Both scripts and run-full-flow.sh are valid bash (3.2-compatible syntax).
for f in new-interview.sh new-spec.sh run-full-flow.sh; do
  bash -n "$SCRIPTS/$f" && ok "$f parses" || bad "$f syntax"
done
# run-full-flow.sh passes the baseline to spec-generator too.
grep -q -- '--conops "$CONOPS" --system-baseline "$BASELINE" --review' "$SCRIPTS/run-full-flow.sh" && ok "run-full-flow passes --system-baseline" || bad "run-full-flow baseline flag"

# --- explicit baseline choice (2026-09-12 review): a new product must never
# silently inherit the generator's own baseline ---

# fixtures (an earlier test emptied out/)
mkdir -p "$IE/out/20260910-203404-7bd9" "$IE/out/20260912-201837-bd17" "$SG/examples" "$APP"
printf '{}' > "$IE/out/20260910-203404-7bd9/intent_model.json"
printf '{}' > "$IE/out/20260910-203404-7bd9/conops.json"
printf '{}' > "$IE/out/20260912-201837-bd17/intent_model.json"
printf '{}' > "$IE/out/20260912-201837-bd17/conops.json"
touch -t 202609100000 "$IE/out/20260910-203404-7bd9"; touch -t 202609120000 "$IE/out/20260912-201837-bd17"
printf '{"contract_version":"0.14.1","baseline_id":"tpl","system_name":"tpl","mode":"greenfield","repositories":[],"immutable_decisions":[]}' > "$SG/examples/system-baseline.greenfield.json"
printf '{"baseline_id":"generator"}' > "$APP/system-baseline.json"

# no flag at all: rejected with a human-readable choice, even though the
# generator's own baseline file EXISTS right there
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/new-spec.sh" 20260910-203404-7bd9 2>&1)" \
  && bad "new-spec without an anchor choice is rejected" || ok "new-spec without an anchor choice is rejected"
echo "$OUT" | grep -q 'choose the architecture anchor explicitly' && ok "rejection names the choice" || bad "rejection message"
echo "$OUT" | grep -q 'PYTHON-CALLED' && bad "no model call without an anchor choice" || ok "no model call without an anchor choice"

# --baseline passes the given file through
mkdir -p "$ROOT/myproduct"; printf '{"baseline_id":"mine"}' > "$ROOT/myproduct/baseline.json"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/new-spec.sh" --baseline "$ROOT/myproduct/baseline.json" 2>&1)"
echo "$OUT" | grep -q -- "--system-baseline $ROOT/myproduct/baseline.json" && ok "--baseline passes through" || bad "--baseline passthrough"

# --greenfield materializes a per-session greenfield baseline next to the intent model
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/new-spec.sh" --greenfield 2>&1)"
GF="$IE/out/20260912-201837-bd17/greenfield-baseline.json"
echo "$OUT" | grep -q -- "--system-baseline $GF" && ok "--greenfield passes the materialized baseline" || bad "--greenfield handoff"
grep -q '"mode": "greenfield"' "$GF" && ok "materialized baseline is mode=greenfield" || bad "materialized mode"
grep -q 'greenfield-20260912-201837-bd17' "$GF" && ok "baseline id names the session" || bad "baseline id"
# and the generator's own baseline NEVER appears in any invocation
echo "$OUT" | grep -q 'vmodel-spec-app/system-baseline.json' && bad "generator baseline never inherited" || ok "generator baseline never inherited"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
