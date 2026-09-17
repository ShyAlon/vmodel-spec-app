#!/usr/bin/env bash
# run-full-flow.sh - interview to spec bundle in one command.
#
#   scripts/run-full-flow.sh "a marketplace for surf lessons in Tel Aviv" --greenfield
#   scripts/run-full-flow.sh "improve the spec pipeline" --baseline vmodel-spec-app/system-baseline.json
#   scripts/run-full-flow.sh --session <id> --greenfield     # resume an interrupted interview/spec run
#   scripts/run-full-flow.sh --session <id> --greenfield --fresh-spec  # keep approved interview; new spec generation
#
# Runs the interview (interactive: Q&A + the approve gate), captures the
# session id it prints, then runs spec-generator against that session's
# intent_model.json with the review gates. The baseline is an EXPLICIT choice
# (--greenfield for a new product, --baseline <path> for an existing system) -
# a silent default would anchor a new product to the wrong system's
# architecture (2026-09-12 review).
set -euo pipefail

usage() { echo "usage: $0 (\"<product idea>\" | --session <id>) (--greenfield | --baseline <path>) [--new-session] [--fresh-spec] [--expert-opinion] [--test-architecture]" >&2; exit 1; }
[ $# -ge 1 ] || usage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
ARTIFACTS_ROOT="${VMODEL_ARTIFACTS_DIR:-$REQUIRE_ROOT/artifacts}"
export VMODEL_ARTIFACTS_DIR="$ARTIFACTS_ROOT"
IE="$REQUIRE_ROOT/interview-engine"
SG="$REQUIRE_ROOT/spec-generator"
[ -d "$IE" ] || { echo "error: interview-engine not found at $IE" >&2; exit 1; }
[ -d "$SG" ] || { echo "error: spec-generator not found at $SG" >&2; exit 1; }

SESSION=""
IDEA_ARGS=()
BASELINE=""
GREENFIELD=0
FRESH_SPEC=0
EXPERT_OPINION=0
TEST_ARCHITECTURE=0
NEW_SESSION=0
while [ $# -gt 0 ]; do
  case "$1" in
    --session|-s) SESSION="${2:?--session needs an id}"; shift 2 ;;
    --greenfield) GREENFIELD=1; shift ;;
    --baseline)   BASELINE="${2:?--baseline needs a path}"; shift 2 ;;
    --fresh-spec) FRESH_SPEC=1; shift ;;
    --expert-opinion) EXPERT_OPINION=1; shift ;;
    --test-architecture) TEST_ARCHITECTURE=1; FRESH_SPEC=1; shift ;;
    --new-session) NEW_SESSION=1; shift ;;
    -*)           usage ;;
    *)            IDEA_ARGS+=("$1"); shift ;;
  esac
