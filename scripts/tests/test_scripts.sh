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

# fixture: a require/ tree with three process repos
ROOT="$TMP/require"
for r in interview-engine spec-generator verification-loop; do mkdir -p "$ROOT/$r"; done
printf '# my settings\nDEEPSEEK_API_KEY=sk-real-key-123\nSPEC_GENERATOR_MODEL_SRS=ollama:custom\n' > "$ROOT/spec-generator/.env"

REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" ollama >/dev/null || bad "ollama run exits clean"
want "$ROOT/interview-engine/.env" '^INTERVIEW_ENGINE_MODEL_PROBING=ollama:qwen2\.5-coder:14b$' "ollama: interview probing"
want "$ROOT/interview-engine/.env" '^INTERVIEW_ENGINE_MODEL_SCOPE_TIEBREAK=ollama:qwen2\.5-coder:14b$' "ollama: interview tiebreak"
want "$ROOT/spec-generator/.env" '^SPEC_GENERATOR_MODEL_SRS=ollama:qwen2\.5-coder:14b$' "ollama: spec srs OVERWRITTEN"
want "$ROOT/spec-generator/.env" '^SPEC_GENERATOR_MODEL_REVIEW=ollama:qwen2\.5-coder:14b$' "ollama: spec review"
want "$ROOT/verification-loop/.env" '^VERIFICATION_LOOP_MODEL_RESIDUE_JUDGE=ollama:qwen2\.5-coder:14b$' "ollama: verification judge"
want "$ROOT/spec-generator/.env" '^DEEPSEEK_API_KEY=sk-real-key-123$' "ollama: existing API key preserved"
want "$ROOT/spec-generator/.env" '^# my settings$' "ollama: unrelated lines preserved"

