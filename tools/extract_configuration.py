#!/usr/bin/env python3
"""Regenerate Adacraft.Protocol.Configuration_Data, and the captured golden
scenario of the configuration exchange, from the oracle capture.

The capture (generated/26.3/configuration/oracle-core.jsonl) is written in
the lab by tools/capture_configuration.py against the pinned server jar: a
vanilla client that knows the minecraft:core 26.3 pack. Every clientbound
body the server sends in CONFIGURATION is taken from it as it is: nothing
here builds a registry or a tag by hand.

Packet ids are checked against the pinned packet report.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CAPTURE = ROOT / "generated" / "26.3" / "configuration" / "oracle-core.jsonl"
PACKETS = ROOT / "generated" / "26.3" / "reports" / "packets.json"
OUT = ROOT / "generated" / "adacraft-protocol-configuration_data.ads"
SCENARIO = ROOT / "tests" / "corpus" / "configuration-core-pack.scenario"

# The Login steps before configuration: the same Login Start as
# login-offline-happy, and the Login Success the server answers it with.
LOGIN_START = "17 00 05 4E 6F 74 63 68 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10"
LOGIN_SUCCESS = "18 02 B5 0A D3 85 82 9D 31 41 A2 16 7E 7D 75 39 BA 7F 05 4E 6F 74 63 68 00"
LOGIN_ACK = "01 03"


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


def spaced(frame_hex: str) -> str:
    h = frame_hex.upper()
    return " ".join(h[k:k + 2] for k in range(0, len(h), 2))


def main() -> int:
    ids = json.loads(PACKETS.read_text())["configuration"]
    cb = {v["protocol_id"]: k for k, v in ids["clientbound"].items()}
    sb = {v["protocol_id"]: k for k, v in ids["serverbound"].items()}
    frames = [json.loads(line) for line in CAPTURE.read_text().splitlines() if line.strip()]

    # Before the client's Select Known Packs: what the server sends on
    # Login Acknowledged. After it: the registries, the tags, the finish.
    first, after = [], []
    seen_packs = False
    for f in frames:
        table = cb if f["direction"] == "clientbound" else sb
        if f["id"] not in table:
            raise SystemExit(f"capture has unknown {f['direction']} id {f['id']:#x}")
        if f["direction"] == "serverbound":
            if table[f["id"]] == "minecraft:select_known_packs":
                seen_packs = True
            continue
        (after if seen_packs else first).append(f)

    names_first = [cb[f["id"]] for f in first]
    if names_first != ["minecraft:custom_payload", "minecraft:update_enabled_features",
                       "minecraft:select_known_packs"]:
        raise SystemExit(f"unexpected opening of configuration: {names_first}")
    regs = [f for f in after if cb[f["id"]] == "minecraft:registry_data"]
    tags = [f for f in after if cb[f["id"]] == "minecraft:update_tags"]
    fin = [f for f in after if cb[f["id"]] == "minecraft:finish_configuration"]
    rest = [f for f in after if f not in regs + tags + fin]
    if len(tags) != 1 or len(fin) != 1 or rest or after[-1] is not fin[0] or after[-2] is not tags[0]:
        raise SystemExit("unexpected close of configuration: "
                         + str([cb[f["id"]] for f in after]))

    out = [
        "-- Generated from the pinned Minecraft 26.3 server's configuration exchange",
        "-- (generated/26.3/configuration/oracle-core.jsonl, captured in the lab by",
        "-- tools/capture_configuration.py). Do not edit. Regenerate with",
        "-- tools/extract_configuration.py.",
        "-- Protocol 777. Data version 5023.",
        "--",
        "-- Each constant is a packet body in hex, packet id first, without the",
        "-- length prefix: what the server sends a client that knows the",
        "-- minecraft:core 26.3 pack.",
        "package Adacraft.Protocol.Configuration_Data is",
        "",
        "   pragma Style_Checks (Off);",
        "",
        "   type Hex_Access is access constant String;",
        "",
        "   --  The pack every vanilla 26.3 client knows.",
        '   Known_Pack_Namespace : constant String := "minecraft";',
        '   Known_Pack_Id        : constant String := "core";',
        '   Known_Pack_Version   : constant String := "26.3";',
        "",
        "   --  On Login Acknowledged, in this order.",
        ada_hex("Brand", body_of(first[0]["hex"])),
        "",
        ada_hex("Enabled_Features", body_of(first[1]["hex"])),
        "",
        ada_hex("Select_Known_Packs", body_of(first[2]["hex"])),
        "",
        "   --  On the client's Select Known Packs naming that pack, in this order.",
    ]
    for k, f in enumerate(regs, 1):
        out.append(ada_hex(f"Registry_{k}", body_of(f["hex"])))
        out.append("")
    out.append(f"   Registry_Count : constant := {len(regs)};")
    out.append("   Registries : constant array (1 .. Registry_Count) of Hex_Access :=")
    refs = [f"Registry_{k}'Access" for k in range(1, len(regs) + 1)]
    out.append("     [" + ",\n      ".join(refs) + "];")
    out.append("")
    out.append(ada_hex("Update_Tags", body_of(tags[0]["hex"])))
    out.append("")
    out.append(ada_hex("Finish_Configuration", body_of(fin[0]["hex"])))
    out.append("")
    out.append("end Adacraft.Protocol.Configuration_Data;")
    ada_text = "\n".join(out) + "\n"

    s = [
        "corpus_format: 1",
        "id: configuration-core-pack",
        "title: Configuration with the vanilla core pack, as the 26.3 server does it",
        "description: Login Acknowledged opens configuration with brand, features and the "
        "known-packs question; a client naming minecraft:core 26.3 gets the registries, the "
        "tags and Finish Configuration, byte for byte as the oracle sent them; its Finish "
        "Configuration moves to PLAY.",
        "category: configuration",
        "protocol: 777",
        "provenance: captured",
        "initial_state: LOGIN",
        "final_state: PLAY",
        "",
    ]

    def step(direction, frame_hex, pid, state):
        s.extend(["step:", f"  direction: {direction}", f"  input: {frame_hex}",
                  "  outcome: accepted", f"  packet_id: 0x{pid:02X}", f"  state_after: {state}", ""])

    step("serverbound", LOGIN_START, 0x00, "LOGIN_AWAITING_ACK")
    step("clientbound", LOGIN_SUCCESS, 0x02, "LOGIN_AWAITING_ACK")
    step("serverbound", LOGIN_ACK, 0x03, "CONFIGURATION")
    # The server's answer to Login Acknowledged comes straight after it in
    # the scenario (on the socket the client's first packets crossed it).
    ordered = first + [f for f in frames if f not in first]
    state = "CONFIGURATION"
    for f in ordered:
        # The answer to Select Known Packs ends with Finish Configuration:
        # from that packet on, the server waits for the client's.
        if f["direction"] == "serverbound" and sb[f["id"]] == "minecraft:select_known_packs":
            state = "CONFIGURATION_AWAITING_ACK"
        elif f["direction"] == "serverbound" and sb[f["id"]] == "minecraft:finish_configuration":
            state = "PLAY"
        step(f["direction"], spaced(f["hex"]), f["id"], state)
    scenario_text = "\n".join(s)
    if "--check" in sys.argv:
        stale = [p.relative_to(ROOT) for p, t in ((OUT, ada_text), (SCENARIO, scenario_text))
                 if not p.exists() or p.read_text() != t]
        if stale:
            print("configuration data differs from the capture: " + ", ".join(map(str, stale)))
            return 1
        print("configuration data ok")
        return 0
    OUT.write_text(ada_text)
    SCENARIO.write_text(scenario_text)
    print(f"wrote {OUT.relative_to(ROOT)} ({len(regs)} registries) and {SCENARIO.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
