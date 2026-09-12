#!/usr/bin/env bash
# Sanity tests for the shared scripts (standing rule: tests before ship).
# Run: bash vmodel-spec-app/scripts/tests/test_scripts.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(dirname "$HERE")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }
want() { grep -qE "$2" "$1" && ok "$3" || { bad "$3"; echo "  in $1:"; cat "$1" | sed 's/^/  /'; }; }

# fixture: a require/ tree with three process repos + pre-existing repo-local .env
ROOT="$TMP/require"
for r in interview-engine spec-generator verification-loop; do mkdir -p "$ROOT/$r"; done
printf '# my settings\nDEEPSEEK_API_KEY=sk-real-key-123\nSPEC_GENERATOR_MODEL_SRS=ollama:custom\n' > "$ROOT/spec-generator/.env"
SHARED="$ROOT/.env"

REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" ollama >/dev/null || bad "ollama run exits clean"
want "$SHARED" '^INTERVIEW_ENGINE_MODEL_PROBING=ollama:phi4$' "ollama: interview probing -> shared"
want "$SHARED" '^INTERVIEW_ENGINE_MODEL_SCOPE_TIEBREAK=ollama:phi4$' "ollama: interview tiebreak -> shared"
want "$SHARED" '^SPEC_GENERATOR_MODEL_SRS=ollama:phi4$' "ollama: spec srs -> shared"
want "$SHARED" '^SPEC_GENERATOR_MODEL_REVIEW=ollama:phi4$' "ollama: spec review -> shared"
want "$SHARED" '^VERIFICATION_LOOP_MODEL_RESIDUE_JUDGE=ollama:phi4$' "ollama: verification judge -> shared"
want "$SHARED" '^DEEPSEEK_API_KEY=sk-real-key-123$' "migration: repo-local key value preserved into shared"
! grep -qE '^SPEC_GENERATOR_MODEL_SRS=' "$ROOT/spec-generator/.env" && ok "migration: managed MODEL_* stripped from repo-local" || bad "migration: managed MODEL_* stripped from repo-local"
! grep -qE '^DEEPSEEK_API_KEY=' "$ROOT/spec-generator/.env" && ok "migration: key stripped from repo-local" || bad "migration: key stripped from repo-local"
want "$ROOT/spec-generator/.env" '^# my settings$' "migration: unrelated repo-local lines preserved"

# deepseek: key via env pass-through, written to the shared file
OUT="$(DEEPSEEK_API_KEY=sk-test-AAAA REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek)" || bad "deepseek run exits clean"
want "$SHARED" '^SPEC_GENERATOR_MODEL_SRS=deepseek:deepseek-flash$' "deepseek: spec srs switched"
want "$SHARED" '^INTERVIEW_ENGINE_MODEL_DISTILLATION=deepseek:deepseek-flash$' "deepseek: interview distillation"
# DeepSeek override without a code change
DEEPSEEK_MODEL=deepseek-v4-pro DEEPSEEK_API_KEY=sk-test-PRO REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek >/dev/null
want "$SHARED" '^SPEC_GENERATOR_MODEL_SRS=deepseek:deepseek-v4-pro$' "deepseek: DEEPSEEK_MODEL override respected"
# restore default for the remaining idempotency/key tests
DEEPSEEK_API_KEY=sk-test-AAAA REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek >/dev/null
want "$SHARED" '^DEEPSEEK_API_KEY=sk-test-AAAA$' "deepseek: key written to shared (replaced migrated one)"
printf '%s' "$OUT" | grep -q 'sk-test-AAAA' && bad "key never echoed to stdout" || ok "key never echoed to stdout"
# rerun with a NEW key replaces the line, never duplicates
DEEPSEEK_API_KEY=sk-test-BBBB REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek >/dev/null
want "$SHARED" '^DEEPSEEK_API_KEY=sk-test-BBBB$' "deepseek rerun: key replaced"
[ "$(grep -c '^DEEPSEEK_API_KEY=' "$SHARED")" = "1" ] && ok "deepseek rerun: key not duplicated" || bad "deepseek rerun: key not duplicated"
[ "$(grep -c '^SPEC_GENERATOR_MODEL_SRS=' "$SHARED")" = "1" ] && ok "idempotent: no duplicate keys" || bad "idempotent: no duplicate keys"
# hidden-prompt path: key on stdin, not echoed
OUT="$(printf 'sk-test-CCCC\n' | REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek)" || bad "deepseek prompt path exits clean"
want "$SHARED" '^DEEPSEEK_API_KEY=sk-test-CCCC$' "prompt: key written from hidden prompt"
printf '%s' "$OUT" | grep -q 'sk-test-CCCC' && bad "prompt: key never echoed" || ok "prompt: key never echoed"
# no key anywhere (stdin EOF) fails loudly, writes nothing
REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek </dev/null >/dev/null 2>&1 && bad "missing key rejected" || ok "missing key rejected"
want "$SHARED" '^DEEPSEEK_API_KEY=sk-test-CCCC$' "missing key: existing shared .env untouched"

