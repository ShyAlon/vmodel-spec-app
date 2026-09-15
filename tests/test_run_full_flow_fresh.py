"""Shell-level guard for fresh spec generation from an approved interview."""
from pathlib import Path


def test_fresh_spec_flag_is_explicit_and_uses_new_output():
    text=(Path(__file__).parents[1]/"scripts/run-full-flow.sh").read_text()
    assert "--fresh-spec requires --session" in text
    assert 'SPEC_OUT="$REQUIRE_ROOT/artifacts/artifacts-${STAMP}-${SESSION}-fresh"' in text
    assert 'SPEC_OUT_ARGS=(-o "$SPEC_OUT")' in text
    assert 'python -m spec_generator.cli "$INTENT" --conops "$CONOPS" --system-baseline "$BASELINE" --review' in text
    # Old stable checkpoint is neither deleted nor moved.
    assert "rm -rf" not in text and "checkpoints.sqlite" not in text
