#!/usr/bin/env bash
# Sanity tests for scripts/experiments/run-smoke.sh (standing rule: tests before ship).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(dirname "$HERE")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

# Fake require-root: stub spec-generator with the greenfield template, a
# shared .env, and a stub `python` that echoes args AND the cap env it sees.
ROOT="$TMP/require"; SG="$ROOT/spec-generator"
mkdir -p "$SG/examples" "$SG/examples"
printf '{"contract_version":"0.14.1","baseline_id":"tpl","system_name":"tpl","mode":"greenfield","repositories":[],"immutable_decisions":[]}' \
  > "$SG/examples/system-baseline.greenfield.json"
printf 'VMODEL_CAP_NEEDS=9\n' > "$ROOT/.env"
INTENT="$TMP/intent.json"; printf '{"session_id":"smoke"}' > "$INTENT"
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/python" <<'SH'
#!/usr/bin/env bash
echo "PYTHON-CALLED: $*"
echo "CAPS: needs=$VMODEL_CAP_NEEDS stack=$VMODEL_CAP_STACK_SLOTS tests=$VMODEL_CAP_TESTS llmlog=$VMODEL_LLM_LOG"
SH
chmod +x "$BIN/python"
export PATH="$BIN:$PATH"

RUN="$SCRIPTS/experiments/run-smoke.sh"

# 1. flags beat the shared .env; the pipeline gets the fixture + greenfield baseline
OUT="$(REQUIRE_ROOT="$ROOT" bash "$RUN" --intent "$INTENT" --cap-needs 2 --cap-stack 4 --cap-tests 6 2>&1)"
echo "$OUT" | grep -q '== experiment smoke run ==' && ok "opening banner" || bad "opening banner"
echo "$OUT" | grep -q 'needs<=2 stack<=4 tests<=6' && ok "caps printed before the run" || bad "caps print"
echo "$OUT" | grep -q 'CAPS: needs=2 stack=4 tests=6' && ok "flags exported to the pipeline env" || bad "flag env passthrough"
echo "$OUT" | grep -q -- "spec_generator.cli $INTENT --system-baseline $SG/examples/system-baseline.greenfield.json" \
  && ok "pipeline called with intent + greenfield baseline" || bad "pipeline invocation"
echo "$OUT" | grep -q 'experiment_report' && ok "quality report runs after the pipeline" || bad "report invocation"
echo "$OUT" | grep -q 'llmlog=.*/llm-calls.jsonl' && ok "llm-calls.jsonl enabled for the run" || bad "llm log env"

# 2. shared .env fills caps when flags are absent (his one-config-file rule)
OUT="$(REQUIRE_ROOT="$ROOT" bash "$RUN" --intent "$INTENT" --cap-stack 4 2>&1)"
echo "$OUT" | grep -q 'CAPS: needs=9 stack=4 tests=12' && ok "shared .env fills unset caps" || bad ".env fallback"

# 3. the shared .env is NEVER written by an experiment run
echo "$ROOT/.env unchanged?"; BEFORE="$(cat "$ROOT/.env")"
REQUIRE_ROOT="$ROOT" bash "$RUN" --intent "$INTENT" >/dev/null 2>&1
[ "$(cat "$ROOT/.env")" = "$BEFORE" ] && ok "shared .env untouched (no experiment poisoning)" || bad ".env written"

# 4. bundle lands under an experiment-* dir, clearly separate from real bundles
OUT="$(REQUIRE_ROOT="$ROOT" bash "$RUN" --intent "$INTENT" 2>&1)"
echo "$OUT" | grep -q "bundle:   $ROOT/artifacts/experiment-" && ok "experiment bundles are clearly separated" || bad "bundle dir naming"

# 5. bad caps are a human-readable error, not a traceback
OUT="$(REQUIRE_ROOT="$ROOT" bash "$RUN" --intent "$INTENT" --cap-needs lots 2>&1)" \
  && bad "bad cap exits non-zero" || ok "bad cap exits non-zero"
echo "$OUT" | grep -q 'caps must be positive integers' && ok "bad cap message is human-readable" || bad "bad cap message"

# 6. missing intent is a human-readable error
OUT="$(REQUIRE_ROOT="$ROOT" bash "$RUN" --intent "$TMP/nope.json" 2>&1)" \
  && bad "missing intent exits non-zero" || ok "missing intent exits non-zero"
echo "$OUT" | grep -q 'intent model not found' && ok "missing intent message" || bad "missing intent message"

# 7. the checked-in fixture is a contract-valid IntentModel (verified against the real contract)
python3 - "$SCRIPTS/experiments/fixtures/intent-model.smoke.json" <<'PY' && ok "smoke fixture validates against IntentModel" || bad "fixture contract"
import json, sys
from vmodel_contracts import IntentModel
IntentModel.model_validate(json.load(open(sys.argv[1])))
PY

bash -n "$RUN" && ok "run-smoke.sh parses (bash 3.2)" || bad "syntax"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
