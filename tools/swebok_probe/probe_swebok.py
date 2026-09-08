#!/usr/bin/env python3
"""Memorization probe: was your local LLM trained on the SWEBOK Guide v4?

Samples distinctive passages from YOUR local copy of the SWEBOK v4 PDF
(nothing from the book ships in this repo - the script extracts passages
from the PDF you point it at), shows your Ollama model the first words of
each passage, and measures how much of the real continuation it reproduces
verbatim. High overlap = the text (or an earlier edition of it) was likely
in the training data; low overlap = it was not.

Zero-cost, local-first: talks only to Ollama on localhost. Python stdlib only.
PDF text extraction needs ONE of: `pdftotext` (brew install poppler) or
the tiny pure-python `pypdf` package (python3 -m pip install --user pypdf).

Usage:
    python3 probe_swebok.py /path/to/swebok-v4.pdf [--model qwen2.5-coder:14b] [--limit 11]
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

# Short anchor phrases (de minimis) that locate distinctive passages in the
# guide. (section label, anchor) - the passage is the ~64 words after the anchor.
ANCHORS = [
    ("Requirements 1.1 definition", "a condition or capability needed by a user"),
    ("Requirements 1.4 functional", "Functional requirements specify observable"),
    ("Requirements 1.5 nonfunctional", "Nonfunctional requirements in some way constrain"),
    ("Requirements 2 elicitation goal", "The goal of requirements elicitation is to surface"),
    ("Requirements 3.1 properties", "be unambiguous (interpretable in"),
    ("Requirements 3.4 conflict", "One approach is to negotiate a resolution among the conflicting stakeholders"),
    ("Requirements 3.3 perfection point", "Perfection point"),
    ("Requirements 2.1 stakeholder", "A stakeholder can be defined as any"),
    ("Requirements 2.2 techniques", "Common stakeholder elicitation techniques include"),
    ("Design - abstraction", "Abstraction is a property that exposes only required or relevant information"),
    ("Testing - oracles", "many kinds of oracles"),
]

PROMPT = (
    "The following is the beginning of a passage from the IEEE SWEBOK Guide "
    "(Software Engineering Body of Knowledge). Continue it exactly as it is "
    "written in the guide, for about 40 more words. Do not paraphrase; do not "
    "explain; output only the continuation.\n\n---\n{prefix}\n"
)


def extract_text(pdf: Path) -> str:
    """PDF -> plain text via pdftotext if present, else pypdf."""
    if shutil.which("pdftotext"):
        with tempfile.NamedTemporaryFile(suffix=".txt", delete=False) as tmp:
            subprocess.run(["pdftotext", str(pdf), tmp.name], check=True)
            return Path(tmp.name).read_text(encoding="utf-8", errors="replace")
    try:
        from pypdf import PdfReader
    except ImportError:
        sys.exit(
            "could not extract PDF text.\n"
            "why: neither `pdftotext` nor the `pypdf` package is available.\n"
            "fix: brew install poppler   (or: python3 -m pip install --user pypdf)"
        )
    reader = PdfReader(str(pdf))
    return "\n".join(page.extract_text() or "" for page in reader.pages)


def normalize(s: str) -> str:
    s = re.sub(r"-\n", "", s)          # de-hyphenate line breaks
    s = re.sub(r"\s+", " ", s)          # collapse whitespace
    return s


def words(s: str) -> list[str]:
    s = s.lower().replace("\u2019", "'").replace("\u2014", " ").replace("\u2013", " ")
    s = s.replace("\u201c", '"').replace("\u201d", '"').replace("\u2022", " ")
    return [w.strip(".,;:()[]\"'") for w in s.split() if w.strip(".,;:()[]\"'")]


def ngrams(ws: list[str], n: int) -> set[tuple[str, ...]]:
    return {tuple(ws[i:i + n]) for i in range(len(ws) - n + 1)}


def ollama_generate(host: str, model: str, prompt: str) -> str:
    body = json.dumps({
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": 0, "num_predict": 140},
    }).encode()
    req = urllib.request.Request(
        host.rstrip("/") + "/api/generate", data=body,
        headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            return json.loads(resp.read())["response"]
    except (OSError, ValueError) as exc:
        sys.exit(
            f"could not reach Ollama at {host} ({exc}).\n"
            "why: the server is not running or the model is missing.\n"
            "fix: `ollama serve` in another terminal, then `ollama pull "
            + "qwen2.5-coder:14b` (or pass --model with one you have)."
        )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pdf", type=Path, help="path to your local swebok-v4 PDF")
    ap.add_argument("--model", default="qwen2.5-coder:14b")
    ap.add_argument("--host", default="http://localhost:11434")
    ap.add_argument("--limit", type=int, default=len(ANCHORS))
    ap.add_argument("--ngram", type=int, default=8,
                    help="verbatim-run length scored (default 8 words)")
    args = ap.parse_args()
    if not args.pdf.exists():
        sys.exit(f"PDF not found: {args.pdf}\n"
                 "get it free at https://computer.org/swebok")

    print(f"extracting text from {args.pdf} ...", file=sys.stderr)
    text = normalize(extract_text(args.pdf))

    print(f"probing {args.model} via {args.host} "
          f"({min(args.limit, len(ANCHORS))} passages, n={args.ngram})...\n")
    scores = []
    for section, anchor in ANCHORS[: args.limit]:
        i = text.find(anchor)
        if i < 0:
            print(f"[skip] {section}: anchor not found in this PDF edition")
            continue
        passage = text[i:i + 460].split()
        prefix, expected = " ".join(passage[:24]), passage[24:64]
        completion = ollama_generate(args.host, args.model,
                                     PROMPT.format(prefix=prefix))
        exp_g, cmp_g = ngrams(words(" ".join(expected)), args.ngram), ngrams(words(completion), args.ngram)
        gram_score = len(exp_g & cmp_g) / len(exp_g) if exp_g else 0.0
        lcs = SequenceMatcher(None, words(" ".join(expected)), words(completion))
        longest = max((b.size for b in lcs.get_matching_blocks()), default=0)
        scores.append(gram_score)
        print(f"[{gram_score:5.0%}] {section}")
        print(f"       prefix:    {prefix[:72]}...")
        print(f"       expected:  {' '.join(expected)[:72]}...")
        print(f"       model:     {' '.join(completion.split())[:72]}...")
        print(f"       longest verbatim run: {longest} words\n")

    if not scores:
        sys.exit("no passages probed - is this the right PDF?")
    mean = sum(scores) / len(scores)
    verdict = (
        "LIKELY MEMORIZED - the model reproduces the text verbatim; quoting it in prompts adds little it does not already 'know' (and check what edition it memorized - probably v3)."
        if mean > 0.5 else
        "PARTIALLY FAMILIAR - the model knows the concepts and some phrasing, but does not recite the text. Curated context still adds precision."
        if mean > 0.2 else
        "NOT MEMORIZED - the model cannot reproduce the text. Curated excerpts are real new knowledge for it."
    )
    print(f"mean {args.ngram}-gram overlap: {mean:.0%} over {len(scores)} passages")
    print(f"verdict: {verdict}")


if __name__ == "__main__":
    main()
