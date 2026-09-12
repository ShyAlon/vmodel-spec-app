#!/usr/bin/env bash
# Collect one spec-generator run's analysis data into a single compressed
# bundle you can send for review: logs, artifacts, specs, and a manifest that
# says exactly what was found, what was included, and what was missing.
#
#   bash vmodel-spec-app/scripts/collect-analysis.sh
#   bash vmodel-spec-app/scripts/collect-analysis.sh --artifacts <dir>
#   bash vmodel-spec-app/scripts/collect-analysis.sh <dir>
#
# With no argument it picks the NEWEST artifacts-* directory under
# spec-generator. The bundle lands next to it as
# <artifacts-dir>-analysis-<timestamp>.tar.gz.
# `zsh collect-analysis.sh` and `sh collect-analysis.sh` override the shebang.
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "error: this script needs Bash; run: bash scripts/collect-analysis.sh $*" >&2
  exit 2
fi
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SG="$REQUIRE_ROOT/spec-generator"
APP="$REQUIRE_ROOT/vmodel-spec-app"
PYTHON_BIN="${COLLECT_ANALYSIS_PYTHON:-python3}"

fail() { echo "error: $*" >&2; exit 1; }

usage() {
  cat <<'EOF'
usage:
  scripts/collect-analysis.sh                      newest artifacts-* under spec-generator
  scripts/collect-analysis.sh --artifacts DIR      this specific run directory
  scripts/collect-analysis.sh DIR                  same, positional

Collects llm-calls.jsonl, usage.jsonl, run.log, the stage artifacts
(needs/srs/architecture/items/tests), specs/, traceability, manifest, the
batch report, and any *.partial.json resume state into
<artifacts-dir>-analysis-<timestamp>.tar.gz with a MANIFEST.json, and prints
a one-look summary (status, stage call counts, models, wall time, tokens).
EOF
}

ART=""
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --artifacts) ART="${2:-}"; [ -n "$ART" ] || fail "--artifacts needs a directory path" ;;
  "") ;;
  *) ART="$1" ;;
esac

[ -d "$SG" ] || fail "spec-generator not found at $SG"
command -v "$PYTHON_BIN" >/dev/null 2>&1 \
  || fail "python3 not found - the collector needs it to read the run's JSON logs (set COLLECT_ANALYSIS_PYTHON to override)"

if [ -z "$ART" ]; then
  # newest artifacts-* DIRECTORY (the analysis bundles we write are files and
  # must not shadow real runs)
  ART="$({ ls -1dt "$SG"/artifacts-* 2>/dev/null || true; } | while IFS= read -r c; do
           if [ -d "$c" ]; then echo "$c"; break; fi
         done)"
  [ -n "$ART" ] || fail "no artifacts-* directory found under $SG - pass one explicitly: bash scripts/collect-analysis.sh $SG/artifacts-..."
  echo "Auto-detected newest artifacts directory: $ART"
else
  [ -d "$ART" ] || fail "artifacts directory not found: $ART"
fi
ART="$(cd "$ART" && pwd)"
NAME="$(basename "$ART")"
STAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BUNDLE="$SG/${NAME}-analysis-${STAMP}.tar.gz"
n=2
while [ -e "$BUNDLE" ]; do
  BUNDLE="$SG/${NAME}-analysis-${STAMP}-$n.tar.gz"
  n=$((n+1))
done

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
WORK="$STAGE_DIR/$NAME"
mkdir -p "$WORK"

for f in needs.json needs.md srs.json srs.md architecture.json architecture.md \
         items.json tests.json traceability.json manifest.json review-fixes.json \
         system-baseline.json AGENTS.md usage.jsonl llm-calls.jsonl run.log; do
  if [ -f "$ART/$f" ]; then
    cp -p "$ART/$f" "$WORK/$f"
  fi
