#!/usr/bin/env bash
# switch-model.sh - point every process's repo-local .env at one LLM.
#
#   scripts/switch-model.sh ollama     # local, qwen2.5-coder:14b, $0 (the standing default)
#   scripts/switch-model.sh deepseek   # DeepSeek V4 Flash (deepseek-v4-flash), needs DEEPSEEK_API_KEY
#   scripts/switch-model.sh openai     # OpenAI gpt-5.4-mini by default, needs OPENAI_API_KEY
#                                      # override the model without a code change:
#                                      #   OPENAI_MODEL=gpt-5.4 scripts/switch-model.sh openai
#
# Writes <repo>/.env for every process repo that exists (interview-engine,
# spec-generator, verification-loop). The processes load their .env at
# startup (model_config._env); real environment variables always win
# over the file, and repo DEFAULTS are untouched - this is a switcher, not a
# default change.
#
# API keys: hand them over without landing in shell history or a process
# list - either export first:
#   OPENAI_API_KEY=sk-... scripts/switch-model.sh openai
# or just run the script and it prompts with hidden input. Keys are written
# into each repo's .env (reruns replace, never duplicate), never printed
# back, and .env is gitignored in every process repo.
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

# set_env FILE KEY VALUE - update the KEY= line in place or append it; every
# other line (comments, unrelated settings, the OTHER provider's key) is
# preserved. Reruns replace.
set_env() {
  local file="$1" key="$2" value="$3"
  touch "$file"
  if grep -qE "^${key}=" "$file"; then
    "${SED_I[@]}" "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

switch_repo() {
  local repo="$1"; shift
  local dir="$REQUIRE_ROOT/$repo"
  if [ ! -d "$dir" ]; then
    echo "  - $repo: not found at $dir (skipped)"
    return
  fi
  local envfile="$dir/.env"
  for key in "$@"; do
    set_env "$envfile" "$key" "$MODEL"
  done
  echo "  - $repo: $(basename "$envfile") -> $MODEL"
}

# Resolve the provider's API key BEFORE touching files: env pass-through
# first, then a hidden prompt. The value is only ever written to .env files.
API_KEY=""
if [ -n "$KEY_VAR" ]; then
  eval "API_KEY=\"\${$KEY_VAR:-}\""
  if [ -z "$API_KEY" ]; then
    read -r -s -p "$1 API key (hidden): " API_KEY; echo
  fi
  [ -n "$API_KEY" ] || die "no key given - export $KEY_VAR or answer the prompt"
fi

echo "Switching all processes to $MODEL"
switch_repo interview-engine \
  INTERVIEW_ENGINE_MODEL_PROBING INTERVIEW_ENGINE_MODEL_DISTILLATION \
  INTERVIEW_ENGINE_MODEL_PHRASING INTERVIEW_ENGINE_MODEL_SCOPE_TIEBREAK
switch_repo spec-generator \
  SPEC_GENERATOR_MODEL_NEEDS SPEC_GENERATOR_MODEL_SRS SPEC_GENERATOR_MODEL_ARCHITECTURE \
  SPEC_GENERATOR_MODEL_ITEMS SPEC_GENERATOR_MODEL_TESTS SPEC_GENERATOR_MODEL_REVIEW
switch_repo verification-loop VERIFICATION_LOOP_MODEL_RESIDUE_JUDGE

if [ -n "$KEY_VAR" ]; then
  for repo in interview-engine spec-generator verification-loop; do
    [ -d "$REQUIRE_ROOT/$repo" ] && set_env "$REQUIRE_ROOT/$repo/.env" "$KEY_VAR" "$API_KEY"
  done
  API_KEY=""  # drop it from the shell as soon as it is on disk
  echo
  echo "API key written into each repo's .env (gitignored, never leaves your machine except to the provider)."
fi
echo "Done. Processes read their .env on next start; exported shell variables still override it."
