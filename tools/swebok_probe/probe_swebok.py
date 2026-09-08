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
    python3 probe_swebok.py --control [--model qwen2.5-coder:14b]

--control runs a positive control: texts any LLM is near-certain to have
memorized (MIT/Apache/GPL licenses, Gettysburg Address). If SWEBOK scores
~0%% AND the control scores high, the "not memorized" verdict is solid. If
the control also scores ~0, suspect the scorer or the model, not SWEBOK.
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



def _mk(source: str, full_text: str) -> tuple[str, str, list[str]]:
    ws = full_text.split()
    return source, " ".join(ws[:24]), ws[24:64]


# Positive controls: texts any model trained on public code/corpora is
# near-certain to have memorized. Shipped inline - they are the point.
CONTROL_TEXTS = [
    _mk("the MIT License",
        "Permission is hereby granted, free of charge, to any person obtaining a copy "
        "of this software and associated documentation files (the Software), to deal "
        "in the Software without restriction, including without limitation the rights "
        "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell "
        "copies of the Software, and to permit persons to whom the Software is "
        "furnished to do so, subject to the following conditions:"),
    _mk("the Apache License 2.0",
        "Subject to the terms and conditions of this License, each Contributor hereby "
        "grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, "
        "irrevocable copyright license to reproduce, prepare Derivative Works of, "
        "publicly display, publicly perform, sublicense, and distribute the Work and "
        "such Derivative Works in Source or Object form. Grant of Patent License. "
        "Subject to the terms and conditions of this License, each Contributor hereby "
        "grants to You a perpetual, worldwide, non-exclusive, no-charge, royalty-free, "
        "irrevocable (except as stated in this section) patent license to make, have "
        "made, use, offer to sell, sell, import, and otherwise transfer the Work."),
    _mk("the GNU General Public License v3 preamble",
        "The GNU General Public License is a free, copyleft license for software and "
        "other kinds of works. The licenses for most software and other practical works "
        "are designed to take away your freedom to share and change the works. By "
        "contrast, the GNU General Public License is intended to guarantee your freedom "
        "to share and change all versions of a program--to make sure it remains free "
        "software for all its users."),
    _mk("the Gettysburg Address",
        "Four score and seven years ago our fathers brought forth on this continent, "
        "a new nation, conceived in Liberty, and dedicated to the proposition that "
        "all men are created equal. Now we are engaged in a great civil war, testing "
        "whether that nation, or any nation so conceived and so dedicated, can long "
        "endure. We are met on a great battle-field of that war. We have come to "
        "dedicate a portion of that field, as a final resting place for those who here "
        "gave their lives that that nation might live. It is altogether fitting and "
        "proper that we should do this."),
]

PROMPT = (
    "The following is the beginning of a passage from {source}. Continue it "
    "exactly as it is written in the original, for about 40 more words. Do "
    "not paraphrase; do not explain; output only the continuation.\n\n---\n{prefix}\n"
)
SWEBOK_SOURCE = "the IEEE SWEBOK Guide (Software Engineering Body of Knowledge)"


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
    ap.add_argument("pdf", type=Path, nargs="?", help="path to your local swebok-v4 PDF")
    ap.add_argument("--control", action="store_true",
                    help="positive control: probe near-certainly-memorized texts instead (no PDF needed)")
    ap.add_argument("--model", default="qwen2.5-coder:14b")
    ap.add_argument("--host", default="http://localhost:11434")
    ap.add_argument("--limit", type=int, default=len(ANCHORS))
    ap.add_argument("--ngram", type=int, default=8,
                    help="verbatim-run length scored (default 8 words)")
    args = ap.parse_args()
    if args.control:
        passages = [(s, p, e) for s, p, e in CONTROL_TEXTS][: args.limit]
        print(f"POSITIVE CONTROL: probing {args.model} with texts it is "
              "near-certain to have memorized\n"
              "(compare against your SWEBOK run - controls should score HIGH)\n")
    else:
        if args.pdf is None or not args.pdf.exists():
            sys.exit("PDF not found: " + str(args.pdf) + "\n"
                     "get it free at https://computer.org/swebok "
                     "(or run --control for the positive control, no PDF needed)")
        print(f"extracting text from {args.pdf} ...", file=sys.stderr)
        text = normalize(extract_text(args.pdf))
        passages = []
        for section, anchor in ANCHORS:
            i = text.find(anchor)
            if i < 0:
                print(f"[skip] {section}: anchor not found in this PDF edition")
                continue
            ws = text[i:i + 460].split()
            passages.append((section, " ".join(ws[:24]), ws[24:64], SWEBOK_SOURCE))
        passages = [(s, p, e, src_) for s, p, e, src_ in passages][: args.limit]
        print(f"probing {args.model} via {args.host} "
              f"({len(passages)} passages, n={args.ngram})...\n")
    scores = []
    for item in passages:
        if len(item) == 3:
            section, prefix, expected = item
            source = section
        else:
            section, prefix, expected, source = item
        completion = ollama_generate(args.host, args.model,
                                     PROMPT.format(source=source, prefix=prefix))
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
    if args.control:
        verdict = (
            "CONTROL PASS - the model recites known-memorized texts verbatim, so a ~0 SWEBOK score is trustworthy: SWEBOK v4 is genuinely not in its memory."
            if mean > 0.5 else
            "CONTROL WEAK - the model only partially recites texts it should know cold. The machinery works, but this model paraphrases a lot; a ~0 SWEBOK score is suggestive, not proof."
            if mean > 0.2 else
            "CONTROL FAIL - the model cannot recite even the MIT license. Either the scorer is broken or this code-tuned model paraphrases everything; a ~0 SWEBOK score proves NOTHING until this is explained."
        )
    else:
        verdict = (
            "LIKELY MEMORIZED - the model reproduces the text verbatim; quoting it in prompts adds little it does not already 'know' (and check what edition it memorized - probably v3)."
            if mean > 0.5 else
            "PARTIALLY FAMILIAR - the model knows the concepts and some phrasing, but does not recite the text. Curated context still adds precision."
            if mean > 0.2 else
            "NOT MEMORIZED - the model cannot reproduce the text. Curated excerpts are real new knowledge for it. (Sanity-check with --control if unsure.)"
        )
    print(f"mean {args.ngram}-gram overlap: {mean:.0%} over {len(scores)} passages")
    print(f"verdict: {verdict}")


if __name__ == "__main__":
    main()
