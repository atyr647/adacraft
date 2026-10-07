# Differential driver

Runs the same Golden Corpus scenarios against an **oracle** (the official Minecraft 26.3 `server.jar`) and a **subject** (AdaCraft), records what each one sends back, and compares the two observation sequences. It is a lab tool: nothing shipped depends on it, and it is not part of `make` / `make test`.

**The driver starts neither server.** You start the oracle and the subject yourself; the driver only connects to the `host:port` you give it.

## Prerequisites

- GNAT with `gprbuild`.
- A running oracle (`server.jar`, Java 25) configured with:
  - `online-mode=false`
  - `network-compression-threshold=-1`
- A running AdaCraft subject (`make && ./bin/adacraft 25565`, or another port).
- Compression, encryption and authentication are not exercised.

## Protocol packages

No protocol library GPR exists in the repository, so `differential/differential.gpr` compiles `src/protocol/` and `generated/` directly as source directories. It never depends on `adacraft.gpr`, and nothing in `adacraft.gpr` depends on it.

## Build and test

```text
make differential        # builds differential/bin/differential_driver
make differential-test   # builds and runs the tests (loopback only, no Java)
```

## Invoke

```text
differential/bin/differential_driver --oracle HOST:PORT --subject HOST:PORT \
    [--scenario NAME] [--timeout-ms N] CORPUS_PATH
```

- `CORPUS_PATH` is a directory of `*.scenario` files (for example `tests/corpus`).
- `--scenario NAME` runs only that scenario.
- `--timeout-ms N` is the connect and receive timeout (default 5000).

Each scenario uses a fresh connection to each endpoint. The driver sends all serverbound steps, then reads until the peer closes, a timeout, a malformed frame, or the observation bound.

## The report

Plain text on stdout, deterministic: two runs against identical endpoint behavior give identical output. No timestamps or addresses appear.

- `PASS name` — both endpoints produced the same observation sequence.
- `DIFF name` — the sequences differ. The report gives the first differing 1-based index and both observations (`<end>` when one sequence ended earlier).
- `ERROR name: reason` — the scenario could not be run or compared (for example the oracle was unreachable, or a step cannot be encoded). An error is never reported as a DIFF.
- `SUMMARY pass=N diff=N error=N` — final line.

An observation is the protocol state at receipt, direction (`clientbound`) and packet ID, or an event: connect-failed, closed-by-peer, receive-timeout, malformed (with reason), invalid-in-state. Payload bytes are never compared; wire equality is not required.

## Exit status

- `0` — all scenarios pass.
- `1` — some DIFF, no ERROR.
- `2` — any ERROR, or an argument or corpus failure. Argument, corpus and `--scenario` problems are diagnosed on stderr before any socket is opened.
