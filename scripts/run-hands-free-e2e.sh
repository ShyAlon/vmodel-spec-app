#!/usr/bin/env bash
# Persona -> interview/CONOPS -> full reviewed bundle -> independent integrity report.
set -euo pipefail
usage(){ echo "usage: $0 --persona FILE (--greenfield | --baseline FILE) [--interviewee-mode scripted|llm] [--session ID]" >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; REQUIRE_ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
ARTIFACTS_ROOT="${VMODEL_ARTIFACTS_DIR:-$REQUIRE_ROOT/artifacts}"; export VMODEL_ARTIFACTS_DIR="$ARTIFACTS_ROOT"
PERSONA=""; BASELINE=""; GREENFIELD=0; MODE=scripted; SESSION=""
while [ $# -gt 0 ]; do case "$1" in
 --persona) PERSONA="${2:?}";shift 2;; --greenfield) GREENFIELD=1;shift;; --baseline) BASELINE="${2:?}";shift 2;;
 --interviewee-mode) MODE="${2:?}";shift 2;; --session) SESSION="${2:?}";shift 2;; *) usage;; esac; done
[ -f "$PERSONA" ] || usage; [ "$GREENFIELD" -eq 1 ] && [ -n "$BASELINE" ] && usage
[ "$GREENFIELD" -eq 0 ] && [ -z "$BASELINE" ] && usage
IE="$REQUIRE_ROOT/interview-engine"; SG="$REQUIRE_ROOT/spec-generator"; VL="$REQUIRE_ROOT/verification-loop"
for d in "$IE" "$SG" "$VL"; do [ -d "$d" ] || { echo "Error: required repository missing: $d" >&2; exit 2; }; done
mkdir -p "$ARTIFACTS_ROOT"; BEFORE="$(mktemp)"; trap 'rm -f "$BEFORE"' EXIT
find "$ARTIFACTS_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort > "$BEFORE" 2>/dev/null || true
printf 'boundary=hands-free-pipeline phase=interview mode=%s persona=%s decision=start\n' "$MODE" "$PERSONA"
cd "$IE"; export PYTHONPATH="$REQUIRE_ROOT/vmodel-contracts/src:$IE/src:$SG/src:$VL/src${PYTHONPATH:+:$PYTHONPATH}"
IA=(--interviewee "$PERSONA" --interviewee-mode "$MODE" --auto-approve --expert-opinion)
if [ -n "$SESSION" ]; then python -m interview_engine.cli --session "$SESSION" "${IA[@]}"; else python -m interview_engine.cli "${IA[@]}"; fi
if [ -z "$SESSION" ]; then SESSION="$(comm -13 "$BEFORE" <(find "$ARTIFACTS_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort) | tail -1 | xargs basename)"; fi
[ -n "$SESSION" ] || { echo 'Error: interview produced no session.' >&2; exit 2; }
INT="$ARTIFACTS_ROOT/$SESSION/interview/intent_model.json"; CON="$ARTIFACTS_ROOT/$SESSION/interview/conops.json"; OUT="$ARTIFACTS_ROOT/$SESSION/spec"
[ -f "$INT" ] && [ -f "$CON" ] || { echo "Error: interview did not produce intent_model.json and conops.json for $SESSION" >&2; exit 2; }
if [ "$GREENFIELD" -eq 1 ]; then BASELINE="$ARTIFACTS_ROOT/$SESSION/interview/greenfield-baseline.json"; python - "$SG/examples/system-baseline.greenfield.json" "$BASELINE" "$SESSION" <<'PY'
import json,sys
x=json.load(open(sys.argv[1]));x["baseline_id"]="greenfield-"+sys.argv[3];x["system_name"]="Hands-free E2E "+sys.argv[3];json.dump(x,open(sys.argv[2],"w"),indent=2)
PY
fi
printf 'boundary=hands-free-pipeline phase=spec session=%s decision=start\n' "$SESSION"
cd "$SG"; python -m spec_generator.cli "$INT" --conops "$CON" --system-baseline "$BASELINE" -o "$OUT" --review --expert-opinion --auto-approve
printf 'boundary=hands-free-pipeline phase=oracle session=%s decision=start\n' "$SESSION"
cd "$VL"; PYTHONPATH="$REQUIRE_ROOT/vmodel-contracts/src:$VL/src" python -m verification_loop "$OUT" --out "$OUT/bundle-integrity.json"
python - "$OUT/bundle-integrity.json" "$OUT/hands-free-run.json" "$SESSION" "$MODE" "$PERSONA" <<'PY'
import json,sys,datetime
integrity=json.load(open(sys.argv[1]));json.dump({"session_id":sys.argv[3],"mode":sys.argv[4],"persona":sys.argv[5],"completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"phases":["interview","conops","needs","srs","architecture","items","tests","review","assembly","bundle-integrity"],"integrity":integrity},open(sys.argv[2],"w"),indent=2)
PY
printf 'boundary=hands-free-pipeline session=%s phases=10 files=%s diagnostics=0 decision=complete artifact=%s\n' "$SESSION" "$(python -c 'import json,sys;print(json.load(open(sys.argv[1]))["files_checked"])' "$OUT/bundle-integrity.json")" "$OUT/hands-free-run.json"