# openai: key via env pass-through, default model gpt-5.4-mini
OUT="$(OPENAI_API_KEY=sk-oai-AAAA REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" openai)" || bad "openai run exits clean"
want "$SHARED" '^SPEC_GENERATOR_MODEL_SRS=openai:gpt-5\.4-mini$' "openai: spec srs switched to default model"
want "$SHARED" '^INTERVIEW_ENGINE_MODEL_PROBING=openai:gpt-5\.4-mini$' "openai: interview probing"
want "$SHARED" '^VERIFICATION_LOOP_MODEL_RESIDUE_JUDGE=openai:gpt-5\.4-mini$' "openai: verification judge"
want "$SHARED" '^OPENAI_API_KEY=sk-oai-AAAA$' "openai: key written to shared"
want "$SHARED" '^DEEPSEEK_API_KEY=sk-test-CCCC$' "openai: deepseek key preserved in shared"
printf '%s' "$OUT" | grep -q 'sk-oai-AAAA' && bad "openai: key never echoed" || ok "openai: key never echoed"
# model override without a code change
OPENAI_MODEL=gpt-5.4 OPENAI_API_KEY=sk-oai-BBBB REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" openai >/dev/null
want "$SHARED" '^SPEC_GENERATOR_MODEL_SRS=openai:gpt-5\.4$' "openai: OPENAI_MODEL override respected"
want "$SHARED" '^OPENAI_API_KEY=sk-oai-BBBB$' "openai rerun: key replaced"
[ "$(grep -c '^OPENAI_API_KEY=' "$SHARED")" = "1" ] && ok "openai rerun: key not duplicated" || bad "openai rerun: key not duplicated"
# openai prompt path + empty rejection
OUT="$(printf 'sk-oai-CCCC\n' | REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" openai)" || bad "openai prompt path exits clean"
want "$SHARED" '^OPENAI_API_KEY=sk-oai-CCCC$' "openai prompt: key written from hidden prompt"
printf '%s' "$OUT" | grep -q 'sk-oai-CCCC' && bad "openai prompt: key never echoed" || ok "openai prompt: key never echoed"
REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" openai </dev/null >/dev/null 2>&1 && bad "openai missing key rejected" || ok "openai missing key rejected"

# unknown provider fails loudly
mkdir -p "$ROOT/vmodel-spec-app" "$ROOT/spec-generator/examples"
printf '{"baseline_id":"test"}' > "$ROOT/vmodel-spec-app/system-baseline.json"
printf '{"contract_version":"0.13.0","baseline_id":"tpl","system_name":"tpl","mode":"greenfield","repositories":[],"immutable_decisions":[]}' \
  > "$ROOT/spec-generator/examples/system-baseline.greenfield.json"
REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" banana >/dev/null 2>&1 && bad "unknown provider rejected" || ok "unknown provider rejected"
# missing repo is skipped, not fatal
rm -rf "$ROOT/verification-loop"
REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" ollama >/dev/null && ok "missing repo skipped cleanly" || bad "missing repo skipped cleanly"

# run-full-flow: shim python, verify session capture + handoff args
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/python" <<'SHIM'
#!/usr/bin/env bash
echo "SHIM cwd=$(pwd) args: $*" >> "$SHIM_LOG"
if [[ "$*" == *"interview_engine.cli"* ]]; then
  session="20260909-210000-ab12"
  mkdir -p "out/$session"
  if [ "${SHIM_NO_APPROVE:-0}" != "1" ]; then
    echo '{"session_id": "'"$session"'"}' > "out/$session/intent_model.json"
  fi
  echo "session: $session" >&2
else
  # spec-generator leg: the intent model path (arg 3: -m spec_generator.cli PATH)
  [ -f "$3" ] || { echo "shim: intent model missing: $3" >&2; exit 3; }
fi
SHIM
chmod +x "$BIN/python"
export SHIM_LOG="$TMP/shim.log"
PATH="$BIN:$PATH" REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/run-full-flow.sh" "a test idea" --baseline "$ROOT/vmodel-spec-app/system-baseline.json" >/dev/null \
  && ok "full flow exits clean" || bad "full flow exits clean"
grep -q "interview_engine.cli a test idea" "$SHIM_LOG" && ok "interview got the idea" || bad "interview got the idea"
grep -q "spec_generator.cli $ROOT/interview-engine/out/20260909-210000-ab12/intent_model.json --system-baseline $ROOT/vmodel-spec-app/system-baseline.json --review" "$SHIM_LOG" \
  && ok "spec-generator got the captured session's intent model + baseline + --review" || { bad "spec-generator handoff"; cat "$SHIM_LOG"; }
