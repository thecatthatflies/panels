#!/usr/bin/env python3
"""Synthetic dictation data for panels-dictation-1.

Each record teaches one thing: given the mode of the text field, what is already before the caret,
the user's vocabulary, and a raw speech transcript, produce the clean text that should be inserted.

  {"mode": "note", "before": "...", "vocab": ["Panels"], "raw": "...", "clean": "..."}

The clean side is built first from templates, so it is correct by construction. The raw side is then
made by applying realistic speech damage: fillers, false starts, self corrections, spoken formatting,
spoken punctuation, number words, homophone slips and missing capitals. Standard library only.
"""
import json, random, re, sys, os, hashlib

SEED = int(os.environ.get("SEED", "7"))

PEOPLE = ["Maya", "Jonas", "Priya", "Tom", "Ilse", "Kenji", "Amara", "Luca", "Noor", "Dev", "Sofia", "Marcus", "Aisha", "Theo"]
HELD_OUT_PEOPLE = ["Zeynep", "Callum", "Ingrid", "Rafael"]
TOPICS = ["the launch", "the budget", "the design review", "the onboarding flow", "the quarterly report", "the new logo",
          "the pricing page", "the release notes", "the demo", "the hiring plan", "the migration", "the survey results",
          "the landing page", "the roadmap", "the invoice"]
HELD_OUT_TOPICS = ["the offsite", "the accessibility audit", "the vendor contract"]
PLACES = ["the office", "the cafe on main street", "the library", "room twelve", "the east building", "the park", "my place"]
DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
VERBS = ["send", "review", "finish", "update", "schedule", "check", "draft", "fix", "ship", "share", "write", "plan"]
THINGS = ["the report", "the slides", "the email", "the draft", "the spreadsheet", "the proposal", "the checklist",
          "the changelog", "the notes", "the mockups"]
WORDS_NUM = {0: "zero", 1: "one", 2: "two", 3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine",
             10: "ten", 11: "eleven", 12: "twelve", 13: "thirteen", 14: "fourteen", 15: "fifteen", 16: "sixteen",
             17: "seventeen", 18: "eighteen", 19: "nineteen", 20: "twenty", 30: "thirty", 40: "forty", 50: "fifty"}
VOCAB_POOL = ["Panels", "Instrument Sans", "SwiftUI", "MLX", "Xcode", "GitHub", "Lavender", "Granite", "Stripe", "Figma",
              "Notion", "Linear", "Vercel", "Postgres", "Kubernetes", "Homebrew"]
NOTE_TITLES = ["Welcome", "Roadmap", "Meeting notes", "Reading list", "Ideas log", "Weekly plan"]

FILLERS = ["um", "uh", "uhm", "er", "hmm", "like", "you know", "I mean", "so", "basically", "kind of"]
HARD_FILLERS = ["um", "uh", "uhm", "er", "hmm"]
SOFT_FILLERS = ["you know", "I mean", "basically", "like"]

def num_words(n):
    if n in WORDS_NUM: return WORDS_NUM[n]
    if n < 100:
        t, o = divmod(n, 10)
        return WORDS_NUM[t * 10] + " " + WORDS_NUM[o]
    return str(n)

def pick(r, xs): return xs[r.randrange(len(xs))]

# ------------------------------------------------------------------ clean sentence templates (prose)

def prose_sentence(r, held_out):
    people = HELD_OUT_PEOPLE if held_out else PEOPLE
    topics = HELD_OUT_TOPICS if held_out else TOPICS
    p, p2 = pick(r, people), pick(r, people)
    topic, thing, verb, place, day = pick(r, topics), pick(r, THINGS), pick(r, VERBS), pick(r, PLACES), pick(r, DAYS)
    hour, minute = r.randrange(1, 12), pick(r, [0, 15, 30, 45])
    t = [
        f"{p} will {verb} {thing} by {day}.",
        f"We should talk about {topic} before the meeting on {day}.",
        f"Can you ask {p} to {verb} {thing} for {topic}?",
        f"The meeting with {p} is at {hour}:{minute:02d} PM in {place}.",
        f"I think {topic} needs another pass, but {p2} disagrees.",
        f"{p} and {p2} are working on {topic} this week.",
        f"Remind me to {verb} {thing} on {day} morning.",
        f"Let's move {topic} to {day}, since {p} is out until then.",
        f"Thanks for {verb[:-1] + 'ing' if verb.endswith('e') else verb + 'ing'} {thing}, it really helped.",
        f"Is {topic} still on track, or should we tell {p}?",
        f"We spent about {r.randrange(2, 50)} percent of the budget on {topic}.",
        f"Their plan for {topic} is solid, and it's ready for review.",
        f"I'll see you at {place} around {hour} {pick(r, ['AM', 'PM'])}.",
        f"{p} said {thing} is almost done, which is good news.",
        f"There are {r.randrange(3, 40)} items left on the list for {topic}.",
    ]
    return pick(r, t)

