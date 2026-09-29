# AdaCraft

Native high-assurance Minecraft: Java Edition server, written in Ada/SPARK.

v1.0 is pinned to **Minecraft Java Edition 26.3**, **protocol 777**, **data version 5023**.

The shipped server does not run on a JVM and does not embed Mojang's server.
The official 26.3 `server.jar` is a test-lab oracle only. That oracle needs Java 25. AdaCraft does not.

| Document | What it is |
|---|---|
| [CONSTITUTION.md](CONSTITUTION.md) | Frozen v1.0 specification. Do not edit in place. |
| [ROADMAP.md](ROADMAP.md) | Engineering sequence under the constitution. It does not amend it. |

Next documents, before implementation: `docs/PROTOCOL.md` and `docs/KERNEL.md`.

There is no 1.21.x target and no protocol 767 / data version 3955 scaffold.
Protocol and registry data are generated from the pinned 26.3 artifacts.
