# AdaCraft

Native Minecraft: Java Edition server in Ada/SPARK.

v1.0 is pinned to **26.3**, protocol **777**, data version **5023**. The binary does not link a JVM. The official `server.jar` is a lab oracle only.

| Document | Role |
|---|---|
| [CONSTITUTION.md](CONSTITUTION.md) | Frozen v1.0 specification. |
| [ROADMAP.md](ROADMAP.md) | Sequence under the constitution. |
| [docs/PROTOCOL.md](docs/PROTOCOL.md) | Wire rules for protocol 777. |
| [docs/KERNEL.md](docs/KERNEL.md) | The nine authority operations. |
| [pin/26.3.toml](pin/26.3.toml) | Jar hashes and the version pin. |
| [generated/26.3/](generated/26.3/PROVENANCE.md) | Packet, registry, block, and command reports from the 26.3 data generator. |

## What runs

This tree is the Milestone 0 pin plus the Phase 1 codec, status handling, login-disconnect handling, and the Phase 4a authority boundary.

A 26.3 client can complete a server-list status ping and see protocol 777. Handshake routes next-state 1 to Status and next-state 2 to Login.

Login behaves as the binary does, shown by `tests/test_login_server.adb` driving the built `bin/adacraft` over real TCP: a Handshake with next state Login followed by a well-formed Login Start is answered with one correctly framed protocol 777 Login Disconnect carrying a human-readable reason, after which the server closes only that connection. A Handshake with next state Login and a protocol version other than 777 is answered with Login Disconnect carrying a reason, not a silent close. A packet that is invalid in the Login state closes that connection with no reply. That is the constitution's order, not a temporary shortcut around it.

Not implemented: encryption, online authentication, compression, configuration, known packs, registry data / tags, and the play transition. There is no online login, no Login Success path, and no configuration or play handling.

The server survives bad clients: resets, garbage handshakes, half-packets, and idle connections each close only that connection while others still get status plus ping. Every read is governed by a single 30s read timeout (`Adacraft.Network.Read_Timeout`), covering fully-idle and stalled-mid-frame connections alike, as shown by `tests/test_bad_clients.adb` and the `tools/smoke_bad_clients.py` probe.

```text
make test
make
./bin/adacraft 25565
```

`make test` needs GNAT 2022 on `PATH` (`gnatmake`). Java is not required to build or run the tests. Java 25 is required only to regenerate `generated/26.3/reports` from the pinned jar.

Packet ids are generated. Do not edit `generated/adacraft-protocol-ids.ads` by hand.
