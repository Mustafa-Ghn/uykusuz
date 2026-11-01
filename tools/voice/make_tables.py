#!/usr/bin/env python3
"""The word tables the app's speech text uses, made once and shipped under Resources/Voice.

    make_tables.py <foreign.py dir> <corpus dir> <swift sources dir> <out dir>

english.tsv   English word, then how a Turkish speaker says it in Turkish letters (from the CMU dictionary).
              Used only for the parts of camelCase names. The list holds common English words and every word
              found in code names here, so it stays small; the full dictionary would be seven times larger.
caps.txt      Words of 4 to 6 letters that Turkish text also writes in lowercase: an ALLCAPS one is read as a word
              (NASA, ROMEO, SARS, UYARI), not letter by letter.
"""
import collections
import json
import re
import sys
from pathlib import Path

FOREIGN, CORPUS, SOURCES, OUT = sys.argv[1:5]
sys.path.insert(0, FOREIGN)
from foreign import _CAMEL, _cmu, _from_phones  # noqa: E402

OUT = Path(OUT)
OUT.mkdir(parents=True, exist_ok=True)
EGITIM = Path(CORPUS)
WORD = re.compile(r"[A-Za-z]+")
LOWER = str.maketrans({"I": "ı", "İ": "i"})

english = collections.Counter()
for path in [EGITIM / "ted2020/TED2020.en-tr.en"] + sorted((EGITIM / "kaynaklar/qed").glob("QED.en-tr.en")):
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            english.update(w.lower() for w in WORD.findall(line))

code = collections.Counter()
for path in Path(SOURCES).rglob("*.swift"):
    for token in re.findall(r"[A-Za-z][A-Za-z0-9]*", path.read_text(encoding="utf-8")):
        code.update(p.lower() for p in _CAMEL.findall(token) if p.isalpha() and len(p) >= 2)

cmu = _cmu()
keep = {w for w, c in english.items() if c >= 8 and w in cmu} | {w for w in code if w in cmu}
rows = sorted((w, _from_phones(cmu[w], w)) for w in keep if len(w) >= 2 and w.isalpha())
with open(OUT / "english.tsv", "w", encoding="utf-8") as f:
    for word, spoken in rows:
        f.write(f"{word}\t{spoken}\n")
print("english.tsv", len(rows), "words", (OUT / "english.tsv").stat().st_size // 1024, "KB")

# ALLCAPS words Turkish text knows as words.
TOKEN = re.compile(r"[^\W\d_]+")
files = sorted((EGITIM / "kaynaklar/opus-diller").glob("*/*.tr")) + [EGITIM / "ted2020/TED2020.en-tr.tr", EGITIM / "kaynaklar/qed/QED.en-tr.tr"]
caps, words = collections.Counter(), collections.Counter()
seen = set()
for path in files:
    with open(path, encoding="utf-8", errors="ignore") as f:
        for line in f:
            h = hash(line)
            if h in seen:
                continue
            seen.add(h)
            for t in TOKEN.findall(line):
                if t.isupper():
                    if 4 <= len(t) <= 6:
                        caps[t] += 1
                else:
                    words[t.translate(LOWER).lower()] += 1
known = {t for t, c in caps.items() if c >= 2 and (words[t.translate(LOWER).lower()] >= 20 or words[t.lower()] >= 20)}
# Said as words everywhere, but Turkish text writes them in capitals only, so the count above misses them.
known = sorted(known | {"NATO", "UNESCO", "UNICEF", "AIDS", "SARS", "COVID"})
(OUT / "caps.txt").write_text("\n".join(known) + "\n", encoding="utf-8")
print("caps.txt", len(known), "words", known[:40])
