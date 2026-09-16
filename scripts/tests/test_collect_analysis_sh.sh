#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SCRIPTS="$(dirname "$HERE")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "ok - $1"; }; bad(){ FAIL=$((FAIL+1)); echo "FAIL - $1"; }
ROOT="$TMP/require"; SG="$ROOT/spec-generator"; APP="$ROOT/vmodel-spec-app"; mkdir -p "$SG" "$APP" "$ROOT/artifacts"
complete(){ d="$1"; mkdir -p "$d/specs"; printf '{}' > "$d/manifest.json"; printf '{}' > "$d/traceability.json"; printf '{"functional":[],"non_functional":[]}' > "$d/srs.json"; printf '[]' > "$d/items.json"; printf '[]' > "$d/tests.json"; }
OLD="$ROOT/artifacts/20260912-201837-bd17/spec"; NEW="$ROOT/artifacts/20260916-081731-5dd9/spec"; complete "$OLD"; complete "$NEW"
# A stale legacy export is newer by mtime and lexically tempting; it must be ignored.
LEGACY="$SG/artifacts-2026-09-99_99-99-99"; complete "$LEGACY"; touch "$LEGACY"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh")" || bad "canonical auto-select exits clean"
printf '%s' "$OUT" | grep -q 'Selected session: 20260916-081731-5dd9' && ok "newest canonical session selected" || { bad "wrong session"; echo "$OUT"; }
printf '%s' "$OUT" | grep -q 'Selection reason: newest canonical session id' && ok "selection reason printed" || bad "selection reason missing"
printf '%s' "$OUT" | grep -q "Selected artifacts directory: $NEW" && ok "garage spec selected, stale export ignored" || bad "wrong artifacts"
BUNDLE="$(printf '%s' "$OUT" | sed -n 's/^Send this file: //p')"; [ -f "$BUNDLE" ] && ok "bundle written" || bad "bundle missing"
tar -tzf "$BUNDLE" | grep -q MANIFEST.json && ok "bundle manifest included" || bad "bundle manifest missing"
# Explicit session is deterministic.
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh" --session 20260912-201837-bd17)" || bad "explicit session exits clean"
printf '%s' "$OUT" | grep -q 'Selection reason: explicit --session 20260912-201837-bd17' && ok "explicit session override" || bad "explicit session ignored"
# Newest incomplete refuses to substitute older complete.
INC="$ROOT/artifacts/20260917-090000-abcd/spec"; mkdir -p "$INC"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh" 2>&1)" && bad "incomplete newest refuses" || ok "incomplete newest refuses"
printf '%s' "$OUT" | grep -q 'Do not substitute an older run' && ok "incomplete error names anti-fallback" || bad "weak incomplete error"
rm -rf "$ROOT/artifacts/20260917-090000-abcd"
# Multiple plausible completed variants refuse.
complete "$ROOT/artifacts/20260916-081731-5dd9/spec-fresh"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh" --session 20260916-081731-5dd9 2>&1)" && bad "ambiguous variants refuse" || ok "ambiguous variants refuse"
printf '%s' "$OUT" | grep -q 'multiple completed spec bundles' && ok "ambiguity names candidates" || bad "weak ambiguity error"
# Explicit artifacts remains clean legacy/experiment escape hatch.
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh" --artifacts "$LEGACY")" || bad "explicit artifacts exits clean"
printf '%s' "$OUT" | grep -q 'Selection reason: explicit --artifacts override' && ok "explicit artifacts override" || bad "explicit artifacts ignored"
echo "$PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]
