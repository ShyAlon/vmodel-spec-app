#!/usr/bin/env bash
# Update the six V-model repositories without merges or destructive recovery.
# Compatible with the macOS system Bash 3.2.
set -u

REPOS="interview-engine spec-generator vmodel-contracts verification-loop delivery-api vmodel-spec-app"
ROOT=${VMODEL_REPOS_ROOT:-"$(cd "$(dirname "$0")/../.." && pwd)"}
failed=0

printf 'V-model update root: %s\n\n' "$ROOT"
for repo in $REPOS; do
  dir="$ROOT/$repo"
  printf '%-20s ' "$repo"
  if [ ! -d "$dir/.git" ]; then
    printf 'FAILED\n  Cause: %s is not a Git repository.\n  Next: clone %s into %s and run this script again.\n\n' "$dir" "$repo" "$ROOT"
    failed=1
    continue
  fi
  if ! status=$(git -C "$dir" status --porcelain 2>&1); then
    printf 'FAILED\n  Cause: Git could not inspect the repository: %s\n  Next: run: git -C %s status\n\n' "$status" "$dir"
    failed=1
    continue
  fi
  if [ -n "$status" ]; then
    printf 'FAILED\n  Cause: local changes would make an automatic update unsafe.\n  Next: run: git -C %s status\n        then commit or stash those changes and rerun this script.\n\n' "$dir"
    failed=1
    continue
  fi
  before=$(git -C "$dir" rev-parse HEAD 2>&1) || {
    printf 'FAILED\n  Cause: no current commit could be read.\n  Next: run: git -C %s status\n\n' "$dir"
    failed=1
    continue
  }
  output=$(git -C "$dir" pull --ff-only 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    one_line=$(printf '%s' "$output" | tail -n 1)
    printf 'FAILED\n  Cause: git pull --ff-only failed: %s\n  Next: run: git -C %s pull --ff-only\n        Resolve the reported network, tracking, or divergence issue without force-pushing, then rerun this script.\n\n' "$one_line" "$dir"
    failed=1
    continue
  fi
  after=$(git -C "$dir" rev-parse HEAD)
  if [ "$before" = "$after" ]; then
    printf 'already current (%s)\n' "$(printf %.8s "$after")"
  else
    printf 'pulled %s..%s\n' "$(printf %.8s "$before")" "$(printf %.8s "$after")"
  fi
done

if [ "$failed" -ne 0 ]; then
  printf '\nOne or more repositories were not updated. Follow each exact Next action above.\n'
  exit 1
fi
# A git pull updates source trees, not packages copied into the active venv.
PYTHON_BIN=${VMODEL_PYTHON:-python}
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  printf '\nFAILED\n  Cause: python is unavailable, so the active environment cannot be synchronized.\n  Next: activate the V-model virtualenv and rerun this script.\n'
  exit 1
fi
printf '\nSynchronizing active Python environment... '
if ! install_output=$("$PYTHON_BIN" -m pip install --disable-pip-version-check --no-deps -e "$ROOT/vmodel-contracts" -e "$ROOT/interview-engine" -e "$ROOT/spec-generator" 2>&1); then
  one_line=$(printf '%s' "$install_output" | tail -n 1)
  printf 'FAILED\n  Cause: editable install failed: %s\n  Next: activate the V-model virtualenv and rerun this script.\n' "$one_line"
  exit 1
fi
actual=$("$PYTHON_BIN" -c 'import pathlib,vmodel_contracts; print(pathlib.Path(vmodel_contracts.__file__).resolve())' 2>&1) || {
  printf 'FAILED\n  Cause: vmodel-contracts could not be imported after synchronization: %s\n' "$actual"
  exit 1
}
case "$actual" in
  "$ROOT/vmodel-contracts"/*) printf 'current (editable contracts: %s)\n' "$actual" ;;
  *) printf 'FAILED\n  Cause: Python still imports contracts from %s, not %s/vmodel-contracts.\n  Next: run: %s -m pip install --no-deps -e %s/vmodel-contracts\n' "$actual" "$ROOT" "$PYTHON_BIN" "$ROOT"; exit 1 ;;
esac
printf '\nAll six repositories and the active Python environment are current.\n'
