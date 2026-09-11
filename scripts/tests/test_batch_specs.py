import datetime as dt
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

P = Path(__file__).parents[1] / "batch-specs.py"
S = importlib.util.spec_from_file_location("batch_specs", P)
batch = importlib.util.module_from_spec(S); S.loader.exec_module(batch)


try:
    import vmodel_contracts as _vc  # noqa: F401
    HAVE_CONTRACTS = True
except ImportError:  # bare interpreter (no project venv): contract-handoff tests skip
    HAVE_CONTRACTS = False

needs_contracts = unittest.skipUnless(HAVE_CONTRACTS, "vmodel-contracts not importable in this interpreter")


def make_intent(contract_version: str | None = None) -> dict:
    from vmodel_contracts import IntentModel
    intent = IntentModel(
        session_id="20260910-230000-ab12",
        problem_statement="teams rewrite specs from scratch",
        target_users=["founders"],
        core_value_proposition="a spec that survives contact with a build",
        stakeholder_needs=[{"need_id": "SN-1", "statement": "reuse the interview", "kind": "functional"}],
        in_scope=["batch queue"], out_of_scope=["mobile app"],
        source_turns={"problem_statement": [0], "stakeholder_needs": [0]},
    ).model_dump(mode="json")
    if contract_version is not None:
        intent["contract_version"] = contract_version
    return intent


def older_minor(testcase) -> str:
    from vmodel_contracts import CONTRACT_VERSION
    major, minor, _ = CONTRACT_VERSION.split(".")
    if int(minor) == 0:
        testcase.skipTest("cannot express an older minor for the installed contracts")
    return f"{major}.{int(minor) - 1}.0"

class BatchSpecsTests(unittest.TestCase):
    @needs_contracts
    def test_add_repeat_is_unique_and_stable(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); intent = root / "intent.json"; manifest = root / "queue.json"
            intent.write_text(json.dumps({**make_intent(), "session_id": "20260910-170000-ab12"}))
            runs = batch.add(manifest, intent, repeat=2, name="shop", now=dt.datetime(2026, 9, 10, 17, 1, 2))
            self.assertEqual([r["id"] for r in runs], ["shop-1", "shop-2"])
            self.assertEqual([r["artifacts"] for r in runs],
                             ["artifacts-2026-09-10_17-01-02", "artifacts-2026-09-10_17-01-03"])
            self.assertEqual([r["status"] for r in runs], ["queued", "queued"])

    def test_evaluator_finds_gaps_and_repeat_variance(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); sg = root / "spec-generator"; out = sg / "artifacts-2026-09-10_17-00-00"; out.mkdir(parents=True)
            (out / "needs.json").write_text(json.dumps({"needs": [{"need_id": "N-1"}]}))
            (out / "srs.json").write_text(json.dumps({"functional": [{"requirement_id": "R-1", "acceptance": [{"criterion_id": "AC-1"}]}], "non_functional": []}))
            (out / "items.json").write_text(json.dumps([{"spec_id": "SPEC-1", "requirement_ids": ["R-1"]}]))
            definition = {"preconditions": [], "steps": ["x"], "expected_outcomes": ["y"], "cleanup": [], "cases": [], "execution": {}}
            (out / "tests.json").write_text(json.dumps([{"test_id": "T-1", "criterion_id": "AC-1", "runner": "semantic", "definition": definition}]))
            (out / "traceability.json").write_text("[]")
            (out / "manifest.json").write_text("{}")
            run = {"id": "r", "session_id": "s", "status": "completed", "artifacts": out.name, "wall_seconds": 3600}
            result = batch.evaluate(run, root)
            self.assertEqual(result["counts"]["tests"], 1)
            self.assertTrue(result["test_definitions"]["canonical"])
            self.assertEqual(result["traceability"]["criteria_without_tests"], [])

    def test_run_logged_tees_stdout_and_stderr_to_durable_log(self):
        import contextlib
        import io
        import os
        import sys
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); log = root / "artifacts-x" / "run.log"
            buf = io.StringIO()
            command = [sys.executable, "-c", "import sys; print('visible out'); print('visible err', file=sys.stderr)"]
            with contextlib.redirect_stdout(buf):
                rc = batch._run_logged(command, root, dict(os.environ), log)
            self.assertEqual(rc, 0)
            self.assertIn("visible out", buf.getvalue())
            self.assertIn("visible err", buf.getvalue())
            self.assertIn("visible out", log.read_text())
            self.assertIn("visible err", log.read_text())


    def test_macos_spec_generator_child_uses_caffeinate(self):
        from unittest import mock
        command = ["python", "-m", "spec_generator.cli"]
        with mock.patch("vmodel_contracts.runtime.sys.platform", "darwin"), \
             mock.patch("vmodel_contracts.runtime.shutil.which", return_value="/usr/bin/caffeinate"):
            self.assertEqual(batch.keep_awake_command(command),
                             ["caffeinate", "-dims", *command])
        with mock.patch("vmodel_contracts.runtime.sys.platform", "linux"):
            self.assertEqual(batch.keep_awake_command(command), command)

    def test_estimate_scales_with_resumed_test_count(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); out = root / "spec-generator" / "artifacts-x"
            out.mkdir(parents=True)
            run = {"artifacts": "artifacts-x"}
            self.assertEqual(batch._estimate_hours(run, root),
                             (batch.HOURS_MIN, batch.HOURS_MAX))
            (out / "tests.json").write_text(json.dumps([{}] * 94))
            self.assertEqual(batch._estimate_hours(run, root),
                             (batch.HOURS_MIN * 2, batch.HOURS_MAX * 2))

    def test_pending_count_distinguishes_runnable_states(self):
        with tempfile.TemporaryDirectory() as d:
            manifest = Path(d) / "queue.json"
            batch._atomic_json(manifest, {"version": 1, "runs": [
                {"status": "queued"}, {"status": "running"},
                {"status": "failed"}, {"status": "completed"}]})
            data = batch._load(manifest)
            self.assertEqual(sum(r.get("status") in ("queued", "running") for r in data["runs"]), 2)

    def test_failed_run_requires_explicit_retry_and_keeps_directory(self):
        with tempfile.TemporaryDirectory() as d:
            manifest = Path(d) / "queue.json"
            batch._atomic_json(manifest, {"version": 1, "runs": [{"id": "x", "status": "failed", "artifacts": "artifacts-fixed"}]})
            run = batch.retry(manifest, "x")
            self.assertEqual(run["status"], "queued")
            self.assertEqual(run["artifacts"], "artifacts-fixed")

