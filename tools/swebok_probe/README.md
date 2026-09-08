# SWEBOK memorization probe

Answers: "was my local model already trained on the SWEBOK Guide v4?"

    # one-time: brew install poppler   (or: python3 -m pip install --user pypdf)
    # get the PDF free: https://computer.org/swebok
    python3 probe_swebok.py ~/Downloads/swebok-v4.pdf --model qwen2.5-coder:14b

Prints a per-passage verbatim-overlap score and a verdict
(LIKELY MEMORIZED / PARTIALLY FAMILIAR / NOT MEMORIZED).

## Not sure you trust a 0%? Run the positive control

    python3 probe_swebok.py --control --model qwen2.5-coder:14b

Probes four texts any LLM has near-certainly memorized (MIT license, Apache
2.0 grant, GPL v3 preamble, Gettysburg Address) with the same machinery.

- control HIGH + SWEBOK ~0  -> "not memorized" is solid. Ship it.
- control ~0 too            -> the scorer or the model is the story, not
                               SWEBOK. A code-tuned model that paraphrases
                               everything would show up here.

## How it works

Extracts text from YOUR local PDF (no book text is stored in this repo),
shows the model the first 24 words of 11 distinctive passages, and scores
8-word verbatim overlap between the continuation and the real text.
Temperature 0, local Ollama only - zero cost.
