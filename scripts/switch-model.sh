#!/usr/bin/env bash
# switch-model.sh - point every process at one LLM via ONE shared config file.
#
#   scripts/switch-model.sh ollama     # local, qwen2.5-coder:14b, $0 (the standing default)
#   scripts/switch-model.sh deepseek   # DeepSeek V4 Flash (deepseek-v4-flash), needs DEEPSEEK_API_KEY
#   scripts/switch-model.sh openai     # OpenAI gpt-5.4-mini by default, needs OPENAI_API_KEY
#                                      # override the model without a code change:
#                                      #   OPENAI_MODEL=gpt-5.4 scripts/switch-model.sh openai
#
# Writes <require-root>/.env - the SHARED file every process reads first
# (model_config._dotenv: shared file, then repo-local .env as an override
# layer, real environment variables always win). Repo DEFAULTS in code are
# untouched - this is a switcher, not a default change.
#
# Migration: managed keys (MODEL_* routing, API keys) found in a repo-local
# .env are MOVED to the shared file (values preserved) and removed from the
# repo file, so stale per-repo overrides never linger. Unrelated lines in
# repo .env files are left alone.
#
# Guardrail knobs (VMODEL_LLM_CALL_TIMEOUT_S / VMODEL_LLM_STALL_TIMEOUT_S /
# VMODEL_LLM_MAX_CALLS): defaults are added to the shared file when absent
# and NEVER overwritten once set. VMODEL_LLM_MAX_TOKENS is documented in a
# comment instead (its default is per stage, not one number).
#
# API keys: hand them over without landing in shell history or a process
# list - either export first:
#   OPENAI_API_KEY=sk-... scripts/switch-model.sh openai
# or just run the script and it prompts with hidden input. Keys live in the
# shared .env (reruns replace, never duplicate), never printed back. The
# require root is not a git repo, so the shared .env is untracked by
# construction; repo .env files stay gitignored for the override layer.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: $0 ollama|deepseek|openai   (keys via env pass-through or a hidden prompt)"
KEY_VAR=""
case "$1" in
  ollama)   MODEL="ollama:qwen2.5-coder:14b" ;;
  deepseek) MODEL="deepseek:deepseek-v4-flash"; KEY_VAR="DEEPSEEK_API_KEY" ;;
  openai)   MODEL="openai:${OPENAI_MODEL:-gpt-5.4-mini}"; KEY_VAR="OPENAI_API_KEY" ;;
  *)        die "unknown provider '$1' (want: ollama|deepseek|openai)" ;;
esac

# sed -i differs: GNU takes a bare -i, BSD/macOS takes -i ''. Detect once.
if sed --version >/dev/null 2>&1; then SED_I=(sed -i -e); else SED_I=(sed -i '' -e); fi

# repos live side by side under the require/ dir; override with REQUIRE_ROOT.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SHARED="$REQUIRE_ROOT/.env"

MODEL_KEYS="INTERVIEW_ENGINE_MODEL_PROBING INTERVIEW_ENGINE_MODEL_DISTILLATION \
INTERVIEW_ENGINE_MODEL_PHRASING INTERVIEW_ENGINE_MODEL_SCOPE_TIEBREAK \
SPEC_GENERATOR_MODEL_NEEDS SPEC_GENERATOR_MODEL_SRS SPEC_GENERATOR_MODEL_ARCHITECTURE \
SPEC_GENERATOR_MODEL_ITEMS SPEC_GENERATOR_MODEL_TESTS SPEC_GENERATOR_MODEL_REVIEW \
VERIFICATION_LOOP_MODEL_RESIDUE_JUDGE"
KEY_VARS="DEEPSEEK_API_KEY OPENAI_API_KEY"

