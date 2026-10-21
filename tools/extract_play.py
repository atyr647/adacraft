#!/usr/bin/env python3
"""Regenerate Adacraft.Protocol.Play_Data, and the captured golden scenario
of entering PLAY, from the oracle captures.

The captures are written in the lab by tools/capture_configuration.py
against the pinned server jar (flat world, seed 777, motd AdaCraft, a fresh
world and a new player for each):

  generated/26.3/play/oracle-opening.jsonl
      configuration, then the first frames of PLAY (--play 11)
  generated/26.3/play/oracle-wrong-keep-alive.jsonl
      a keep-alive answered with another id, and the server's disconnect
      (--wrong-keep-alive; trimmed to the keep-alive exchange)

Every body is taken from them as it is. The one field that differs from one
connection to the next, the player's entity id, is found here (it is 1 for
the oracle's first player) and named, not guessed. What is left out of the
opening, and why, is listed in OMIT.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKETS = ROOT / "generated" / "26.3" / "reports" / "packets.json"
OPENING = ROOT / "generated" / "26.3" / "play" / "oracle-opening.jsonl"
WRONG = ROOT / "generated" / "26.3" / "play" / "oracle-wrong-keep-alive.jsonl"
OUT = ROOT / "generated" / "adacraft-protocol-play_data.ads"
SCENARIO = ROOT / "tests" / "corpus" / "play-opening.scenario"

# Left out of what AdaCraft sends on entering PLAY: the command tree lists
# the vanilla server's commands, and AdaCraft runs none yet.
OMIT = {"minecraft:commands"}
# The opening packets whose body carries the player's entity id as a 4-byte
# big-endian Int straight after the packet id.
WITH_ENTITY = {"minecraft:login", "minecraft:entity_event"}
ORACLE_ENTITY = 1


def read_varint(data: bytes, i: int):
    n = shift = 0
    while True:
        b = data[i]
        i += 1
        n |= (b & 0x7F) << shift
        if not b & 0x80:
            return n, i
        shift += 7


def body_of(frame_hex: str) -> bytes:
    data = bytes.fromhex(frame_hex)
    n, i = read_varint(data, 0)
    assert len(data) == i + n, "capture frame length mismatch"
    return data[i:]


def ada_hex(name: str, body: bytes) -> str:
    h = body.hex().upper()
    pieces = [h[k:k + 96] for k in range(0, len(h), 96)] or [""]
    lines = [f"   {name} : aliased constant String :="]
    for k, p in enumerate(pieces):
        lead = "     " if k == 0 else "     & "
        lines.append(f'{lead}"{p}"' + (";" if k == len(pieces) - 1 else ""))
    return "\n".join(lines)


def spaced(data: bytes) -> str:
    h = data.hex().upper()
    return " ".join(h[k:k + 2] for k in range(0, len(h), 2))


def frame(body: bytes) -> bytes:
    n = len(body)
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out += bytes([b | 0x80])
        else:
            return out + bytes([b]) + body


def main() -> int:
    ids = json.loads(PACKETS.read_text())["play"]
    cb = {v["protocol_id"]: k for k, v in ids["clientbound"].items()}
    lines = [json.loads(x) for x in OPENING.read_text().splitlines() if x.strip()]
    # The configuration part ends with the client's Finish Configuration.
    cut = max(i for i, f in enumerate(lines)
              if f["direction"] == "serverbound" and f["id"] == 0x03) + 1
    play = [f for f in lines[cut:] if f["direction"] == "clientbound"]
    names = [cb[f["id"]] for f in play]
    if names[0] != "minecraft:login":
        raise SystemExit(f"PLAY doesn't open with login: {names}")
    sent = [(cb[f["id"]], body_of(f["hex"])) for f in play if cb[f["id"]] not in OMIT]
    for name, body in sent:
        if name in WITH_ENTITY and int.from_bytes(body[1:5], "big") != ORACLE_ENTITY:
            raise SystemExit(f"{name}: entity id isn't the oracle's first player's")

    wrong = [json.loads(x) for x in WRONG.read_text().splitlines() if x.strip()]
    ka = [f for f in wrong if f["direction"] == "clientbound"
          and cb.get(f["id"]) == "minecraft:keep_alive"]
    dis = [f for f in wrong if f["direction"] == "clientbound"
           and cb.get(f["id"]) == "minecraft:disconnect"]
    if not ka or len(dis) != 1:
        raise SystemExit("the keep-alive capture has no keep-alive or no single disconnect")
    ka_body = body_of(ka[0]["hex"])
    if len(ka_body) != 9:
        raise SystemExit("keep-alive isn't an id and a Long")

    out = [
        "-- Generated from the pinned Minecraft 26.3 server entering PLAY",
        "-- (generated/26.3/play/, captured in the lab by",
        "-- tools/capture_configuration.py). Do not edit. Regenerate with",
        "-- tools/extract_play.py.",
        "-- Protocol 777. Data version 5023.",
        "--",
        "-- Bodies in hex, packet id first, without the length prefix.",
        "package Adacraft.Protocol.Play_Data is",
        "",
        "   pragma Style_Checks (Off);",
        "",
        "   type Hex_Access is access constant String;",
        "",
        "   --  Clientbound and serverbound ids, from the packet report.",
        f"   Cb_Keep_Alive : constant := {ids['clientbound']['minecraft:keep_alive']['protocol_id']};",
        f"   Sb_Keep_Alive : constant := {ids['serverbound']['minecraft:keep_alive']['protocol_id']};",
        f"   Cb_Disconnect : constant := {ids['clientbound']['minecraft:disconnect']['protocol_id']};",
        "",
        "   --  What is sent on the client's Finish Configuration, in order: the",
        "   --  oracle's, less " + ", ".join(sorted(OMIT)) + " (no commands are run yet).",
        "   --  Those marked carry the player's entity id, a big-endian Int at",
        f"   --  octets 2 .. 5 (the oracle's first player's: {ORACLE_ENTITY}).",
    ]
    for k, (name, body) in enumerate(sent, 1):
        out.append(f"   --  {k}: {name}")
        out.append(ada_hex(f"Opening_{k}", body))
        out.append("")
    out.append(f"   Opening_Count : constant := {len(sent)};")
    out.append("   Opening : constant array (1 .. Opening_Count) of Hex_Access :=")
    out.append("     [" + ",\n      ".join(f"Opening_{k}'Access" for k in range(1, len(sent) + 1)) + "];")
    out.append("   Carries_Entity : constant array (1 .. Opening_Count) of Boolean :=")
    out.append("     [" + ", ".join("True" if n in WITH_ENTITY else "False" for n, _ in sent) + "];")
    out.append("")
    out.append("   --  A keep-alive answered with another id: the oracle's disconnect")
    out.append('   --  ({"translate":"disconnect.timeout"} as network NBT).')
    out.append(ada_hex("Timeout_Disconnect", body_of(dis[0]["hex"])))
    out.append("")
    out.append("end Adacraft.Protocol.Play_Data;")
    ada_text = "\n".join(out) + "\n"

    s = [
        "corpus_format: 1",
        "id: play-opening",
        "title: Entering PLAY as the 26.3 server does it",
        "description: Finish Configuration acknowledged enters PLAY; the server sends the "
        "oracle's opening packets, byte for byte, the first player's entity id being 1, "
        "and no command tree.",
        "category: play",
        "protocol: 777",
        "provenance: captured",
        "initial_state: CONFIGURATION_AWAITING_ACK",
        "final_state: PLAY",
        "",
        "step:",
        "  direction: serverbound",
        "  input: 01 03",
        "  outcome: accepted",
        "  packet_id: 0x03",
        "  state_after: PLAY",
        "",
    ]
    for name, body in sent:
        pid, _ = read_varint(body, 0)
        s.extend(["step:", "  direction: clientbound", f"  input: {spaced(frame(body))}",
                  "  outcome: accepted", f"  packet_id: 0x{pid:02X}", "  state_after: PLAY", ""])
    scenario_text = "\n".join(s)

    if "--check" in sys.argv:
        stale = [p.relative_to(ROOT) for p, t in ((OUT, ada_text), (SCENARIO, scenario_text))
                 if not p.exists() or p.read_text() != t]
        if stale:
            print("play data differs from the capture: " + ", ".join(map(str, stale)))
            return 1
        print("play data ok")
        return 0
    OUT.write_text(ada_text)
    SCENARIO.write_text(scenario_text)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(sent)} opening packets) and "
          f"{SCENARIO.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
