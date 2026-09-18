from pathlib import Path

def test_hands_free_driver_crosses_every_phase_and_invokes_oracle():
 s=(Path(__file__).parents[1]/"scripts/run-hands-free-e2e.sh").read_text()
 for phase in ("interview","spec","oracle"): assert f"phase={phase}" in s
 assert "--interviewee" in s and "--auto-approve" in s and "--expert-opinion" in s
 assert "python -m verification_loop" in s and "bundle-integrity.json" in s
 assert all(x in s for x in ('"interview"','"conops"','"needs"','"srs"','"architecture"','"items"','"tests"','"review"','"assembly"','"bundle-integrity"'))
