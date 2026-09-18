#!/usr/bin/env bash
set -euo pipefail
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/require"; mkdir -p "$ROOT/vmodel-spec-app" "$ROOT/interview-engine" "$ROOT/spec-generator" "$ROOT/verification-loop"
printf 'DEEPSEEK_API_KEY=sk-existing-secret\n' > "$ROOT/.env"
OUT=$(REQUIRE_ROOT="$ROOT" bash "$(dirname "$0")/../switch-model.sh" deepseek </dev/null)
grep -q 'DEEPSEEK_API_KEY: keeping existing shared key' <<<"$OUT"
! grep -q 'sk-existing-secret' <<<"$OUT"
grep -q '^DEEPSEEK_API_KEY=sk-existing-secret$' "$ROOT/.env"
# Missing key still takes hidden stdin prompt and stores the supplied value.
rm -f "$ROOT/.env"
printf 'sk-new-secret\n' | REQUIRE_ROOT="$ROOT" bash "$(dirname "$0")/../switch-model.sh" deepseek >/tmp/switch-key-out
! grep -q 'sk-new-secret' /tmp/switch-key-out
grep -q '^DEEPSEEK_API_KEY=sk-new-secret$' "$ROOT/.env"
echo 'ok - existing key reused silently; missing key prompted and stored'