# unapproved interview (no intent_model.json) stops before spec-generator
rm -f "$ROOT/interview-engine/out/20260909-210000-ab12/intent_model.json"
: > "$SHIM_LOG"
PATH="$BIN:$PATH" SHIM_NO_APPROVE=1 REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/run-full-flow.sh" "again" --baseline "$ROOT/vmodel-spec-app/system-baseline.json" >/dev/null 2>&1 \
  && bad "unapproved interview stops the flow" || ok "unapproved interview stops the flow"
grep -q "spec_generator" "$SHIM_LOG" && bad "spec-generator NOT run without approval" || ok "spec-generator NOT run without approval"
# the baseline is an explicit choice: no --greenfield/--baseline, no flow
: > "$SHIM_LOG"
PATH="$BIN:$PATH" REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/run-full-flow.sh" "a test idea" >/dev/null 2>&1 \
  && bad "full flow without an anchor choice is rejected" || ok "full flow without an anchor choice is rejected"
grep -q "interview_engine" "$SHIM_LOG" && bad "interview NOT run without anchor choice" || ok "interview NOT run without anchor choice"
# --greenfield materializes a per-session greenfield baseline and passes it
: > "$SHIM_LOG"
PATH="$BIN:$PATH" REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/run-full-flow.sh" "a test idea" --greenfield >/dev/null \
  && ok "full flow --greenfield exits clean" || bad "full flow --greenfield exits clean"
grep -q "spec_generator.cli $ROOT/interview-engine/out/20260909-210000-ab12/intent_model.json --system-baseline $ROOT/interview-engine/out/20260909-210000-ab12/greenfield-baseline.json --review" "$SHIM_LOG" \
  && ok "spec-generator got the materialized greenfield baseline" || { bad "greenfield handoff"; cat "$SHIM_LOG"; }
grep -q '"mode": "greenfield"' "$ROOT/interview-engine/out/20260909-210000-ab12/greenfield-baseline.json" \
  && ok "materialized baseline is mode=greenfield" || bad "materialized baseline mode"

echo
# guardrail knobs: defaults added when absent, never overridden, never duplicated
want "$SHARED" '^VMODEL_LLM_CALL_TIMEOUT_S=600$' "guardrails: call timeout default written"
want "$SHARED" '^VMODEL_LLM_STALL_TIMEOUT_S=180$' "guardrails: stall timeout default written"
want "$SHARED" '^VMODEL_LLM_MAX_CALLS=200$' "guardrails: call budget default written"
want "$SHARED" '^# VMODEL_LLM_MAX_TOKENS: per-call generation-length ceiling' "guardrails: max-tokens documented (per-stage default)"
REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" ollama >/dev/null || bad "guardrails rerun exits clean"
[ "$(grep -c '^VMODEL_LLM_MAX_CALLS=' "$SHARED")" = "1" ] && ok "guardrails rerun: defaults not duplicated" || bad "guardrails rerun: defaults not duplicated"
[ "$(grep -c '^# VMODEL_LLM_MAX_TOKENS:' "$SHARED")" = "1" ] && ok "guardrails rerun: max-tokens comment not duplicated" || bad "guardrails rerun: max-tokens comment not duplicated"
# user-set values survive the next run untouched
printf 'VMODEL_LLM_MAX_CALLS=50\nVMODEL_LLM_MAX_TOKENS=4096\n' >> "$SHARED"
REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek >/dev/null 2>&1 || \
  DEEPSEEK_API_KEY=sk-test-CCCC REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek >/dev/null || bad "guardrails preserve run exits clean"
want "$SHARED" '^VMODEL_LLM_MAX_CALLS=50$' "guardrails: user-set call budget preserved"
want "$SHARED" '^VMODEL_LLM_MAX_TOKENS=4096$' "guardrails: user-set max-tokens preserved"
want "$SHARED" '^VMODEL_LLM_CALL_TIMEOUT_S=600$' "guardrails: earlier default still there"

if bash "$SCRIPTS/tests/test_batch_specs_sh.sh"; then
  ok "bash batch entrypoint loops interviews and delegates lifecycle"
else
  bad "bash batch entrypoint"
fi

if bash "$SCRIPTS/tests/test_collect_analysis_sh.sh"; then
  ok "analysis collector bundles runs and reports honestly"
else
  bad "analysis collector"
fi

if bash "$SCRIPTS/tests/test_new_scripts_sh.sh"; then
  ok "new-interview/new-spec scripts resolve sessions and pass the baseline"
else
  bad "new-interview/new-spec scripts"
fi

# shared scripts runbook: every batch lifecycle command is documented
for cmd in add run report retry; do
  grep -q "batch-specs.sh $cmd" "$SCRIPTS/README.md" || bad "scripts README documents batch $cmd"
done
ok "scripts README documents batch lifecycle"

# batch-specs: Python unit coverage for queue ids, repeat outputs, evaluator.
# Use python3: this check runs after the test shim prepended a fake `python`.
if python3 "$SCRIPTS/tests/test_batch_specs.py" >/dev/null; then
  ok "batch specs queue + evaluator"
else
  bad "batch specs queue + evaluator"
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
