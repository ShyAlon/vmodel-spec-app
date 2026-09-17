"""Launcher protects meaningful exact-product work from accidental fresh sessions."""
from pathlib import Path


def test_exact_product_resume_guard_and_explicit_override_are_present():
    text=(Path(__file__).parents[1]/"scripts/run-full-flow.sh").read_text()
    assert '--new-session) NEW_SESSION=1' in text
    assert 'this exact product already has an in-progress session' in text
    assert 'launcher-idea.json' in text
    assert 'idea.encode() in bytes(v)' in text  # legacy sessions: inspect checkpoint payload
    assert 're.search(r"^You:\\s*\\S", text, re.MULTILINE)' in text
    assert 'add --new-session' in text
    assert '$0 --session $MATCH --greenfield --expert-opinion' in text
