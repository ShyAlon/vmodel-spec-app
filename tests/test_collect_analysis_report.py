from pathlib import Path


def test_collector_builds_report_from_selected_artifacts_not_repo_batch_state():
    text=(Path(__file__).parents[1]/"scripts/collect-analysis.sh").read_text()
    assert 'cp -p "$APP/$f" "$WORK/$f"' not in text
    assert '"source_artifacts_dir": name' in text
    assert '(work / "batch-report.json").write_text' in text
    assert 'criteria_without_tests' in text