# deepseek: key via env pass-through, written to every repo's .env
OUT="$(DEEPSEEK_API_KEY=sk-test-AAAA REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek)" || bad "deepseek run exits clean"
want "$ROOT/spec-generator/.env" '^SPEC_GENERATOR_MODEL_SRS=deepseek:deepseek-v4-flash$' "deepseek: spec srs switched"
want "$ROOT/interview-engine/.env" '^INTERVIEW_ENGINE_MODEL_DISTILLATION=deepseek:deepseek-v4-flash$' "deepseek: interview distillation"
want "$ROOT/spec-generator/.env" '^DEEPSEEK_API_KEY=sk-test-AAAA$' "deepseek: key written (replaced old one)"
want "$ROOT/interview-engine/.env" '^DEEPSEEK_API_KEY=sk-test-AAAA$' "deepseek: key written where none existed"
want "$ROOT/verification-loop/.env" '^DEEPSEEK_API_KEY=sk-test-AAAA$' "deepseek: key written to verification-loop"
printf '%s' "$OUT" | grep -q 'sk-test-AAAA' && bad "key never echoed to stdout" || ok "key never echoed to stdout"
# rerun with a NEW key replaces the line, never duplicates
DEEPSEEK_API_KEY=sk-test-BBBB REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek >/dev/null
want "$ROOT/spec-generator/.env" '^DEEPSEEK_API_KEY=sk-test-BBBB$' "deepseek rerun: key replaced"
[ "$(grep -c '^DEEPSEEK_API_KEY=' "$ROOT/spec-generator/.env")" = "1" ] && ok "deepseek rerun: key not duplicated" || bad "deepseek rerun: key not duplicated"
[ "$(grep -c '^SPEC_GENERATOR_MODEL_SRS=' "$ROOT/spec-generator/.env")" = "1" ] && ok "idempotent: no duplicate keys" || bad "idempotent: no duplicate keys"
# hidden-prompt path: key on stdin, not echoed
OUT="$(printf 'sk-test-CCCC\n' | REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek)" || bad "deepseek prompt path exits clean"
want "$ROOT/interview-engine/.env" '^DEEPSEEK_API_KEY=sk-test-CCCC$' "prompt: key written from hidden prompt"
printf '%s' "$OUT" | grep -q 'sk-test-CCCC' && bad "prompt: key never echoed" || ok "prompt: key never echoed"
# no key anywhere (stdin EOF) fails loudly, writes nothing
printf 'DEEPSEEK_API_KEY=keepme\n' > "$ROOT/verification-loop/.env"
REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" deepseek </dev/null >/dev/null 2>&1 && bad "missing key rejected" || ok "missing key rejected"
want "$ROOT/verification-loop/.env" '^DEEPSEEK_API_KEY=keepme$' "missing key: existing .env untouched"
# openai: key via env pass-through, default model gpt-5.4-mini
OUT="$(OPENAI_API_KEY=sk-oai-AAAA REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" openai)" || bad "openai run exits clean"
want "$ROOT/spec-generator/.env" '^SPEC_GENERATOR_MODEL_SRS=openai:gpt-5\.4-mini$' "openai: spec srs switched to default model"
want "$ROOT/interview-engine/.env" '^INTERVIEW_ENGINE_MODEL_PROBING=openai:gpt-5\.4-mini$' "openai: interview probing"
want "$ROOT/verification-loop/.env" '^VERIFICATION_LOOP_MODEL_RESIDUE_JUDGE=openai:gpt-5\.4-mini$' "openai: verification judge"
want "$ROOT/interview-engine/.env" '^OPENAI_API_KEY=sk-oai-AAAA$' "openai: key written"
printf '%s' "$OUT" | grep -q 'sk-oai-AAAA' && bad "openai: key never echoed" || ok "openai: key never echoed"
want "$ROOT/interview-engine/.env" '^DEEPSEEK_API_KEY=sk-test-CCCC$' "openai: deepseek key preserved"
# model override without a code change
OPENAI_MODEL=gpt-5.4 OPENAI_API_KEY=sk-oai-BBBB REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" openai >/dev/null
want "$ROOT/spec-generator/.env" '^SPEC_GENERATOR_MODEL_SRS=openai:gpt-5\.4$' "openai: OPENAI_MODEL override respected"
want "$ROOT/spec-generator/.env" '^OPENAI_API_KEY=sk-oai-BBBB$' "openai rerun: key replaced"
[ "$(grep -c '^OPENAI_API_KEY=' "$ROOT/spec-generator/.env")" = "1" ] && ok "openai rerun: key not duplicated" || bad "openai rerun: key not duplicated"
# openai prompt path + empty rejection
OUT="$(printf 'sk-oai-CCCC\n' | REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" openai)" || bad "openai prompt path exits clean"
want "$ROOT/interview-engine/.env" '^OPENAI_API_KEY=sk-oai-CCCC$' "openai prompt: key written from hidden prompt"
printf '%s' "$OUT" | grep -q 'sk-oai-CCCC' && bad "openai prompt: key never echoed" || ok "openai prompt: key never echoed"
REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/switch-model.sh" openai </dev/null >/dev/null 2>&1 && bad "openai missing key rejected" || ok "openai missing key rejected"

# unknown provider fails loudly
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
PATH="$BIN:$PATH" REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/run-full-flow.sh" "a test idea" >/dev/null \
  && ok "full flow exits clean" || bad "full flow exits clean"
grep -q "interview_engine.cli a test idea" "$SHIM_LOG" && ok "interview got the idea" || bad "interview got the idea"
grep -q "spec_generator.cli $ROOT/interview-engine/out/20260909-210000-ab12/intent_model.json -o bundle/ --review" "$SHIM_LOG" \
  && ok "spec-generator got the captured session's intent model + --review" || { bad "spec-generator handoff"; cat "$SHIM_LOG"; }
# unapproved interview (no intent_model.json) stops before spec-generator
rm -f "$ROOT/interview-engine/out/20260909-210000-ab12/intent_model.json"
: > "$SHIM_LOG"
PATH="$BIN:$PATH" SHIM_NO_APPROVE=1 REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/run-full-flow.sh" "again" >/dev/null 2>&1 \
  && bad "unapproved interview stops the flow" || ok "unapproved interview stops the flow"
grep -q "spec_generator" "$SHIM_LOG" && bad "spec-generator NOT run without approval" || ok "spec-generator NOT run without approval"

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