done
[ "$GREENFIELD" -eq 1 ] && [ -n "$BASELINE" ] && usage
[ "$GREENFIELD" -eq 0 ] && [ -z "$BASELINE" ] && {
  echo "error: choose the architecture anchor explicitly:" >&2
  echo "  --greenfield        a brand-new product (no existing system)" >&2
  echo "  --baseline <path>   an existing system's checked baseline" >&2
  exit 1
}
if [ -z "$SESSION" ] && [ ${#IDEA_ARGS[@]} -eq 0 ]; then usage; fi

# A product string normally means "start". Refuse that destructive-looking
# ambiguity when the exact same idea already has meaningful unfinished work.
# --new-session is the explicit escape hatch for a deliberate second run.
if [ -z "$SESSION" ] && [ "$NEW_SESSION" -eq 0 ]; then
  IDEA_TEXT="${IDEA_ARGS[*]}"
  MATCH="$({ IDEA_TEXT="$IDEA_TEXT" ARTIFACTS_ROOT="$ARTIFACTS_ROOT" python3 - <<'PYGUARD'
import json, os, re, sqlite3
from pathlib import Path
root=Path(os.environ["ARTIFACTS_ROOT"]); idea=os.environ["IDEA_TEXT"]
for d in sorted(root.glob("*"), reverse=True):
    interview=d/"interview"; db=interview/"checkpoints.sqlite"; log=interview/"run.log"
    if not db.exists(): continue
    # An abandoned shell created at turn 1 must not shadow a real resumable run.
    text=log.read_text(errors="ignore") if log.exists() else ""
    if not re.search(r"^You:\s*\S", text, re.MULTILINE): continue
    # A fully assembled default spec is complete, not in progress.
    if (d/"spec"/"manifest.json").exists(): continue
    found=False
    try:
        con=sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        for table in ("checkpoints", "writes"):
            try: rows=con.execute(f'SELECT * FROM "{table}"')
            except sqlite3.Error: continue
            for row in rows:
                if any(idea.encode() in bytes(v) for v in row if isinstance(v,(bytes,bytearray))):
                    found=True; break
                if any(idea == v for v in row if isinstance(v,str)):
                    found=True; break
                if found: break
            if found: break
    except sqlite3.Error: pass
    if not found:
        # New launcher runs leave an exact-match sidecar, avoiding knowledge of
        # checkpoint serialization. This does not weaken legacy checkpoint scan.
        side=interview/"launcher-idea.json"
        try: found=json.loads(side.read_text()).get("idea") == idea
        except Exception: pass
    if found:
        print(d.name); break
PYGUARD
  } 2>/dev/null || true)"
  if [ -n "$MATCH" ]; then
    echo "error: this exact product already has an in-progress session: $MATCH" >&2
    echo "Resume it with:" >&2
    if [ "$GREENFIELD" -eq 1 ]; then
      if [ "$EXPERT_OPINION" -eq 1 ]; then
        echo "  $0 --session $MATCH --greenfield --expert-opinion" >&2
      else
        echo "  $0 --session $MATCH --greenfield" >&2
      fi
    else
      if [ "$EXPERT_OPINION" -eq 1 ]; then
        echo "  $0 --session $MATCH --baseline $BASELINE --expert-opinion" >&2
      else
        echo "  $0 --session $MATCH --baseline $BASELINE" >&2
      fi
    fi
    echo "To deliberately start a second run of the same product, add --new-session." >&2
    exit 2
  fi
fi
[ "$FRESH_SPEC" -eq 1 ] && [ -z "$SESSION" ] && { echo "error: --fresh-spec requires --session <approved-session-id>" >&2; exit 1; }
if [ -n "$SESSION" ]; then
  set -- --session "$SESSION"          # resume form for the interview leg
else
  set -- ${IDEA_ARGS[@]+"${IDEA_ARGS[@]}"}
fi
[ "$EXPERT_OPINION" -eq 1 ] && set -- "$@" --expert-opinion

# 1. INTERVIEW. The app mirrors stderr to a plain run.log while preserving
# terminal TTY/color and interactive approval prompts. Capture the session via
# the newly created artifacts directory, not by piping through tee.
BEFORE="$(mktemp "${TMPDIR:-/tmp}/vmodel-interview-before.XXXXXX")"
find "$ARTIFACTS_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort > "$BEFORE" || true
echo "== interview (plain log is printed by the app) =="
cd "$IE"
python -m interview_engine.cli "$@"

if [ -z "$SESSION" ]; then
  SESSION="$(comm -13 "$BEFORE" <(find "$ARTIFACTS_ROOT" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort) | tail -1 | xargs basename 2>/dev/null || true)"
