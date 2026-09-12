#!/usr/bin/env bash
# Sanity tests for collect-analysis.sh (standing rule: tests before ship).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(dirname "$HERE")"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "ok - $1"; }
bad()  { FAIL=$((FAIL+1)); echo "FAIL - $1"; }

ROOT="$TMP/require"
SG="$ROOT/spec-generator"; APP="$ROOT/vmodel-spec-app"
mkdir -p "$SG" "$APP"
OLD="$SG/artifacts-2026-09-01_10-00-00"
NEW="$SG/artifacts-2026-09-10_20-55-21-architecture-2026-09-12_12-04-18"
mkdir -p "$OLD/specs" "$NEW/specs"

# OLD: a complete full run (has manifest.json)
printf '{"functional":[{"requirement_id":"R-1"}],"non_functional":[]}' > "$OLD/srs.json"
printf '[{"spec_id":"SPEC-1"}]' > "$OLD/items.json"
printf '[{"test_id":"T-1"}]' > "$OLD/tests.json"
printf '{}' > "$OLD/traceability.json"; printf '{}' > "$OLD/manifest.json"
printf '{"stage":"srs","provider":"ollama","model":"phi4","prompt_tokens":10,"completion_tokens":5,"cost_usd":0}\n' > "$OLD/usage.jsonl"
printf '%s\n' \
  '{"event":"llm_call_start","stage":"srs","provider":"ollama","model":"phi4","ts":"2026-09-01T10:00:00"}' \
  '{"event":"llm_call_end","stage":"srs","provider":"ollama","model":"phi4","latency_s":60.0,"ts":"2026-09-01T10:01:00"}' \
  '{"event":"llm_call_end","stage":"items","provider":"ollama","model":"phi4","latency_s":120.0,"ts":"2026-09-01T10:03:00"}' \
  > "$OLD/llm-calls.jsonl"
printf 'spec body' > "$OLD/specs/SPEC-1.md"
touch -t 202609011000 "$OLD"

# NEW: a NEWER stage experiment with resume partials, almost no files, NO manifest.json
printf '{"stack_entries":[]}' > "$NEW/architecture.json"
printf '{"stack_keys":["language"]}' > "$NEW/architecture.partial.json"

# auto-detect prefers the COMPLETED run over the newer experiment (the
# 2026-09-12 wrong-bundle round-trip shipped an experiment by mistake)
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh")" || bad "auto-detect run exits clean"
printf '%s' "$OUT" | grep -q "Auto-detected artifacts directory: $OLD" \
  && ok "auto-detect prefers the completed run (manifest.json) over the newer experiment" || { bad "auto-detect prefers the completed run (manifest.json) over the newer experiment"; echo "$OUT"; }
printf '%s' "$OUT" | grep -q "skipped stage experiment(s) without manifest.json: $(basename "$NEW")" \
  && ok "the skipped experiment is named" || { bad "the skipped experiment is named"; echo "$OUT"; }
BUNDLE="$(printf '%s' "$OUT" | sed -n 's/^Send this file: //p')"
[ -n "$BUNDLE" ] && [ -f "$BUNDLE" ] && ok "bundle exists at the printed path" || bad "bundle exists at the printed path"
case "$BUNDLE" in
  *"artifacts-2026-09-01_10-00-00-analysis-"*".tar.gz") ok "bundle named after the artifacts dir + timestamp" ;;
  *) bad "bundle named after the artifacts dir + timestamp ($BUNDLE)" ;;
esac
printf '%s' "$OUT" | grep -q "Status: complete (full bundle assembled)" && ok "complete run reported complete" || { bad "complete run reported complete"; echo "$OUT"; }
printf '%s' "$OUT" | grep -q "items=1, srs=1" && ok "stage call counts from llm-calls.jsonl" || { bad "stage call counts"; echo "$OUT"; }
printf '%s' "$OUT" | grep -q "ollama:phi4" && ok "model used is named" || bad "model used is named"
printf '%s' "$OUT" | grep -q "wall time (LLM log span): 3m0s" && ok "wall time spans the LLM log" || { bad "wall time"; echo "$OUT"; }
printf '%s' "$OUT" | grep -q "tokens: 10 in / 5 out" && ok "token totals from usage.jsonl" || { bad "token totals"; echo "$OUT"; }
printf '%s' "$OUT" | grep -q "requirements=1, specs=1, tests=1" && ok "artifact counts" || { bad "artifact counts"; echo "$OUT"; }
printf '%s' "$OUT" | grep -q "missing: nothing expected\|missing: .*run.log" && ok "missing list is honest" || bad "missing list is honest"
tar -tzf "$BUNDLE" | grep -q "MANIFEST.json" && ok "bundle carries MANIFEST.json" || bad "bundle carries MANIFEST.json"
# a second auto-detect run must ignore the bundle file it just wrote (not a dir)
OUT2="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh")" || bad "second auto-detect run exits clean"
printf '%s' "$OUT2" | grep -q "Auto-detected artifacts directory: $OLD" \
  && ok "auto-detect ignores its own bundle files" || bad "auto-detect ignores its own bundle files"

