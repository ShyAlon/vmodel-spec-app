import hashlib,json,os,subprocess,tarfile
from pathlib import Path

SCRIPT=Path(__file__).parents[1]/"scripts/capture-golden-session.sh"
def test_capture_is_allowlisted_hashed_and_reproducible(tmp_path):
 root=tmp_path/"require"; session="20260918-test"; src=root/"artifacts"/session
 (src/"interview").mkdir(parents=True);(src/"spec/specs").mkdir(parents=True)
 (src/"interview/intent_model.json").write_text('{"session_id":"20260918-test"}')
 (src/"interview/checkpoints.sqlite").write_bytes(b"secret")
 (src/"spec/usage.jsonl").write_text('{"stage":"srs"}\n')
 (src/"spec/bundle-integrity.json").write_text('{"diagnostics":[]}')
 (src/"spec/specs/SPEC-1.md").write_text('# spec')
 (src/"spec/debug-http.jsonl").write_text('private payload')
 env={**os.environ,"REQUIRE_ROOT":str(root)};a=tmp_path/"a.tar.gz";b=tmp_path/"b.tar.gz"
 for out in (a,b): subprocess.run([str(SCRIPT),session,str(out)],env=env,check=True,capture_output=True,text=True)
 assert hashlib.sha256(a.read_bytes()).digest()==hashlib.sha256(b.read_bytes()).digest()
 with tarfile.open(a) as tf:
  names=tf.getnames();base=f"golden-session-{session}"
  assert f"{base}/interview/intent_model.json" in names and f"{base}/spec/specs/SPEC-1.md" in names
  assert not any("sqlite" in n or "debug-http" in n for n in names)
  manifest=json.load(tf.extractfile(f"{base}/capture-manifest.json"))
 assert manifest["session_id"]==session and len(manifest["files"])==4
 assert "none are reconstructed" in manifest["sanitization"]["accepted_live_call_bodies"]