fi
rm -f "$BEFORE"
if [ ${#IDEA_ARGS[@]} -gt 0 ] && [ -n "$SESSION" ]; then
  mkdir -p "$ARTIFACTS_ROOT/$SESSION/interview"
  IDEA_TEXT="${IDEA_ARGS[*]}" python3 - "$ARTIFACTS_ROOT/$SESSION/interview/launcher-idea.json" <<'PYIDEA'
import json, os, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({"idea": os.environ["IDEA_TEXT"]}, indent=2))
PYIDEA
fi
# Compatibility for older interview-engine layouts and script test shims.
if [ -z "$SESSION" ]; then
  SESSION="$(ls -t "$IE/out" 2>/dev/null | head -1 || true)"
fi
[ -n "$SESSION" ] || { echo "error: no session id or new interview artifacts found" >&2; exit 1; }

INTENT="$ARTIFACTS_ROOT/$SESSION/interview/intent_model.json"
CONOPS="$ARTIFACTS_ROOT/$SESSION/interview/conops.json"
if [ ! -f "$INTENT" ] && [ -f "$IE/out/$SESSION/intent_model.json" ]; then
  INTENT="$IE/out/$SESSION/intent_model.json"
  CONOPS="$IE/out/$SESSION/conops.json"
fi
if [ ! -f "$INTENT" ] || [ ! -f "$CONOPS" ]; then
  echo "Interview for session $SESSION ended without an approved Intent Model and Concept of Operations -" >&2
  echo "nothing was generated. Resume it with: $0 --session $SESSION" >&2
  exit 1
fi

# 2. SPEC GENERATION. Not piped: the --review gates (accept/edit/feedback/
# reject) read from the terminal.
echo
echo "== spec generation for session $SESSION (review gates on) =="
if [ "$GREENFIELD" -eq 1 ]; then
  TEMPLATE="$SG/examples/system-baseline.greenfield.json"
  [ -f "$TEMPLATE" ] || { echo "error: greenfield template not found at $TEMPLATE" >&2; exit 1; }
  INTERVIEW_DIR="$(dirname "$INTENT")"
  BASELINE="$INTERVIEW_DIR/greenfield-baseline.json"
  SESSION="$SESSION" python3 - "$TEMPLATE" "$BASELINE" <<'PY'
import json, os, sys
template, out = sys.argv[1], sys.argv[2]
d = json.load(open(template))
d["baseline_id"] = f"greenfield-{os.environ['SESSION']}"
d["system_name"] = f"Greenfield product (interview session {os.environ['SESSION']})"
json.dump(d, open(out, "w"), indent=2)
PY
fi
[ -f "$BASELINE" ] || { echo "error: system baseline not found at $BASELINE" >&2; exit 1; }
echo "== baseline: $BASELINE =="
cd "$SG"
SPEC_OUT_ARGS=()
EXPERT_ARGS=()
[ "$EXPERT_OPINION" -eq 1 ] && EXPERT_ARGS=(--expert-opinion)
if [ "$FRESH_SPEC" -eq 1 ]; then
  # A fresh spec generation must not collide with the session's stable default
  # checkpoint. Keep the approved interview artifacts immutable; create a stable,
  # explicit generation directory beside the prior attempt. Repeating the
  # command resumes this fresh generation after interruption.
  if [ "$TEST_ARCHITECTURE" -eq 1 ]; then
    SPEC_OUT="$ARTIFACTS_ROOT/$SESSION/spec-identity-test"
  else
    SPEC_OUT="$ARTIFACTS_ROOT/$SESSION/spec-fresh"
  fi
  SPEC_OUT_ARGS=(-o "$SPEC_OUT")
  if [ -e "$SPEC_OUT/checkpoints.sqlite" ]; then
    echo "== resuming fresh spec generation: $SPEC_OUT =="
  else
    echo "== fresh spec generation: $SPEC_OUT =="
  fi
fi
echo "== preflight (zero model calls) =="
python -m spec_generator.cli "$INTENT" --conops "$CONOPS" --system-baseline "$BASELINE" --review ${EXPERT_ARGS[@]+"${EXPERT_ARGS[@]}"} --preflight ${SPEC_OUT_ARGS[@]+"${SPEC_OUT_ARGS[@]}"}
TO_ARGS=()
[ "$TEST_ARCHITECTURE" -eq 1 ] && TO_ARGS=(--to architecture)
python -m spec_generator.cli "$INTENT" --conops "$CONOPS" --system-baseline "$BASELINE" --review ${EXPERT_ARGS[@]+"${EXPERT_ARGS[@]}"} ${TO_ARGS[@]+"${TO_ARGS[@]}"} ${SPEC_OUT_ARGS[@]+"${SPEC_OUT_ARGS[@]}"}

ARTIFACT_PATH="$ARTIFACTS_ROOT/$SESSION/spec"
if [ "$FRESH_SPEC" -eq 1 ]; then ARTIFACT_PATH="$SPEC_OUT"; fi

echo
echo "Done. Artifacts: $ARTIFACT_PATH/  (AGENTS.md, srs.md, needs.md, architecture.md, specs/, traceability.json)"
echo "Redo one stage under newer code: python -m spec_generator.cli $INTENT --conops $CONOPS --system-baseline $BASELINE --from <stage>"
