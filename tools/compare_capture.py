#!/usr/bin/env python3
"""Compare two captures (tools/capture_configuration.py output) frame by
frame, knowing how the oracle varies from one run of its process to the
next (docs/ORACLE.md), so a difference that is only that isn't taken for
a bug, and a real one isn't waved through.

    python3 tools/compare_capture.py EXPECTED.jsonl ACTUAL.jsonl

Each frame is one of:
  same         byte for byte
  reordered    the same bytes in another order, in a packet whose lists
               the oracle sends in hash-map order (update_tags,
               update_recipes, the dimension list of login)
  per-run      a field the oracle gives anew each run or connection:
               keep-alive ids, the player's entity id, the spawn position
  DIFFERENT    anything else: a bug, or a rule missing here
Exit status 1 if any frame is DIFFERENT or the frame counts differ.
"""

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORT = json.loads((ROOT / "generated" / "26.3" / "reports" / "packets.json").read_text())

REORDERED = {
    ("configuration", "minecraft:update_tags"),
    ("play", "minecraft:update_recipes"),
    ("play", "minecraft:login"),
}
PER_RUN = {
    ("configuration", "minecraft:keep_alive"),
    ("play", "minecraft:keep_alive"),
    ("play", "minecraft:player_position"),
}
# Packets whose only per-connection field is the entity id after the packet
# id (a big-endian Int at body octets 2..5).
ENTITY = {("play", "minecraft:login"), ("play", "minecraft:entity_event")}


def load(path):
    return [json.loads(line) for line in Path(path).read_text().splitlines() if line.strip()]


def named(frames):
    """Each frame with its state and packet name: CONFIGURATION until the
    client's Finish Configuration, PLAY after."""
    state = "configuration"
    out = []
    for f in frames:
        table = REPORT[state]["clientbound" if f["direction"] == "clientbound" else "serverbound"]
        name = next((k for k, v in table.items() if v["protocol_id"] == f["id"]), f"#{f['id']}")
        out.append((state, name, f))
        if state == "configuration" and f["direction"] == "serverbound" \
                and name == "minecraft:finish_configuration":
            state = "play"
    return out


def without_entity(hex_frame):
    b = bytearray(bytes.fromhex(hex_frame))
    # frame = length VarInt, packet id VarInt (one octet below 128), Int
    i = 0
    while b[i] & 0x80:
        i += 1
    b[i + 2:i + 6] = b"\0\0\0\0"
    return bytes(b)


def verdict(state, name, a, b):
    if a == b:
        return "same"
    key = (state, name)
    if key in ENTITY and without_entity(a) == without_entity(b):
        return "per-run"
    if key in REORDERED and len(a) == len(b) and Counter(bytes.fromhex(a)) == Counter(bytes.fromhex(b)):
        return "reordered"
    if key in REORDERED and key in ENTITY:
        x, y = without_entity(a), without_entity(b)
        if len(x) == len(y) and Counter(x) == Counter(y):
            return "reordered"
    if key in PER_RUN and len(a) == len(b):
        return "per-run"
    return "DIFFERENT"


def main() -> int:
    exp, act = named(load(sys.argv[1])), named(load(sys.argv[2]))
    bad = len(exp) != len(act)
    tally = Counter()
    for k, ((s1, n1, f1), (s2, n2, f2)) in enumerate(zip(exp, act), 1):
        if (s1, n1, f1["direction"]) != (s2, n2, f2["direction"]):
            print(f"{k}: DIFFERENT packet: {s1} {n1} vs {s2} {n2}")
            bad = True
            tally["DIFFERENT"] += 1
            continue
        v = verdict(s1, n1, f1["hex"], f2["hex"])
        tally[v] += 1
        if v != "same":
            print(f"{k}: {v:9} {s1} {f1['direction']} {n1}")
        bad = bad or v == "DIFFERENT"
    if len(exp) != len(act):
        print(f"frame counts differ: {len(exp)} expected, {len(act)} actual")
    print(", ".join(f"{n} {v}" for v, n in sorted(tally.items())))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
