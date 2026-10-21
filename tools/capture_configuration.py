#!/usr/bin/env python3
"""Lab only: record the official 26.3 server's configuration exchange.

Drives a running oracle (the pinned server jar, offline mode, white-list
off, network-compression-threshold=-1) through handshake, offline login and
configuration as a vanilla client that knows the minecraft:core 26.3 pack,
and writes every frame of the configuration state, both directions, as JSON
lines (direction, packet id, hex of the whole frame).

    python3 tools/capture_configuration.py 127.0.0.1 25565 \\
        generated/26.3/configuration/oracle-core.jsonl

The shipped server never runs this or talks to the oracle. Its output is the
input of tools/extract_configuration.py.
"""

import json
import socket
import sys

PROTOCOL = 777


def varint(n: int) -> bytes:
    n &= 0xFFFFFFFF
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        if n:
            out += bytes([b | 0x80])
        else:
            return out + bytes([b])


def string(s: str) -> bytes:
    b = s.encode()
    return varint(len(b)) + b


def frame(pid: int, body: bytes = b"") -> bytes:
    p = varint(pid) + body
    return varint(len(p)) + p


def read_varint(data: bytes, i: int):
    n = shift = 0
    while True:
        b = data[i]
        i += 1
        n |= (b & 0x7F) << shift
        if not b & 0x80:
            return n, i
        shift += 7


class Oracle:
    def __init__(self, host: str, port: int):
        self.port = port
        self.sock = socket.create_connection((host, port), timeout=10)
        self.buf = b""
        self.log = []
        self.recording = False

    def send(self, pid: int, body: bytes = b""):
        data = frame(pid, body)
        if self.recording:
            self.log.append({"direction": "serverbound", "id": pid, "hex": data.hex()})
        self.sock.sendall(data)

    def recv(self):
        while True:
            try:
                n, i = read_varint(self.buf, 0)
                if len(self.buf) >= i + n:
                    whole, body = self.buf[:i + n], self.buf[i:i + n]
                    self.buf = self.buf[i + n:]
                    pid, j = read_varint(body, 0)
                    if self.recording:
                        self.log.append({"direction": "clientbound", "id": pid, "hex": whole.hex()})
                    return pid, body[j:]
            except IndexError:
                pass
            chunk = self.sock.recv(65536)
            if not chunk:
                raise EOFError("the oracle closed the connection")
            self.buf += chunk


def main() -> int:
    host, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    o = Oracle(host, port)
    o.send(0x00, varint(PROTOCOL) + string("localhost") + port.to_bytes(2, "big") + varint(2))
    o.send(0x00, string("Notch") + bytes(range(1, 17)))
    pid, _ = o.recv()
    if pid != 0x02:
        raise SystemExit(f"expected Login Success, got {pid:#x} (white-list? online mode?)")
    o.send(0x03)   # Login Acknowledged: CONFIGURATION from here
    o.recording = True
    # Client Information: locale, view distance, chat mode, chat colours,
    # skin parts, main hand, text filtering, server listings, particles.
    o.send(0x00, string("en_us") + bytes([8]) + varint(0) + b"\x01" + bytes([0x7F])
           + varint(1) + b"\x00" + b"\x01" + varint(0))
    while True:
        pid, body = o.recv()
        if pid == 0x0F:     # Select Known Packs
            o.send(0x07, varint(1) + string("minecraft") + string("core") + string("26.3"))
        elif pid == 0x04:   # Keep Alive
            o.send(0x04, body)
        elif pid == 0x03:   # Finish Configuration
            o.send(0x03)
            break
    with open(out, "w") as f:
        for e in o.log:
            f.write(json.dumps(e) + "\n")
    print(f"{len(o.log)} frames -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
