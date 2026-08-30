#!/usr/bin/env python3
import json, sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)

names = [m["name"] for m in data.get("mice", []) if m.get("name")]
print("|".join(names), end="")
