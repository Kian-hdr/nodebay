"""Synthetic, content-free benchmark labels and deterministic quality checks.

Checks catch factual/format regressions, not general answer quality. Replies are
examined only in memory and never included in benchmark reports.
"""
import re

CASES = {
    "focus": "Give one practical tip for staying focused.",
    "arithmetic": "What is 17 times 24? Give the result and one short explanation.",
    "format": "Write exactly three Markdown bullets about checking a backup: make a copy, open the copy, keep the original.",
    "summary": (
        "Summarize these fictional project notes in exactly three bullets. Preserve the dates, "
        "numbers and uncertainty, without inventing a launch commitment: "
        "The prototype completed 18 of 20 checks on September 1. Two checks remain blocked by "
        "missing hardware. The team proposes September 15 for release, but this is not approved. "
        "The allocated budget is EUR 2400, of which EUR 600 has been spent."
    ),
    "long": (
        "Write a 220 to 320 word explanation of why copying files is not the same as a tested "
        "backup. Use three Markdown headings. Cover restoring and opening a sample file, "
        "keeping version history, an offline copy, and why synchronization can propagate "
        "deletions. Do not claim you tested my files."
    ),
    "code": (
        "Explain this Python bug and provide corrected code in one fenced block: "
        "def add(value, items=[]): items.append(value); return items. "
        "The fixed function must not share a list between calls, must preserve a caller-supplied "
        "empty list, and must append only once. Do not run any code."
    ),
}


def quality_check(case, answer):
    text = answer.replace("NODEBAY_CHAT_OK", "").strip()
    lower = text.lower()
    bullets = sum(line.lstrip().startswith(("- ", "* ")) for line in text.splitlines())
    if case == "focus":
        return 0 < len(text.split()) < 100
    if case == "arithmetic":
        return bool(re.search(r"\b408\b", text))
    if case == "format":
        return bullets == 3
    if case == "summary":
        return (bullets == 3 and "18" in text and "20" in text and "15" in text
                and "2400" in text.replace(",", "") and "600" in text
                and any(word in lower for word in ("unapproved", "not approved", "propos", "tentative"))
                and "hardware" in lower)
    if case == "long":
        return (220 <= len(text.split()) <= 320
                and sum(bool(re.match(r"^#{1,6} ", line)) for line in text.splitlines()) == 3
                and all(word in lower for word in ("restor", "version", "offline", "delet")))
    if case == "code":
        # Do not execute model-produced code, even in synthetic benchmarks.
        return (text.count("```") == 2 and "items=None" in text.replace(" ", "")
                and "items is None" in text and text.count(".append(value)") == 1
                and "return items" in text)
    raise ValueError("Unknown synthetic benchmark case")