if __name__ == "__main__": unittest.main()

@needs_contracts
class ContractHandoffTests(unittest.TestCase):
    """Self-healing contract handoff (0.9.0 intent vs 0.10.x spec-generator):
    compatible payloads migrate with an audit trail, drift refuses untouched,
    and the queue never starts while repo pins disagree."""

    def test_older_compatible_intent_migrates_with_audit_line(self):
        import contextlib
        import io
        from vmodel_contracts import CONTRACT_VERSION
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); intent = root / "intent.json"; manifest = root / "queue.json"
            older = older_minor(self)
            intent.write_text(json.dumps(make_intent(older)))
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                runs = batch.add(manifest, intent)
            self.assertIn(f"{older} -> {CONTRACT_VERSION}", buf.getvalue())
            after = json.loads(intent.read_text())
            self.assertEqual(after["contract_version"], CONTRACT_VERSION)
            migrations = runs[0]["contract_migrations"]
            self.assertEqual([(m["from"], m["to"], m["when"]) for m in migrations],
                             [(older, CONTRACT_VERSION, "add")])
            stored = batch._load(manifest)["runs"][0]
            self.assertEqual(stored["contract_migrations"][0]["from"], older)

    def test_incompatible_intent_refuses_without_mutation(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); intent = root / "intent.json"; manifest = root / "queue.json"
            payload = make_intent(older_minor(self))
            del payload["problem_statement"]  # real schema drift, not just an old stamp
            intent.write_text(json.dumps(payload))
            before = intent.read_bytes()
            with self.assertRaises(ValueError) as ctx:
                batch.add(manifest, intent)
            self.assertIn("not compatible", str(ctx.exception))
            self.assertEqual(intent.read_bytes(), before)  # never silently re-stamped
            self.assertFalse(manifest.exists())            # nothing queued

    def test_preflight_names_the_repo_behind_a_contract_release(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            pin = ('[project]\ndependencies = [\n  "vmodel-contracts @ git+https://github.com/'
                   'ShyAlon/vmodel-contracts.git@%s",\n]\n')
            for name, tag in (("interview-engine", "v0.8.0"), ("spec-generator", "v0.10.0")):
                repo = root / name; repo.mkdir()
                (repo / "pyproject.toml").write_text(pin % tag)
            with self.assertRaises(ValueError) as ctx:
                batch.preflight_repo_consistency(root)
            message = str(ctx.exception)
            self.assertIn("interview-engine", message)
            self.assertIn("v0.8.0", message)
            self.assertIn("git pull", message)
            self.assertNotIn("spec-generator is behind", message)
            # agreeing pins pass
            (root / "interview-engine" / "pyproject.toml").write_text(pin % "v0.10.0")
            batch.preflight_repo_consistency(root)

    def test_run_queue_stops_before_starting_on_pin_mismatch(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            pin = ('[project]\ndependencies = [\n  "vmodel-contracts @ git+https://github.com/'
                   'ShyAlon/vmodel-contracts.git@%s",\n]\n')
            for name, tag in (("interview-engine", "v0.9.0"), ("spec-generator", "v0.10.0")):
                repo = root / name; repo.mkdir()
                (repo / "pyproject.toml").write_text(pin % tag)
            manifest = root / "queue.json"
            batch._atomic_json(manifest, {"version": 1, "runs": [{"id": "x", "status": "queued",
                                                                  "artifacts": "a", "intent_model": "i.json"}]})
            with self.assertRaises(ValueError) as ctx:
                batch.run_queue(manifest, root)
            self.assertIn("interview-engine", str(ctx.exception))
            self.assertEqual(batch._load(manifest)["runs"][0]["status"], "queued")  # untouched


