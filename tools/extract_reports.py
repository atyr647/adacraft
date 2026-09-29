#!/usr/bin/env python3
"""Regenerate Adacraft.Protocol.Ids from the pinned 26.3 packet report.

The report itself is produced by the official generator:

    java -cp <bundled libs>:<inner server jar> \\
        net.minecraft.data.Main --reports --output <dir>

This script does not invent ids and does not read a 1.21.x source tree.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKETS = ROOT / "generated" / "26.3" / "reports" / "packets.json"
OUT = ROOT / "generated" / "adacraft-protocol-ids.ads"

STATES = ("handshake", "status", "login", "configuration", "play")
STATE_NAME = {
    "handshake": "Handshake",
    "status": "Status",
    "login": "Login",
    "configuration": "Configuration",
    "play": "Play",
}


def ada_enum(state: str, direction: str, ident: str) -> str:
    short = ident.split(":", 1)[1]
    short = re.sub(r"[^A-Za-z0-9]+", "_", short).strip("_")
    parts = [part.capitalize() for part in short.split("_") if part]
    bound = "Sb" if direction == "serverbound" else "Cb"
    return f"{bound}_{STATE_NAME[state]}_{'_'.join(parts)}"


def main() -> int:
    pin = (ROOT / "pin" / "26.3.toml").read_text()
    if 'protocol = 777' not in pin or 'data_version = 5023' not in pin:
        print("pin is not 26.3 / 777 / 5023", file=sys.stderr)
        return 1
    packets = json.loads(PACKETS.read_text())
    entries = []
    for state in STATES:
        for direction in ("serverbound", "clientbound"):
            for ident, body in packets.get(state, {}).get(direction, {}).items():
                entries.append((ada_enum(state, direction, ident), int(body["protocol_id"])))
    names = [name for name, _ in entries]
    if len(names) != len(set(names)):
        print("duplicate Ada packet names", file=sys.stderr)
        return 1
    entries.sort()
    lines = [
        "-- Generated from the pinned Minecraft 26.3 server PacketReport.",
        "-- Do not edit. Regenerate with tools/extract_reports.py.",
        "-- Protocol 777. Data version 5023.",
        "package Adacraft.Protocol.Ids is",
        "",
        "   type Packet_Name is",
        "     (",
    ]
    for index, (name, _) in enumerate(entries):
        comma = "," if index < len(entries) - 1 else ""
        lines.append(f"      {name}{comma}")
    lines += [
        "     );",
        "",
        "   type Id_Table is array (Packet_Name) of Natural;",
        "   Protocol_Id : constant Id_Table := (",
    ]
    for index, (name, protocol_id) in enumerate(entries):
        comma = "," if index < len(entries) - 1 else ""
        lines.append(f"      {name} => {protocol_id}{comma}")
    lines += ["   );", "end Adacraft.Protocol.Ids;", ""]
    OUT.write_text("\n".join(lines))
    print(f"wrote {len(entries)} packet ids to {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
