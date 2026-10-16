#!/usr/bin/env python3
"""Scores a dictation cleaner on the held-out test set.

A predictor is any function (record) -> text. Baselines: raw text as spoken, and a Python port of the
rule based cleaner that ships in the app today (DictationCleaner in Dictation.swift).

Metrics
  exact      share of records whose output equals the clean target
  cer        character error rate against the target (lower is better)
  over_edit  share of records where the output changes the meaning words (a content word was dropped
             or invented), the failure that matters most for dictation
  by mode    exact match per field type
"""
import json, re, sys, os, collections

DATA = os.path.join(os.path.dirname(__file__), "data")

def load(split):
    return [json.loads(l) for l in open(os.path.join(DATA, f"{split}.jsonl"))]

def levenshtein(a, b):
    if a == b: return 0
    if not a: return len(b)
    if not b: return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]

def content_words(s):
    stop = {"a", "an", "the", "um", "uh", "uhm", "er", "hmm", "like", "so", "basically", "kind", "of", "you", "know", "i", "mean"}
    return [w for w in re.findall(r"[a-z0-9']+", s.lower()) if w not in stop]

def over_edit(pred, clean, raw):
    """True if the prediction lost words the target keeps, or added words nobody said or wrote."""
    p, c, r = collections.Counter(content_words(pred)), collections.Counter(content_words(clean)), collections.Counter(content_words(raw))
    lost = sum(((c - p).values()))
    invented = sum(((p - (c + r)).values()))
    return lost > 1 or invented > 1

# ---------------------------------------------------------------- baselines

def baseline_raw(rec): return rec["raw"]

def starts_sentence(before):
    t = re.sub(r"[ \t]+$", "", before)
    return (not t) or t[-1] in ".!?\n" or t.endswith("- ") or t.endswith("# ")

def baseline_rules(rec):
    """Port of DictationCleaner.clean from Dictation.swift."""
    t = rec["raw"].strip()
    terminal = rec["mode"] == "terminal"
    t = re.sub(r"(?i)\b(?:um+|uh+|uhm+|erm+|er|hmm+|mm+)\b[,.]?\s*", "", t).strip()
    if not terminal:
        t = re.sub(r"(?i)[,.]?\s*\bnew paragraph\b[,.]?\s*", "\n\n", t)
        t = re.sub(r"(?i)[,.]?\s*\bnew line\b[,.]?\s*", "\n", t)
        t = re.sub(r"(?i)^bullet(?: point)?[,.:]?\s*", "- ", t)
        t = re.sub(r"(?i)^heading (?:one|1)[,.:]?\s*", "# ", t)
        t = re.sub(r"(?i)^heading (?:two|2)[,.:]?\s*", "## ", t)
        t = re.sub(r"(?i)^heading (?:three|3)[,.:]?\s*", "### ", t)
        t = re.sub(r"(?i)^to do[,.:]?\s*", "- [ ] ", t)
        t = re.sub(r"[ \t]+\n", "\n", t)
    if terminal:
        return t.lower().strip(".,;")
    if starts_sentence(rec["before"]):
        m = re.search(r"[A-Za-z]", t)
        if m and re.match(r"^[-#\[\] x]*$", t[:m.start()]):
            t = t[:m.start()] + t[m.start()].upper() + t[m.start() + 1:]
    t = re.sub(r"(\n+(?:- (?:\[ \] )?|#+ )?)([a-z])", lambda m: m.group(1) + m.group(2).upper(), t)
    b = rec["before"]
    if b and not b[-1].isspace() and b[-1] not in "\n([{" and t and not (t[0].isspace() or t[0] in ",.;:!?)"):
        t = " " + t
    return t

# ---------------------------------------------------------------- scoring

def score(name, predictor, rows):
    exact = cer_num = cer_den = oe = 0
    per = collections.defaultdict(lambda: [0, 0])
    for rec in rows:
        pred = predictor(rec)
        ok = pred == rec["clean"]
        exact += ok
        cer_num += levenshtein(pred, rec["clean"]); cer_den += max(len(rec["clean"]), 1)
        oe += over_edit(pred, rec["clean"], rec["raw"])
        per[rec["mode"]][0] += ok; per[rec["mode"]][1] += 1
    n = len(rows)
    modes = "  ".join(f"{m} {100 * a / b:.0f}%" for m, (a, b) in sorted(per.items()))
    print(f"{name:<22} exact {100 * exact / n:5.1f}%   cer {100 * cer_num / cer_den:5.1f}%   over-edit {100 * oe / n:4.1f}%   {modes}")
    return exact / n

if __name__ == "__main__":
    rows = load("test")
    print(f"test set: {len(rows)} records (held-out names and topics)\n")
    score("raw as spoken", baseline_raw, rows)
    score("rules (in the app now)", baseline_rules, rows)