# the workspace-sibling artifacts/ folder (the 2026-09-12 default root) is
# searched too: a COMPLETED sibling run wins on recency
SIB="$ROOT/artifacts/artifacts-2026-09-12_14-00-00"
mkdir -p "$SIB"
printf '{"stack_entries":[]}' > "$SIB/architecture.json"
printf '{}' > "$SIB/manifest.json"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh")" || bad "sibling-root auto-detect run exits clean"
printf '%s' "$OUT" | grep -q "Auto-detected artifacts directory: $SIB" \
  && ok "auto-detect searches the sibling artifacts/ root" || { bad "auto-detect searches the sibling artifacts/ root"; echo "$OUT"; }
rm -rf "$ROOT/artifacts"
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh")" || bad "fallback auto-detect run exits clean"
printf '%s' "$OUT" | grep -q "Auto-detected artifacts directory: $OLD" \
  && ok "auto-detect falls back to spec-generator/ runs" || { bad "auto-detect falls back to spec-generator/ runs"; echo "$OUT"; }

# explicit dir override: the stage experiment, labeled as such
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh" --artifacts "$NEW")" || bad "explicit --artifacts run exits clean"
printf '%s' "$OUT" | grep -q "Status: stage experiment (--only-stage architecture); 1 per-slot partial(s) present" \
  && ok "status line names the stage experiment and the resume partials" || { bad "status line"; echo "$OUT"; }
printf '%s' "$OUT" | grep -q "missing:" && printf '%s' "$OUT" | grep -q "llm-calls.jsonl" \
  && ok "missing files are named, not fatal" || bad "missing files are named, not fatal"
tar -tzf "$(printf '%s' "$OUT" | sed -n 's/^Send this file: //p')" | grep -q "architecture.partial.json" \
  && ok "bundle carries the per-slot resume state" || bad "bundle carries the per-slot resume state"

# an experiments-only tree: newest experiment bundled, honestly labeled
EXP="$TMP/experiments/require"
mkdir -p "$EXP/spec-generator" "$EXP/vmodel-spec-app" "$EXP/spec-generator/artifacts-2099-01-01_00-00-00-architecture-2099-01-01_01-00-00"
printf '{"stack_entries":[]}' > "$EXP/spec-generator/artifacts-2099-01-01_00-00-00-architecture-2099-01-01_01-00-00/architecture.json"
OUT="$(REQUIRE_ROOT="$EXP" bash "$SCRIPTS/collect-analysis.sh")" || bad "experiments-only auto-detect exits clean"
printf '%s' "$OUT" | grep -q "no manifest.json - looks like a stage experiment; bundling it anyway" \
  && ok "experiments-only tree: experiment bundled with an honest label" || { bad "experiments-only tree: experiment bundled with an honest label"; echo "$OUT"; }

# positional form works too
REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh" "$OLD" >/dev/null && ok "positional artifacts dir" || bad "positional artifacts dir"

# no artifacts anywhere: human-readable failure, non-zero, no traceback
EMPTY="$TMP/empty"; mkdir -p "$EMPTY/spec-generator" "$EMPTY/vmodel-spec-app"
OUT="$(REQUIRE_ROOT="$EMPTY" bash "$SCRIPTS/collect-analysis.sh" 2>&1)" && bad "empty tree fails" || ok "empty tree fails"
printf '%s' "$OUT" | grep -q "^error: no artifacts-\* directory found" && ok "empty tree error is human-readable" || { bad "empty tree error is human-readable"; echo "$OUT"; }
printf '%s' "$OUT" | grep -qi "traceback" && bad "no python traceback leaks" || ok "no python traceback leaks"

# missing explicit dir: human-readable failure
OUT="$(REQUIRE_ROOT="$ROOT" bash "$SCRIPTS/collect-analysis.sh" --artifacts "$ROOT/nope" 2>&1)" && bad "bad dir fails" || ok "bad dir fails"
printf '%s' "$OUT" | grep -q "^error: artifacts directory not found" && ok "bad dir error is human-readable" || bad "bad dir error is human-readable"

# scripts README documents the collector
grep -q "collect-analysis.sh" "$SCRIPTS/README.md" && ok "scripts README documents collect-analysis.sh" || bad "scripts README documents collect-analysis.sh"

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
