#!/usr/bin/env python3
"""Check the words, the way the tests check the code.

Every defect this catches was shipped at least once. The copy was written while
the implementation was still in mind, so the sentence that came out described
how the thing works rather than what the reader needs. Nothing caught it because
behaviour had thirty-eight tests and the words had none.

    python scripts/check-copy.py

Exits non-zero on a finding.
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STRINGS = os.path.join(ROOT, "web", "strings.reference.json")

# Panels that exist to be technical. Everything else speaks to a buyer.
TECHNICAL_KEYS = {
    "vTitle", "vBody", "vContract", "vPlan", "vProof", "vChain",
    "fContract", "fChain", "fSource", "errPlan", "plan", "s2b", "s2t",
}

# Words that belong in the source, not on a buyer's screen.
JARGON = [
    "precompile", "proven", "on chain", "on-chain", "blockchain", "smart contract",
    "eth_", "rpc", "indexer", "uint", "bytes32", "keccak", "merkle", "queryId",
    "프리컴파일", "온체인", "블록체인", "체인을 읽",
]

# Sentences that argue with nobody, or explain a decision the reader did not
# question. Each of these shipped.
MONOLOGUE = [
    "that is what keeps", "which is what keeps", "fall over", "falls over",
    "earned its keep", "would never have", "neither chain alone",
    "worth stating", "it is worth", "not a cleverer",
    "this page can show", "this page can display",
    "묻지", "설계상", "우리가 택한", "이 페이지가 표시할",
]

# Things a page should never promise.
OVERCLAIM = [
    "never fails", "always works", "guaranteed", "100% secure", "cannot be hacked",
    "절대 안전", "무조건", "100% 보장",
]

BANNED_PUNCT = {"—": "em dash"}


def load():
    return json.load(io.open(STRINGS, encoding="utf-8"))


def check_strings(d):
    problems = []
    langs = list(d)
    base = set(d["en"]) - {"_name", "_locale"}

    for L in langs:
        missing = base - set(d[L])
        extra = set(d[L]) - base - {"_name", "_locale"}
        if missing:
            problems.append("%s is missing %s" % (L, sorted(missing)))
        if extra:
            problems.append("%s has keys English does not: %s" % (L, sorted(extra)))

    ph = lambda v: ",".join(sorted(set(re.findall(r"\{(\w+)\}", str(v)))))
    for k in sorted(base):
        ref = ph(d["en"][k])
        for L in langs:
            if L == "en" or k not in d[L]:
                continue
            if ph(d[L][k]) != ref:
                problems.append("%s.%s placeholders [%s], English has [%s]"
                                % (L, k, ph(d[L][k]), ref))

    for L in langs:
        for k, v in d[L].items():
            if k.startswith("_"):
                continue
            low = str(v).lower()
            if k not in TECHNICAL_KEYS:
                for w in JARGON:
                    if w in low:
                        problems.append("%s.%s says %r, which is source vocabulary: %s"
                                        % (L, k, w, v[:60]))
            for w in MONOLOGUE:
                if w in low:
                    problems.append("%s.%s argues with nobody (%r): %s" % (L, k, w, v[:60]))
            for w in OVERCLAIM:
                if w in low:
                    problems.append("%s.%s overclaims (%r): %s" % (L, k, w, v[:60]))
            for ch, name in BANNED_PUNCT.items():
                if ch in str(v):
                    problems.append("%s.%s contains an %s" % (L, k, name))
            if not str(v).strip():
                problems.append("%s.%s is empty" % (L, k))
    return problems


def check_files(extra=()):
    """Judge-facing prose gets the monologue and punctuation checks too.

    Extra paths can be passed on the command line, so submission text that lives
    outside this repository is held to the same rules.
    """
    problems = []
    paths = [os.path.join(ROOT, r) for r in ("docs/deck.html", "README.md", "CLAUDE.md")]
    paths += list(extra)
    for path in paths:
        rel = os.path.basename(path)
        if not os.path.exists(path):
            problems.append("%s does not exist" % path)
            continue
        s = io.open(path, encoding="utf-8").read()
        for w in MONOLOGUE:
            for m in re.finditer(re.escape(w), s, re.I):
                line = s[:m.start()].count("\n") + 1
                problems.append("%s:%d argues with nobody (%r)" % (rel, line, w))
        for ch, name in BANNED_PUNCT.items():
            if ch in s:
                problems.append("%s contains an %s" % (rel, name))
    return problems


def main():
    d = load()
    problems = check_strings(d) + check_files(sys.argv[1:])
    if problems:
        print("copy check failed, %d finding(s):" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    n = len(set(d["en"]) - {"_name", "_locale"})
    print("copy check passed: %d strings x %d languages, plus deck, README and CLAUDE.md"
          % (n, len(d)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