# set_env FILE KEY VALUE - update the KEY= line in place or append it; every
# other line is preserved. Reruns replace.
set_env() {
  local file="$1" key="$2" value="$3"
  touch "$file"
  if grep -qE "^${key}=" "$file"; then
    "${SED_I[@]}" "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

# migrate_repo_env REPO - move managed keys from <repo>/.env into the shared
# file (values preserved, shared not clobbered), then strip them locally.
migrate_repo_env() {
  local f="$REQUIRE_ROOT/$1/.env"
  [ -f "$f" ] || return 0
  local k v moved=""
  for k in $MODEL_KEYS $KEY_VARS; do
    if grep -qE "^${k}=." "$f"; then        # non-empty value worth preserving
      v="$(grep -E "^${k}=" "$f" | head -1 | cut -d= -f2-)"
      grep -qE "^${k}=." "$SHARED" 2>/dev/null || { touch "$SHARED"; printf '%s=%s\n' "$k" "$v" >> "$SHARED"; }
      moved="$moved $k"
    elif grep -qE "^${k}=" "$f"; then
      moved="$moved $k"
    fi
    grep -qE "^${k}=" "$f" && "${SED_I[@]}" "/^${k}=/d" "$f"
  done
  [ -n "$moved" ] && echo "  - $1: moved managed keys to shared .env:$(echo $moved | sed 's/ /, /g')"
  return 0
}

# Resolve the provider's API key BEFORE touching files: env pass-through
# first, then a hidden prompt. The value is only ever written to the shared
# .env file.
API_KEY=""
if [ -n "$KEY_VAR" ]; then
  eval "API_KEY=\"\${$KEY_VAR:-}\""
  if [ -z "$API_KEY" ]; then
    read -r -s -p "$1 API key (hidden): " API_KEY; echo
  fi
  [ -n "$API_KEY" ] || die "no key given - export $KEY_VAR or answer the prompt"
fi

echo "Switching all processes to $MODEL (shared config: $SHARED)"
for repo in interview-engine spec-generator verification-loop; do
  if [ ! -d "$REQUIRE_ROOT/$repo" ]; then
    echo "  - $repo: not found at $REQUIRE_ROOT/$repo (skipped)"
    continue
  fi
  migrate_repo_env "$repo"
done
for k in $MODEL_KEYS; do
  set_env "$SHARED" "$k" "$MODEL"
done

# Guardrail knobs: write the defaults when ABSENT, never override a value the
# user already set - these are global limits and his edits are the point.
ensure_default() {
  local key="$1" value="$2"
  grep -qE "^${key}=" "$SHARED" 2>/dev/null && return 0
  printf '%s=%s\n' "$key" "$value" >> "$SHARED"
  echo "  - added default $key=$value (tune freely; never overwritten)"
}
ensure_default VMODEL_LLM_CALL_TIMEOUT_S 600
ensure_default VMODEL_LLM_STALL_TIMEOUT_S 180
ensure_default VMODEL_LLM_MAX_CALLS 200
# VMODEL_LLM_MAX_TOKENS has no single default - each stage ships its own tuned
# ceiling - so document it in a comment once instead of writing a misleading value.
if ! grep -qE "^VMODEL_LLM_MAX_TOKENS=" "$SHARED" && ! grep -q "^# VMODEL_LLM_MAX_TOKENS:" "$SHARED"; then
  printf '%s\n' \
    "# VMODEL_LLM_MAX_TOKENS: per-call generation-length ceiling. Unset = each stage's tuned" \
    "# default (spec-generator 8192, its tests stage 12288, interview-engine 2048," \
    "# verification-loop 4096). Uncomment with a number to cap every call globally." \
    "#VMODEL_LLM_MAX_TOKENS=" >> "$SHARED"
  echo "  - documented VMODEL_LLM_MAX_TOKENS (per-stage defaults; uncomment to cap globally)"
fi
if [ -n "$KEY_VAR" ]; then
  set_env "$SHARED" "$KEY_VAR" "$API_KEY"
  API_KEY=""  # drop it from the shell as soon as it is on disk
  echo
  echo "API key written into $SHARED (untracked by any repo, never leaves your machine except to the provider)."
fi
echo "Done. Processes read the shared .env on next start; a repo-local .env overrides it, and exported shell variables override both."
