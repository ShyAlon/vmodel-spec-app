#!/usr/bin/env python3
"""Queue completed interviews for sequential spec generation and comparison.

The founder still conducts and approves each interview. This harness takes over
at intent_model.json, runs spec-generator one job at a time, resumes interrupted
jobs in place, and writes deterministic batch reports.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

VERSION = 1
HOURS_MIN = 2.5
HOURS_MAX = 3.0


def _atomic_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, path)


def _load(path: Path) -> dict:
    if not path.exists():
        return {"version": VERSION, "runs": []}
    data = json.loads(path.read_text())
    if data.get("version") != VERSION or not isinstance(data.get("runs"), list):
        raise ValueError(f"{path}: expected batch manifest version {VERSION} with a runs list")
    return data


def _root() -> Path:
    # .../require/vmodel-spec-app/scripts/batch-specs.py -> .../require
    return Path(__file__).resolve().parents[2]


def _unique_stamp(data: dict, now: dt.datetime | None = None) -> str:
    candidate = (now or dt.datetime.now()).replace(microsecond=0)
    used = {r.get("artifacts") for r in data["runs"]}
    while True:
        stamp = f"artifacts-{candidate:%Y-%m-%d_%H-%M-%S}"
        if stamp not in used:
            return stamp
        candidate += dt.timedelta(seconds=1)


def add(manifest: Path, intent_path: Path, repeat: int = 1, name: str | None = None,
        now: dt.datetime | None = None) -> list[dict]:
    if repeat < 1:
        raise ValueError("--repeat must be at least 1")
    intent_path = intent_path.expanduser().resolve()
    if not intent_path.is_file():
        raise ValueError(f"intent model not found: {intent_path}")
    payload = json.loads(intent_path.read_text())
    session = payload.get("session_id")
    if not isinstance(session, str) or not session:
        raise ValueError(f"{intent_path}: not an intent model (session_id missing)")
    data = _load(manifest)
    added = []
    base = name or session
    clock = now
    for index in range(1, repeat + 1):
        artifacts = _unique_stamp(data, clock)
        run = {
            "id": f"{base}-{index}" if repeat > 1 else base,
            "session_id": session,
            "intent_model": str(intent_path),
            "artifacts": artifacts,
            "status": "queued",
            "attempts": 0,
        }
        if any(old.get("id") == run["id"] for old in data["runs"]):
            raise ValueError(f"run id already queued: {run['id']} (use --name to distinguish it)")
        data["runs"].append(run)
        added.append(run)
        if clock is not None:
            clock += dt.timedelta(seconds=1)
    _atomic_json(manifest, data)
    return added


def _json_file(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return default


def _text_hash(value) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()[:16]


def evaluate(run: dict, require_root: Path) -> dict:
    out = require_root / "spec-generator" / run["artifacts"]
    needs = _json_file(out / "needs.json", {})
    srs = _json_file(out / "srs.json", {})
    items = _json_file(out / "items.json", [])
    tests = _json_file(out / "tests.json", [])
    trace = _json_file(out / "traceability.json", {})
    manifest = _json_file(out / "manifest.json", {})
    functional = srs.get("functional") or []
    non_functional = srs.get("non_functional") or []
    requirements = functional + non_functional
    criteria = [c for r in requirements for c in (r.get("acceptance") or [])]
    req_ids = {r.get("requirement_id") for r in requirements}
    covered_req_ids = {rid for item in items for rid in (item.get("requirement_ids") or [])}
    criterion_ids = {c.get("criterion_id") for c in criteria}
    tested_criteria = {t.get("criterion_id") for t in tests if t.get("criterion_id")}
    canonical = {"preconditions", "steps", "expected_outcomes", "cleanup", "cases", "execution"}
    bad_definitions = [t.get("test_id") for t in tests
                       if not isinstance(t.get("definition"), dict)
                       or set(t["definition"]) != canonical]
    usage = []
    for line in (out / "usage.jsonl").read_text().splitlines() if (out / "usage.jsonl").exists() else []:
        try:
            usage.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    calls = []
    llm_path = out / "llm-calls.jsonl"
    for line in llm_path.read_text().splitlines() if llm_path.exists() else []:
        try:
            calls.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    ends = [e for e in calls if e.get("event") == "llm_call_end"]
    return {
        "id": run["id"], "session_id": run["session_id"], "status": run["status"],
        "artifacts": str(out), "wall_seconds": run.get("wall_seconds"),
        "counts": {"needs": len(needs.get("needs") or []), "requirements": len(requirements),
                   "acceptance_criteria": len(criteria), "specs": len(items), "tests": len(tests)},
        "traceability": {"requirements_without_specs": sorted(req_ids - covered_req_ids),
                         "criteria_without_tests": sorted(criterion_ids - tested_criteria),
                         "entries": len(trace) if isinstance(trace, (dict, list)) else 0},
        "test_definitions": {"canonical": len(bad_definitions) == 0, "invalid_test_ids": bad_definitions,
                             "runners": dict(sorted(Counter(t.get("runner", "") for t in tests).items()))},
        "usage": {"calls": len(usage), "prompt_tokens": sum(int(u.get("prompt_tokens", 0) or 0) for u in usage),
                  "completion_tokens": sum(int(u.get("completion_tokens", 0) or 0) for u in usage),
                  "cost_usd": round(sum(float(u.get("cost_usd", 0) or 0) for u in usage), 6)},
        "llm_timing": {"completed_calls": len(ends),
                       "latency_seconds": round(sum(float(e.get("latency_s", 0) or 0) for e in ends), 3),
                       "ttft_seconds": round(sum(float(e.get("ttft_s", 0) or 0) for e in ends), 3)},
        "hashes": {"srs": _text_hash(srs), "items": _text_hash(items), "tests": _text_hash(tests)},
        "bundle_manifest_present": bool(manifest),
    }


def write_report(manifest_path: Path, data: dict, require_root: Path) -> dict:
    summaries = [evaluate(r, require_root) for r in data["runs"] if r.get("status") == "completed"]
    groups = {}
    for s in summaries:
        groups.setdefault(s["session_id"], []).append(s)
    variance = []
    for session, runs in groups.items():
        if len(runs) > 1:
            variance.append({"session_id": session, "runs": [r["id"] for r in runs],
                             "distinct_srs": len({r["hashes"]["srs"] for r in runs}),
                             "distinct_items": len({r["hashes"]["items"] for r in runs}),
                             "distinct_tests": len({r["hashes"]["tests"] for r in runs}),
                             "count_vectors": [r["counts"] for r in runs]})
    report = {"version": VERSION, "generated_at": dt.datetime.now().isoformat(timespec="seconds"),
              "runs": summaries, "variance_by_session": variance}
    json_path = manifest_path.with_name("batch-report.json")
    md_path = manifest_path.with_name("batch-report.md")
    _atomic_json(json_path, report)
    lines = ["# Batch spec report", "", "| Run | Status | Needs | Reqs | ACs | Specs | Tests | Time | Canonical |",
             "|---|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for s in summaries:
        c = s["counts"]; sec = s.get("wall_seconds")
        elapsed = f"{sec/3600:.2f}h" if isinstance(sec, (int, float)) else "n/a"
        lines.append(f"| {s['id']} | {s['status']} | {c['needs']} | {c['requirements']} | "
                     f"{c['acceptance_criteria']} | {c['specs']} | {c['tests']} | {elapsed} | "
                     f"{'yes' if s['test_definitions']['canonical'] else 'NO'} |")
    lines += ["", "## Traceability gaps", ""]
    for s in summaries:
        tr = s["traceability"]
        lines.append(f"- **{s['id']}**: requirements without specs: {tr['requirements_without_specs'] or 'none'}; "
                     f"criteria without tests: {tr['criteria_without_tests'] or 'none'}")
    if variance:
        lines += ["", "## Repeat variance", ""]
        for v in variance:
            lines.append(f"- **{v['session_id']}** ({', '.join(v['runs'])}): distinct hashes - "
                         f"SRS {v['distinct_srs']}, items {v['distinct_items']}, tests {v['distinct_tests']}")
    md_path.write_text("\n".join(lines) + "\n")
    return report


def retry(manifest: Path, run_id: str) -> dict:
    data = _load(manifest)
    run = next((r for r in data["runs"] if r.get("id") == run_id), None)
    if run is None:
        raise ValueError(f"run id not found: {run_id}")
    if run.get("status") != "failed":
        raise ValueError(f"{run_id}: status is {run.get('status')}, not failed")
    run["status"] = "queued"
    _atomic_json(manifest, data)
    return run


def run_queue(manifest: Path, require_root: Path, limit: int | None = None) -> int:
    data = _load(manifest)
    # A prior SIGINT/SIGTERM leaves the manifest at `running`; that is pending
    # and resumes in its recorded directory. A real nonzero exit is `failed`
    # and stops the queue for diagnosis; retry it explicitly with `retry`.
    pending = [r for r in data["runs"] if r.get("status") in ("queued", "running")]
    if limit is not None:
        pending = pending[:limit]
    print(f"Queued: {len(pending)} sequential run(s); estimated {len(pending)*HOURS_MIN:.1f}-{len(pending)*HOURS_MAX:.1f} hours total.")
    sg = require_root / "spec-generator"
    failures = 0
    for pos, run in enumerate(pending, 1):
        out = sg / run["artifacts"]
        run.update(status="running", attempts=int(run.get("attempts", 0)) + 1,
                   started_at=run.get("started_at") or dt.datetime.now().isoformat(timespec="seconds"))
        _atomic_json(manifest, data)
        print(f"[{pos}/{len(pending)}] {run['id']} -> {out} (estimate {HOURS_MIN}-{HOURS_MAX}h)", flush=True)
        env = dict(os.environ, VMODEL_LLM_LOG=str(out / "llm-calls.jsonl"))
        started = time.monotonic()
        rc = subprocess.run([sys.executable, "-m", "spec_generator.cli", run["intent_model"],
                             "-o", run["artifacts"]], cwd=sg, env=env).returncode
        run["wall_seconds"] = round(float(run.get("wall_seconds", 0)) + time.monotonic() - started, 3)
        run["status"] = "completed" if rc == 0 else "failed"
        run["finished_at"] = dt.datetime.now().isoformat(timespec="seconds")
        run["exit_code"] = rc
        _atomic_json(manifest, data)
        write_report(manifest, data, require_root)
        if rc:
            failures += 1
            print(f"Stopped: {run['id']} failed (exit {rc}). Fix it, then run the queue command again; it resumes this artifacts directory.", file=sys.stderr)
            break
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Queue approved interview sessions for sequential spec generation")
    ap.add_argument("--manifest", type=Path, default=Path("batch-specs.json"))
    sub = ap.add_subparsers(dest="command", required=True)
    a = sub.add_parser("add", help="queue one approved intent model")
    a.add_argument("intent_model", type=Path)
    a.add_argument("--repeat", type=int, default=1)
    a.add_argument("--name")
    r = sub.add_parser("run", help="run queued jobs sequentially; interrupted jobs resume in place")
    r.add_argument("--limit", type=int)
    retry_p = sub.add_parser("retry", help="requeue one diagnosed failed run in its existing directory")
    retry_p.add_argument("run_id")
    sub.add_parser("report", help="rebuild deterministic reports from completed runs")
    args = ap.parse_args()
    manifest = args.manifest.expanduser().resolve()
    try:
        if args.command == "add":
            added = add(manifest, args.intent_model, args.repeat, args.name)
            for run in added:
                print(f"Queued {run['id']} -> spec-generator/{run['artifacts']} (estimate {HOURS_MIN}-{HOURS_MAX}h)")
            print(f"Manifest: {manifest}")
            return 0
        if args.command == "run":
            return run_queue(manifest, _root(), args.limit)
        if args.command == "retry":
            run = retry(manifest, args.run_id)
            print(f"Requeued {run['id']} in existing directory spec-generator/{run['artifacts']}")
            return 0
        data = _load(manifest)
        report = write_report(manifest, data, _root())
        print(f"Wrote {manifest.with_name('batch-report.json')} and batch-report.md ({len(report['runs'])} completed runs)")
        return 0
    except (ValueError, OSError, json.JSONDecodeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
