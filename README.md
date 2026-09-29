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

This tree is the Milestone 0 pin plus the Phase 1 codec, status handling, offline-login identity check, and the Phase 4a authority boundary.

A 26.3 client can complete a server-list status ping and see protocol 777. Login checks the offline UUID derived from the player name and then disconnects. Play, chunks, encryption, and compression are not implemented. That is the constitution's order, not a temporary shortcut around it.

```text
make test
make
./bin/adacraft 25565
```

`make test` needs GNAT 2022 on `PATH` (`gnatmake`). Java is not required to build or run the tests. Java 25 is required only to regenerate `generated/26.3/reports` from the pinned jar.

Packet ids are generated. Do not edit `generated/adacraft-protocol-ids.ads` by hand.