# ------------------------------------------------------------------ damage functions

def to_spoken_numbers(s, r):
    def hhmm(m):
        h, mi = int(m.group(1)), int(m.group(2))
        spoken = num_words(h) + (" o'clock" if mi == 0 else (" " + ("oh " + num_words(mi) if mi < 10 else num_words(mi))))
        return spoken
    s = re.sub(r"\b(\d{1,2}):(\d{2})\b", hhmm, s)
    s = re.sub(r"\b(\d{1,2}) percent", lambda m: num_words(int(m.group(1))) + " percent", s)
    s = re.sub(r"\b(\d{1,2})\b", lambda m: num_words(int(m.group(1))) if int(m.group(1)) < 60 else m.group(1), s)
    s = s.replace(" PM", " p m").replace(" AM", " a m")
    return s

def homophone_slip(s, r):
    pairs = [("Their", "There"), ("their", "there"), ("it's", "its"), ("you're", "your"), ("to", "too"), ("two", "to")]
    for good, bad in pairs:
        if re.search(rf"\b{re.escape(good)}\b", s) and r.random() < 0.25:
            s = re.sub(rf"\b{re.escape(good)}\b", bad, s, count=1)
            break
    return s

def strip_punct(s, r):
    if r.random() < 0.55:
        s = re.sub(r"[.,;:!?]", "", s)
    return s

def lower_all(s, r):
    return s.lower() if r.random() < 0.5 else s

def add_fillers(words, r, rate):
    out = []
    for w in words:
        if r.random() < rate:
            out.append(pick(r, HARD_FILLERS if r.random() < 0.75 else SOFT_FILLERS))
        out.append(w)
    return out

def add_false_start(words, r):
    if len(words) < 4: return words
    i = r.randrange(1, min(len(words), 5))
    return words[:i] + words[:i] + words[i:]        # "we should we should go"

# ------------------------------------------------------------------ record builders

def build_prose(r, held_out):
    n = r.choice([1, 1, 2, 2, 3])
    sents = [prose_sentence(r, held_out) for _ in range(n)]
    clean = " ".join(sents)
    raw = clean
    notes = []

    # self correction: replace a day or number with "X no wait Y" where the clean keeps Y
    if r.random() < 0.28:
        for d in DAYS:
            if d in clean:
                wrong = pick(r, [x for x in DAYS if x != d])
                phrase = pick(r, ["no wait", "I mean", "sorry", "actually"])
                raw = raw.replace(d, f"{wrong} {phrase} {d}", 1)
                notes.append("self_correct")
                break

    if r.random() < 0.8: raw = to_spoken_numbers(raw, r)
    raw = homophone_slip(raw, r)
    raw = strip_punct(raw, r)
    raw = lower_all(raw, r)
    words = raw.split()
    if r.random() < 0.55: words = add_fillers(words, r, 0.09)
    if r.random() < 0.18: words = add_false_start(words, r)
    raw = " ".join(words)
    return clean, raw

def build_paragraph(r, held_out):
    a, ra = build_prose(r, held_out)
    b, rb = build_prose(r, held_out)
    return a + "\n\n" + b, ra + " new paragraph " + rb

def build_bullets(r, held_out):
    k = r.randrange(2, 5)
    items = []
    raws = []
    for _ in range(k):
        thing, verb = pick(r, THINGS), pick(r, VERBS)
        items.append(f"{verb.capitalize()} {thing}")
        raws.append(f"bullet {verb} {thing}")
    return "\n".join("- " + i for i in items), " ".join(raws)

def build_headings(r, held_out):
    lvl = r.randrange(1, 4)
    title = pick(r, ["Project plan", "Meeting notes", "Next steps", "Open questions", "Release checklist", "Summary"])
    word = {1: "one", 2: "two", 3: "three"}[lvl]
    body, raw_body = build_prose(r, held_out)
    return "#" * lvl + " " + title + "\n\n" + body, f"heading {word} {title.lower()} new paragraph {raw_body}"