done
[ -d "$ART/specs" ] && cp -R "$ART/specs" "$WORK/specs"
for p in "$ART"/*.partial.json; do
  [ -e "$p" ] || continue
  cp -p "$p" "$WORK/$(basename "$p")"
done
for f in batch-report.json batch-report.md; do
  if [ -f "$APP/$f" ]; then
    cp -p "$APP/$f" "$WORK/$f"
  fi
done
if [ -f "$ART/checkpoints.sqlite" ]; then
  echo "note: checkpoints.sqlite left out (binary run state, not analysis data)"
fi

ART_DIR="$ART" WORK_DIR="$WORK" RUN_NAME="$NAME" BUNDLE_NAME="$(basename "$BUNDLE")" \
COLLECTED_AT="$STAMP" "$PYTHON_BIN" - <<'PY'
import datetime as dt
import json
import os
from pathlib import Path

art = Path(os.environ["ART_DIR"])
work = Path(os.environ["WORK_DIR"])

EXPECTED = ["needs.json", "needs.md", "srs.json", "srs.md", "architecture.json",
            "architecture.md", "items.json", "tests.json", "traceability.json",
            "manifest.json", "review-fixes.json", "system-baseline.json",
            "AGENTS.md", "usage.jsonl", "llm-calls.jsonl", "run.log", "specs"]

included = sorted(str(p.relative_to(work)) for p in work.rglob("*") if p.is_file())
missing = [f for f in EXPECTED if not (work / f).exists()]

def load_json(path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return None

def jsonl(path):
    if not path.exists():
        return []
    out = []
    for line in path.read_text().splitlines():
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return out

calls = jsonl(work / "llm-calls.jsonl")
usage = jsonl(work / "usage.jsonl")
ends = [e for e in calls if e.get("event") == "llm_call_end"]
errors = [e for e in calls if e.get("event") == "llm_call_error"]

stage_counts = {}
for e in ends:
    stage_counts[e.get("stage", "?")] = stage_counts.get(e.get("stage", "?"), 0) + 1

models = {}
for e in calls:
    prov, model = e.get("provider"), e.get("model")
    if prov and model:
        key = f"{prov}:{model}"
        models[key] = models.get(key, 0) + 1
for u in usage:
    prov, model = u.get("provider"), u.get("model")
    if prov and model:
        key = f"{prov}:{model}"
        models.setdefault(key, 0)

stamps = []
for e in calls:
    ts = e.get("ts")
    if ts:
        try:
            stamps.append(dt.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S"))
        except ValueError:
            pass
wall = (max(stamps) - min(stamps)) if len(stamps) >= 2 else None

def fmt_wall(seconds):
    s = int(seconds)
    if s >= 3600:
        return f"{s // 3600}h{(s % 3600) // 60}m"
    if s >= 60:
        return f"{s // 60}m{s % 60}s"
    return f"{s}s"

prompt_tok = sum(int(u.get("prompt_tokens", 0) or 0) for u in usage)
completion_tok = sum(int(u.get("completion_tokens", 0) or 0) for u in usage)
cost = sum(float(u.get("cost_usd", 0) or 0) for u in usage)

srs = load_json(work / "srs.json") or {}
items = load_json(work / "items.json")
tests = load_json(work / "tests.json")
n_req = len(srs.get("functional") or []) + len(srs.get("non_functional") or [])
n_specs = len(items) if isinstance(items, list) else None
n_tests = len(tests) if isinstance(tests, list) else None

partials = [f for f in included if f.endswith(".partial.json")]
name = os.environ["RUN_NAME"]
if (work / "manifest.json").exists() and (work / "traceability.json").exists():
    status = "complete (full bundle assembled)"
else:
    status = "partial"
    for stage in ("needs", "srs", "architecture", "items", "tests", "review"):
        marker = f"-{stage}-2"
        if marker in name:
            status = f"stage experiment (--only-stage {stage})"
            break
    if partials:
        status += f"; {len(partials)} per-slot partial(s) present - a rerun resumes from them"

manifest = {
    "artifacts_dir": name,
    "source_path": str(art),
    "collected_at": os.environ["COLLECTED_AT"],
    "bundle": os.environ["BUNDLE_NAME"],
    "status": status,
    "included": [{"path": f, "bytes": (work / f).stat().st_size} for f in included],
    "missing": missing,
    "notes": (["checkpoints.sqlite excluded (binary run state, not analysis data)"]
              if (art / "checkpoints.sqlite").exists() else []),
}
(work / "MANIFEST.json").write_text(json.dumps(manifest, indent=2))

print("")
print(f"Run: {name}")
print(f"Status: {status}")
print("Stages (completed LLM calls): "
      + (", ".join(f"{k}={v}" for k, v in sorted(stage_counts.items())) or "none logged"))
print("Models: " + (", ".join(f"{k} ({v} events)" for k, v in sorted(models.items())) or "none logged"))
bits = []
if wall is not None:
    bits.append(f"wall time (LLM log span): {fmt_wall(wall.total_seconds())}")
bits.append(f"tokens: {prompt_tok} in / {completion_tok} out")
bits.append(f"cost: ${cost:.4f}")
print("Usage: " + "  |  ".join(bits))
counts = [f"requirements={n_req}" if srs else None,
          f"specs={n_specs}" if n_specs is not None else None,
          f"tests={n_tests}" if n_tests is not None else None]
print("Artifacts: " + (", ".join(c for c in counts if c) or "no stage artifacts found"))
if errors:
    print(f"LLM errors logged: {len(errors)} (see llm-calls.jsonl)")
print(f"Included: {len(included)} file(s); missing: "
      + (", ".join(missing) if missing else "nothing expected"))
PY

tar -czf "$BUNDLE" -C "$STAGE_DIR" "$NAME"
SIZE="$(du -h "$BUNDLE" | cut -f1 | tr -d ' ')"
echo ""
echo "Bundle written: $BUNDLE ($SIZE)"
echo "Send this file: $BUNDLE"
