#!/usr/bin/env python3
import json, re, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

pat = re.compile(r"apple|bcm5974|touchpad|trackpad|mtp", re.I)
names = [
    m["name"]
    for m in data.get("mice", [])
    if pat.search(m.get("name", ""))
]
print("|".join(names), end="")
