from pathlib import Path

def test_hands_free_driver_crosses_every_phase_and_invokes_oracle():
 s=(Path(__file__).parents[1]/"scripts/run-hands-free-e2e.sh").read_text()
 for phase in ("interview","spec","oracle"): assert f"phase={phase}" in s
 assert "--interviewee" in s and "--auto-approve" in s and "--expert-opinion" in s
 assert "python -m verification_loop" in s and "bundle-integrity.json" in s
 assert all(x in s for x in ('"interview"','"conops"','"needs"','"srs"','"architecture"','"items"','"tests"','"review"','"assembly"','"bundle-integrity"'))

def test_driver_absolutizes_persona_before_changing_repo():
 s=(Path(__file__).parents[1]/"scripts/run-hands-free-e2e.sh").read_text()
 absolute='PERSONA="$(cd "$(dirname "$PERSONA")" && pwd)/$(basename "$PERSONA")"'
 assert absolute in s
 assert s.index(absolute) < s.index('cd "$IE"')

def test_driver_shared_config_overrides_stale_inherited_interview_routes(tmp_path):
 import os, subprocess
 root=tmp_path/"require"
 for repo in ("interview-engine","spec-generator","verification-loop","vmodel-contracts"):
  (root/repo/"src").mkdir(parents=True)
 persona=root/"persona.json";persona.write_text('{"idea":"x","answers":[]}')
 (root/".env").write_text("\n".join([
  "INTERVIEW_ENGINE_MODEL_PROBING=deepseek:deepseek-flash",
  "INTERVIEW_ENGINE_MODEL_DISTILLATION=deepseek:deepseek-flash",
  "INTERVIEW_ENGINE_MODEL_PHRASING=deepseek:deepseek-flash",
  "INTERVIEW_ENGINE_MODEL_SCOPE_TIEBREAK=deepseek:deepseek-flash",
  "INTERVIEW_ENGINE_MODEL_EXPERT_OPINION=deepseek:deepseek-flash",
 ]))
 pkg=root/"interview-engine/src/interview_engine";pkg.mkdir()
 (pkg/"__init__.py").write_text("")
 (pkg/"cli.py").write_text('''import os,sys\nkeys=["PROBING","DISTILLATION","PHRASING","SCOPE_TIEBREAK","EXPERT_OPINION"]\nvals={k:os.environ.get("INTERVIEW_ENGINE_MODEL_"+k) for k in keys}\nconops=vals["DISTILLATION"]\nprint("Models: probing=%s, distillation=%s, conops=%s, phrasing=%s, scope_tiebreak=%s, expert_opinion=%s"%(vals["PROBING"],vals["DISTILLATION"],conops,vals["PHRASING"],vals["SCOPE_TIEBREAK"],vals["EXPERT_OPINION"]),file=sys.stderr)\nraise SystemExit(23)\n''')
 env=os.environ.copy(); env["PATH"]=str(Path(os.sys.executable).parent)+os.pathsep+env.get("PATH","");env.update({"REQUIRE_ROOT":str(root),"INTERVIEW_ENGINE_MODEL_PROBING":"ollama:phi4","INTERVIEW_ENGINE_MODEL_DISTILLATION":"ollama:phi4","INTERVIEW_ENGINE_MODEL_PHRASING":"ollama:phi4","INTERVIEW_ENGINE_MODEL_SCOPE_TIEBREAK":"ollama:phi4","INTERVIEW_ENGINE_MODEL_EXPERT_OPINION":"ollama:phi4"})
 run=subprocess.run(["bash",str(Path(__file__).parents[1]/"scripts/run-hands-free-e2e.sh"),"--persona",str(persona),"--greenfield"],env=env,text=True,capture_output=True)
 assert run.returncode==23
 line=next(x for x in run.stderr.splitlines() if x.startswith("Models:"))
 for stage in ("probing","distillation","conops","phrasing","scope_tiebreak","expert_opinion"):
  assert f"{stage}=deepseek:deepseek-flash" in line
 assert "ollama" not in line
