"""Prints the non-fader, non-encoder messages captured under each LABEL in a capture log.

Usage: python3 -I tools/summarise-round.py captures/<log>
"""
import sys
from collections import Counter

label, out, order = None, {}, []
for line in open(sys.argv[1]):
    parts = line.split(None, 2)
    if len(parts) < 3 or line.startswith("#"):
        continue
    if parts[1] == "LABEL":
        label = parts[2].strip()
        order.append(label)
        out[label] = []
    elif parts[1] == "IN" and label is not None:
        b = parts[2].split()
        if b[0] == "B0" and int(b[1], 16) < 0x28:   # fader positions
            continue
        if b[0] == "B0" and 0x40 <= int(b[1], 16) <= 0x47:   # encoders
            continue
        if b[0] == "90" and b[1] == "05" and int(b[2], 16) & 0x3F < 8:   # fader touch
            continue
        out[label].append(" ".join(b))
for name in order:
    counts = Counter(out[name])
    text = ", ".join(f"{k} x{v}" if v > 1 else k for k, v in counts.items()) or "(nothing)"
    print(f"{name:24s} {text}")