def build_tasks(r, held_out):
    thing, verb, day = pick(r, THINGS), pick(r, VERBS), pick(r, DAYS)
    return f"- [ ] {verb.capitalize()} {thing} by {day}", f"to do {verb} {thing} by {day.lower()}"

def build_vocab(r, held_out):
    v = r.sample(VOCAB_POOL, 2)
    raw_v = [x.lower() for x in v]
    clean = f"I tried {v[0]} and {v[1]} yesterday, and both worked well."
    raw = f"i tried {raw_v[0]} and {raw_v[1]} yesterday and both worked well"
    return clean, raw, v

def build_wiki(r, held_out):
    t = pick(r, NOTE_TITLES)
    clean = f"See [[{t}]] for the details."
    raw = f"see link {t.lower()} for the details"
    return clean, raw, [t]

PATH_SEGS = ["src", "docs", "logs", "build", "tests", "projects", "notes", "assets", "config", "scripts", "app", "lib", "tmp", "backup"]
FILE_BASES = ["main", "readme", "index", "notes", "todo", "config", "server", "app", "output", "report", "setup"]
EXTS = ["py", "swift", "js", "md", "txt", "json", "sh", "ts", "html", "css"]
COMMANDS = [
    ("git", ["status", "add .", "pull", "push origin main", "checkout -b {branch}", "commit -m \"{msg}\"", "log --oneline", "diff", "stash", "merge {branch}"]),
    ("ls", ["-la", "-l", "-a", "{path}", "-lh {path}"]),
    ("cd", ["{path}", "..", "~/{path}", "~"]),
    ("npm", ["install", "run dev", "run build", "test", "install {pkg}", "run lint"]),
    ("brew", ["install {pkg}", "update", "upgrade", "uninstall {pkg}", "list"]),
    ("python3", ["{file}", "-m venv .venv", "-m http.server 8000", "-V"]),
    ("mkdir", ["-p {path}", "{seg}"]),
    ("rm", ["-rf {path}", "{file}", "-r {seg}"]),
    ("cp", ["{file} {path}", "-r {seg} {path}"]),
    ("mv", ["{file} {path}", "{file} {file}"]),
    ("cat", ["{file}", "{path}/{file}"]),
    ("grep", ["-r \"{word}\" {path}", "-n \"{word}\" {file}", "-i {word} {file}"]),
    ("swift", ["build", "build -c release", "test", "run"]),
    ("docker", ["compose up -d", "ps", "build -t {seg} .", "compose down", "logs {seg}"]),
    ("curl", ["-s {seg}.com", "-I https://{seg}.dev"]),
    ("open", [".", "{file}", "-a Safari"]),
    ("chmod", ["+x {file}", "755 {file}"]),
    ("echo", ["\"{msg}\"", "{word} > {file}"]),
    ("xcodebuild", ["-scheme {seg} build", "-list"]),
    ("kill", ["-9 {num}"]),
]
MSGS = ["fix typo", "add tests", "update readme", "bump version", "clean up", "initial commit", "refactor parser"]
PKGS = ["node", "python", "wget", "ripgrep", "eslint", "typescript", "react", "jq"]
BRANCHES = ["feature-login", "fix-bug", "dev", "release", "docs-update"]
WORDS = ["todo", "error", "main", "config", "fixme", "import", "panels"]

SPOKEN = [("--", " dash dash "), ("-", " dash "), ("~", " tilde "), ("/", " slash "), ("|", " pipe "), (">", " greater than "),
          ("\"", " quote "), (".", " dot "), ("+", " plus "), ("_", " underscore ")]
