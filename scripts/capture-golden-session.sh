#!/usr/bin/env bash
# Capture a sanitized, deterministic evidence archive for one completed session.
set -euo pipefail
usage(){ echo "usage: $0 SESSION_ID [OUTPUT.tar.gz]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
SESSION="$1"; [[ "$SESSION" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Error: invalid session id." >&2; exit 2; }
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${REQUIRE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SOURCE="${VMODEL_ARTIFACTS_DIR:-$ROOT/artifacts}/$SESSION"
[ -d "$SOURCE" ] || { echo "Error: session not found: $SOURCE" >&2; echo "Likely cause: the session id or artifacts root is wrong." >&2; echo "Next: pass the completed session id and retry." >&2; exit 2; }
OUT="${2:-$PWD/golden-session-$SESSION.tar.gz}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
DEST="$WORK/golden-session-$SESSION"; mkdir -p "$DEST/interview" "$DEST/spec"
# Explicit allowlist: no checkpoints, databases, HTTP payloads, environment, or credentials.
INTERVIEW_FILES=(intent_model.json conops.json audit.jsonl usage.jsonl run.log)
SPEC_FILES=(needs.json srs.json architecture.json items.json tests.json review.json manifest.json traceability.json bundle-integrity.json hands-free-run.json audit.jsonl usage.jsonl run.log)
copy_allowed(){ local area="$1"; shift; local name; for name in "$@"; do if [ -f "$SOURCE/$area/$name" ]; then cp "$SOURCE/$area/$name" "$DEST/$area/$name"; fi; done; }
copy_allowed interview "${INTERVIEW_FILES[@]}"
copy_allowed spec "${SPEC_FILES[@]}"
# Preserve delivered markdown/spec files, but no hidden/debug/checkpoint trees.
if [ -d "$SOURCE/spec/specs" ]; then mkdir -p "$DEST/spec/specs"; find "$SOURCE/spec/specs" -maxdepth 1 -type f \( -name '*.json' -o -name '*.md' \) -exec cp {} "$DEST/spec/specs/" \;; fi
python3 - "$DEST" "$SESSION" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);session=sys.argv[2]
files=[]
for p in sorted(x for x in root.rglob('*') if x.is_file()):
 b=p.read_bytes();files.append({'path':p.relative_to(root).as_posix(),'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
manifest={'format':'vmodel-golden-capture-v1','session_id':session,'sanitization':{
 'allowlist_only':True,'excluded':['*.sqlite','checkpoints/**','debug-http.jsonl','.env','provider request payloads'],
 'accepted_live_call_bodies':'unavailable unless separately captured during the original run; none are reconstructed'},
 'files':files}
(root/'capture-manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
PY
mkdir -p "$(dirname "$OUT")"
# Stable order, ownership and timestamps make repeated captures byte-identical.
COPYFILE_DISABLE=1 tar --sort=name --owner=0 --group=0 --numeric-owner --mtime='UTC 1970-01-01' -czf "$OUT" -C "$WORK" "$(basename "$DEST")"
echo "Golden session capture: $OUT"
echo "Source: $SOURCE"
echo "Manifest: capture-manifest.json (SHA-256 per included file)"
