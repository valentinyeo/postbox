#!/usr/bin/env python3
import json
import re
import sys


def norm(text):
    text = text.lower().replace("-", "_").replace(" ", "_")
    return re.sub(r"[^a-z0-9_+]", "", text)


def catalog(path):
    out = {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r"\s*\\\\(\S+)\|([^|]*)\|", line)
        if m:
            out[m.group(1).replace("️", "")] = (m.group(1), norm(m.group(2)))
    return out


cat = catalog(sys.argv[2])
lines = []
for entry in json.load(open(sys.argv[1], encoding="utf-8")):
    if entry["category"] == "Flags":
        continue
    key = entry["emoji"].replace("️", "")
    if key not in cat:
        continue
    full, cldr = cat[key]
    names = [a for a in entry["aliases"] if a != cldr]
    if names:
        lines.append(full + " " + " ".join(names))
print("pub const aliases =")
print("\n".join("    \\\\" + l for l in lines))
print("    ;")
