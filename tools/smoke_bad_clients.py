#!/usr/bin/env python3
"""Smoke probe: server survives bad clients.

Starts the built server binary on an ephemeral free port, waits for
listen, then runs raw-socket reset / garbage / half-packet / idle /
many(=64) plus status-while-idle probes, asserting the server is still
alive plus a fresh status+ping with matching payload after each.

Not wired into `make test` (run manually):
    python3 tools/smoke_bad_clients.py [--bin bin/adacraft] [--timeout 15]
"""

import argparse
import os
import socket
import struct
import subprocess
import sys
import time

STATUS_JSON_MARKER = b'"protocol":777'


def encode_varint(value):
    out = bytearray()
    v = value & 0xFFFFFFFF
    for _ in range(5):
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            break
    return bytes(out)


def frame(packet_id, payload=b""):
    body = encode_varint(packet_id) + payload
    return encode_varint(len(body)) + body


def encode_string(s):
    b = s.encode("utf-8")
    return encode_varint(len(b)) + b


def handshake_payload(intent=1, proto=777, addr="localhost", port=25565):
    p = encode_varint(proto) + encode_string(addr) + struct.pack(">H", port)
    p += encode_varint(intent)
    return p


def recv_exact(sock, n, deadline):
    buf = b""
    while len(buf) < n:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("recv timed out")
        sock.settimeout(remaining)
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("eof")
        buf += chunk
    return buf


def read_frame(sock, timeout=5.0):
    deadline = time.monotonic() + timeout
    # VarInt length prefix, at most 3 bytes per protocol limits.
    length = 0
    shift = 0
    for i in range(3):
        b = recv_exact(sock, 1, deadline)[0]
        length |= (b & 0x7F) << shift
        shift += 7
        if not (b & 0x80):
            break
        if i == 2:
            raise ValueError("overlong length prefix")
    else:
        raise ValueError("no length terminator")
    if length <= 0 or length > 2097151:
        raise ValueError("bad length %d" % length)
    body = recv_exact(sock, length, deadline)
    # Decode packet id varint (<=5 bytes).
    pid = 0
    shift = 0
    pos = 0
    for i in range(5):
        if pos >= len(body):
            raise ValueError("truncated packet id")
        b = body[pos]
        pos += 1
        pid |= (b & 0x7F) << shift
        shift += 7
        if not (b & 0x80):
            break
        if i == 4:
            raise ValueError("overlong packet id")
    return pid, body[pos:]


def status_and_ping(port, timeout=5.0, payload=0x0102030405060708):
    """Full healthy exchange: handshake(status) + request + ping."""
    s = socket.create_connection(("127.0.0.1", port), timeout=timeout)
    try:
        s.settimeout(timeout)
        s.sendall(frame(0, handshake_payload(intent=1, port=port)))
        s.sendall(frame(0, b""))
        pid, body = read_frame(s, timeout)
        assert pid == 0, "expected status response id 0, got %r" % pid
        assert STATUS_JSON_MARKER in body, "status json missing 777: %r" % body[:120]
        ping_bytes = struct.pack(">Q", payload)
        s.sendall(frame(1, ping_bytes))
        pid2, body2 = read_frame(s, timeout)
        assert pid2 == 1, "expected pong id 1, got %r" % pid2
        assert body2 == ping_bytes, "pong payload mismatch"
    finally:
        try:
            s.close()
        except OSError:
            pass


def wait_for_listen(port, proc, timeout=10.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError("server exited early with %s" % proc.poll())
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=1.0)
            s.close()
            return
        except OSError:
            time.sleep(0.1)
    raise TimeoutError("server did not listen on %d" % port)


def find_server_binary(explicit):
    if explicit:
        return explicit
    for cand in ("bin/adacraft_server", "bin/adacraft"):
        if os.path.isfile(cand) and os.access(cand, os.X_OK):
            return cand
    return "bin/adacraft"


def probe_reset(port):
    s = socket.create_connection(("127.0.0.1", port), timeout=5.0)
    # RST: linger-zero close.
    try:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER,
                     struct.pack("ii", 1, 0))
    except OSError:
        pass
    s.close()


