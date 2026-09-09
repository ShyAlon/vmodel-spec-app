#!/usr/bin/env bash
# switch-model.sh - point every process's repo-local .env at one LLM.
#
#   scripts/switch-model.sh ollama     # local, qwen2.5-coder:14b, $0 (the standing default)
#   scripts/switch-model.sh deepseek   # DeepSeek V4 Flash (deepseek-v4-flash), needs DEEPSEEK_API_KEY
#
# Writes <repo>/.env for every process repo that exists (interview-engine,
# spec-generator, verification-loop). The processes load their .env at
# startup (model_config._load_dotenv); real environment variables always win
# over the file, and repo DEFAULTS are untouched - this is a switcher, not a
# default change. The DeepSeek key is never written by this script: the .env
# gets an empty DEEPSEEK_API_KEY= line for you to paste into locally.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: $0 ollama|deepseek"
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
# other line (your API key, comments, unrelated settings) is preserved.
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
    f="$REQUIRE_ROOT/$repo/.env"
    [ -f "$f" ] && ! grep -qE '^DEEPSEEK_API_KEY=' "$f" && \
      printf '# paste your key here - never committed, never written by the switcher\nDEEPSEEK_API_KEY=\n' >> "$f"
  done
  echo
  echo "DeepSeek needs your API key: paste it after DEEPSEEK_API_KEY= in each repo's .env"
  echo "(key stays local to your machine - it is never written by scripts or sent anywhere but DeepSeek)."
fi
echo "Done. Processes read their .env on next start; exported shell variables still override it."
