import datetime as dt
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

P = Path(__file__).parents[1] / "batch-specs.py"
S = importlib.util.spec_from_file_location("batch_specs", P)
batch = importlib.util.module_from_spec(S); S.loader.exec_module(batch)

class BatchSpecsTests(unittest.TestCase):
    def test_add_repeat_is_unique_and_stable(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d); intent = root / "intent.json"; manifest = root / "queue.json"
            intent.write_text(json.dumps({"session_id": "20260910-170000-ab12"}))
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