def probe_garbage(port):
    vectors = [
        b"\xff\xff\xff\xff\xff\x01\x00",          # overlong VarInt
        encode_varint(2097152) + b"\x00",          # over-max declared length
        frame(1, handshake_payload(intent=1)),     # unknown handshake id
        frame(0, handshake_payload(intent=0)),     # invalid next-state 0
        frame(0, handshake_payload(intent=4)),     # invalid next-state 4
        frame(0, handshake_payload(intent=1)[:-1]),  # truncated field
        b"\x00",                                  # zero-length frame
        os.urandom(32),
    ]
    for v in vectors:
        s = socket.create_connection(("127.0.0.1", port), timeout=5.0)
        try:
            s.settimeout(5.0)
            try:
                s.sendall(v)
            except OSError:
                pass
            time.sleep(0.1)
        finally:
            try:
                s.close()
            except OSError:
                pass


def probe_half_packet(port):
    full = frame(0, handshake_payload(intent=1, port=port))
    half = full[:2]
    s = socket.create_connection(("127.0.0.1", port), timeout=5.0)
    try:
        s.sendall(half)
        time.sleep(0.5)
        # Go silent with the half frame pending; leave it open briefly
        # so the server holds a stalled mid-frame conn, then close.
        time.sleep(0.5)
    finally:
        try:
            s.close()
        except OSError:
            pass


def probe_idle(port):
    s = socket.create_connection(("127.0.0.1", port), timeout=5.0)
    try:
        time.sleep(1.0)  # fully idle, zero bytes
    finally:
        try:
            s.close()
        except OSError:
            pass


def probe_many(port, n=64):
    conns = []
    try:
        for _ in range(n):
            s = socket.create_connection(("127.0.0.1", port), timeout=5.0)
            s.settimeout(5.0)
            conns.append(s)
        # While all 64 sit idle, a fresh client must still get status+ping.
        status_and_ping(port)
    finally:
        for s in conns:
            try:
                s.close()
            except OSError:
                pass


def probe_status_while_idle(port):
    idle = socket.create_connection(("127.0.0.1", port), timeout=5.0)
    stalled = socket.create_connection(("127.0.0.1", port), timeout=5.0)
    try:
        full = frame(0, handshake_payload(intent=1, port=port))
        stalled.sendall(full[:2])  # stalled mid-frame
        time.sleep(0.3)
        # A second client completes the whole exchange well before any
        # 30s read timeout fires on the idle/stalled conns.
        status_and_ping(port)
    finally:
        for s in (idle, stalled):
            try:
                s.close()
            except OSError:
                pass


def main():
    ap = argparse.ArgumentParser(description="bad-client smoke probe")
    ap.add_argument("--bin", default=None)
    ap.add_argument("--timeout", type=float, default=5.0)
    args = ap.parse_args()
    binary = find_server_binary(args.bin)
    if not (os.path.isfile(binary) and os.access(binary, os.X_OK)):
        print("server binary not found: %s (build first)" % binary,
              file=sys.stderr)
        return 2

    # Ephemeral free port: bind port 0, read it back, close, reuse.
    tmp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    tmp.bind(("127.0.0.1", 0))
    free_port = tmp.getsockname()[1]
    tmp.close()

    proc = subprocess.Popen([binary, str(free_port)],
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT,
                            text=True)
    try:
        wait_for_listen(free_port, proc)
        status_and_ping(free_port, args.timeout)
        print("PASS baseline status+ping")

        probe_reset(free_port)
        status_and_ping(free_port, args.timeout)
        print("PASS reset")

        probe_garbage(free_port)
        status_and_ping(free_port, args.timeout)
        print("PASS garbage")

        probe_half_packet(free_port)
        status_and_ping(free_port, args.timeout)
        print("PASS half-packet")

        probe_idle(free_port)
        status_and_ping(free_port, args.timeout)
        print("PASS idle")

        probe_many(free_port, 64)
        print("PASS many-64")

        probe_status_while_idle(free_port)
        print("PASS status-while-idle")

        if proc.poll() is not None:
            print("FAIL: server exited mid-probes", file=sys.stderr)
            return 1
        print("SMOKE OK: server survived all bad-client probes")
        return 0
    except Exception as e:
        print("FAIL: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 1
    finally:
        try:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