SPOKEN_DIGITS = {"0": "zero", "1": "one", "2": "two", "3": "three", "4": "four", "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "nine"}

def speak_command(cmd):
    s = cmd
    for sym, word in SPOKEN: s = s.replace(sym, word)
    s = re.sub(r"\d", lambda m: " " + SPOKEN_DIGITS[m.group(0)] + " ", s)
    return re.sub(r"\s+", " ", s).strip()

def build_terminal(r, held_out):
    tool, subs = pick(r, COMMANDS)
    sub = pick(r, subs)
    seg = pick(r, PATH_SEGS)
    path = "/".join(r.sample(PATH_SEGS, r.randrange(1, 3)))
    f = pick(r, FILE_BASES) + "." + pick(r, EXTS)
    cmd = tool + " " + sub.format(path=path, file=f, seg=seg, msg=pick(r, MSGS), pkg=pick(r, PKGS), branch=pick(r, BRANCHES),
                                  word=pick(r, WORDS), num=r.randrange(100, 9999))
    raw = speak_command(cmd)
    if r.random() < 0.3: raw = pick(r, HARD_FILLERS) + " " + raw
    if r.random() < 0.15: raw = raw.capitalize()
    return cmd.strip(), raw

BUILDERS_NOTE = [(build_prose, 34), (build_paragraph, 10), (build_vocab, 8), (build_wiki, 4)]
BUILDERS_MD = [(build_bullets, 14), (build_headings, 10), (build_tasks, 8), (build_prose, 10)]

def weighted(r, items):
    total = sum(w for _, w in items)
    x = r.uniform(0, total)
    for f, w in items:
        x -= w
        if x <= 0: return f
    return items[-1][0]

def make_before(r, mode):
    """What is already in the field before the caret (drives capitalization and spacing)."""
    choice = r.random()
    if mode == "terminal": return pick(r, ["", "$ ", "~/projects % "])
    if choice < 0.30: return ""
    if choice < 0.55: return pick(r, ["Hello team.", "That works.", "Notes from today.\n", "Thanks!\n\n"]) + pick(r, [" ", ""])
    if choice < 0.8: return pick(r, ["I think we should", "Let me know if", "The plan is to", "As discussed,"]) + " "
    return pick(r, ["- ", "# ", "- [ ] "]) if mode == "markdown" else "Quick note: "

def apply_context(clean, raw, before, mode):
    """Adjust the clean target to the surrounding text: capitalization and leading space."""
    if mode == "terminal": return clean, raw
    ends_sentence = (not before.strip()) or before.rstrip(" \t").endswith((".", "!", "?", "\n")) or before.rstrip().endswith(("- ", "# "))
    mid = before and not ends_sentence
    if mid and clean and clean[0].isupper() and not clean.startswith(("I ", "I'", "[[", "-", "#")):
        # continue a sentence: the first letter drops to lowercase unless it is a name; keep it simple and only do it for plain words
        first = clean.split(" ")[0]
        if first.lower() in {"the", "we", "can", "is", "let's", "there", "their", "thanks", "remind", "see", "i"}:
            clean = first.lower() + clean[len(first):]
    if before and not before.endswith((" ", "\n")) and not clean.startswith(("\n", " ")):
        clean = " " + clean
    return clean, raw

def make_record(r, held_out):
    mode = r.choices(["note", "markdown", "terminal"], weights=[56, 26, 18])[0]
    vocab = []
    if mode == "terminal":
        clean, raw = build_terminal(r, held_out)
    elif mode == "markdown":
        f = weighted(r, BUILDERS_MD)
        out = f(r, held_out); clean, raw = out[0], out[1]
    else:
        f = weighted(r, BUILDERS_NOTE)
        out = f(r, held_out); clean, raw = out[0], out[1]
        if len(out) > 2: vocab = out[2]
    before = make_before(r, mode)
    clean, raw = apply_context(clean, raw, before, mode)
    if not vocab and r.random() < 0.3: vocab = r.sample(VOCAB_POOL, r.randrange(1, 3))
    return {"mode": mode, "before": before, "vocab": vocab, "raw": raw, "clean": clean}

def main():
    out_dir = os.path.join(os.path.dirname(__file__), "data")
    os.makedirs(out_dir, exist_ok=True)
    r = random.Random(SEED)
    sizes = {"train": 30000, "valid": 1500, "test": 1500}
    seen = set()
    for split, n in sizes.items():
        held_out = split == "test"
        rows = []
        while len(rows) < n:
            rec = make_record(r, held_out)
            key = hashlib.md5((rec["mode"] + rec["before"] + rec["raw"]).encode()).hexdigest()
            if key in seen: continue
            seen.add(key)
            rows.append(rec)
        with open(os.path.join(out_dir, f"{split}.jsonl"), "w") as f:
            for rec in rows: f.write(json.dumps(rec, ensure_ascii=False) + "\n")
        print(f"{split}: {len(rows)} records" + ("  (held-out names and topics)" if held_out else ""))

if __name__ == "__main__":
    main()
