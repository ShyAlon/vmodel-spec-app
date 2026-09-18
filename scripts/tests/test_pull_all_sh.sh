#!/usr/bin/env bash
set -euo pipefail
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/require"; BIN="$TMP/bin"; mkdir -p "$ROOT" "$BIN"
for repo in interview-engine spec-generator vmodel-contracts verification-loop delivery-api vmodel-spec-app; do mkdir -p "$ROOT/$repo/.git"; done
cat > "$BIN/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
 *"status --porcelain"*) exit 0;;
 *"rev-parse HEAD"*) echo abcdef1234567890;;
 *"pull --ff-only"*) echo current;;
 *) exit 1;;
esac
EOF
cat > "$BIN/python" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$PYTHON_LOG"
if [ "$1 $2" = "-m pip" ]; then exit 0; fi
if [ "$1" = "-c" ]; then printf '%s/vmodel-contracts/src/vmodel_contracts/__init__.py\n' "$VMODEL_REPOS_ROOT"; exit 0; fi
exit 1
EOF
chmod +x "$BIN/git" "$BIN/python"; export PYTHON_LOG="$TMP/python.log"
PATH="$BIN:$PATH" VMODEL_REPOS_ROOT="$ROOT" bash "$(dirname "$0")/../pull-all.sh" > "$TMP/out"
grep -q -- '-m pip install --disable-pip-version-check --no-deps -e .*vmodel-contracts -e .*interview-engine -e .*spec-generator' "$PYTHON_LOG"
grep -q 'active Python environment are current' "$TMP/out"
echo 'ok - pull-all synchronizes active environment with editable repos'
