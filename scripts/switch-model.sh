#!/usr/bin/env bash
# switch-model.sh - point every process's repo-local .env at one LLM.
#
#   scripts/switch-model.sh ollama     # local, qwen2.5-coder:14b, $0 (the standing default)
#   scripts/switch-model.sh deepseek   # DeepSeek V4 Flash (deepseek-v4-flash), needs DEEPSEEK_API_KEY
#
# Writes <repo>/.env for every process repo that exists (interview-engine,
# spec-generator, verification-loop). The processes load their .env at
# startup (model_config._dotenv); real environment variables always win
# over the file, and repo DEFAULTS are untouched - this is a switcher, not a
# default change.
#
# The DeepSeek key: hand it over without it ever landing in shell history or
# a process list - either export it first:
#   DEEPSEEK_API_KEY=sk-... scripts/switch-model.sh deepseek
# or just run `switch-model.sh deepseek` and it prompts with hidden input.
# The key is written into each repo's .env (reruns replace, never duplicate),
# never printed back, and .env is gitignored in every process repo.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: $0 ollama|deepseek   (deepseek: key via DEEPSEEK_API_KEY or a hidden prompt)"
case "$1" in
  ollama)   MODEL="ollama:qwen2.5-coder:14b" ;;
  deepseek) MODEL="deepseek:deepseek-v4-flash" ;;
  *)        die "unknown provider '$1' (want: ollama|deepseek)" ;;
esac

# sed -i differs: GNU takes a bare -i, BSD/macOS takes -i ''. Detect once.
if sed --version >/dev/null 2>&1; then SED_I=(sed -i -e); else SED_I=(sed -i '' -e); fi

# repos live side by side under the require/ dir; override with REQUIRE_ROOT.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# set_env FILE KEY VALUE - update the KEY= line in place or append it; every
# other line (comments, unrelated settings) is preserved. Reruns replace.
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

# On deepseek, resolve the API key BEFORE touching files: env pass-through
# first, then a hidden prompt. The value is only ever written to .env files.
API_KEY=""
if [ "$1" = "deepseek" ]; then
  API_KEY="${DEEPSEEK_API_KEY:-}"
  if [ -z "$API_KEY" ]; then
    read -r -s -p "DeepSeek API key (hidden): " API_KEY; echo
  fi
  [ -n "$API_KEY" ] || die "no key given - export DEEPSEEK_API_KEY or answer the prompt"
fi

echo "Switching all processes to $MODEL"
switch_repo interview-engine \
  INTERVIEW_ENGINE_MODEL_PROBING INTERVIEW_ENGINE_MODEL_DISTILLATION \
  INTERVIEW_ENGINE_MODEL_PHRASING INTERVIEW_ENGINE_MODEL_SCOPE_TIEBREAK
switch_repo spec-generator \
  SPEC_GENERATOR_MODEL_NEEDS SPEC_GENERATOR_MODEL_SRS SPEC_GENERATOR_MODEL_ARCHITECTURE \
  SPEC_GENERATOR_MODEL_ITEMS SPEC_GENERATOR_MODEL_TESTS SPEC_GENERATOR_MODEL_REVIEW
switch_repo verification-loop VERIFICATION_LOOP_MODEL_RESIDUE_JUDGE

if [ "$1" = "deepseek" ]; then
  for repo in interview-engine spec-generator verification-loop; do
    [ -d "$REQUIRE_ROOT/$repo" ] && set_env "$REQUIRE_ROOT/$repo/.env" DEEPSEEK_API_KEY "$API_KEY"
  done
  API_KEY=""  # drop it from the shell as soon as it is on disk
  echo
  echo "API key written into each repo's .env (gitignored, never leaves your machine except to DeepSeek)."
fi
echo "Done. Processes read their .env on next start; exported shell variables still override it."
