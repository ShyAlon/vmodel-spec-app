# SWEBOK memorization probe

Answers: "was my local model already trained on the SWEBOK Guide v4?"

    # one-time: brew install poppler   (or: python3 -m pip install --user pypdf)
    # get the PDF free: https://computer.org/swebok
    python3 probe_swebok.py ~/Downloads/swebok-v4.pdf --model qwen2.5-coder:14b

Prints a per-passage verbatim-overlap score and a verdict
(LIKELY MEMORIZED / PARTIALLY FAMILIAR / NOT MEMORIZED).

How it works: the script extracts text from YOUR local PDF (no book text is
stored in this repo), shows the model the first 24 words of 11 distinctive
passages, and scores 8-word verbatim overlap between the model's continuation
and the real text. Temperature 0, local Ollama only - zero cost.
