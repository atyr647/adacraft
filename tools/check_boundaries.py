#!/usr/bin/env python3
"""Fail if protocol or network code can name the kernel or the world."""

from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
banned = ("Adacraft.Kernel", "Adacraft.World", "Chunk.Set_Block")
roots = [root / "src" / "protocol", root / "src" / "network"]
bad = []
for base in roots:
    for path in base.rglob("*"):
        if path.suffix not in {".ads", ".adb"}:
            continue
        text = path.read_text()
        for token in banned:
            if token in text:
                bad.append(f"{path.relative_to(root)}: {token}")
if bad:
    print("boundary violation")
    print("\n".join(bad))
    sys.exit(1)
print("boundaries ok")
