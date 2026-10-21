# AGENTS.md

Notes for an AI agent (or a person) working in this repository.

- **CONSTITUTION.md** is the frozen spec. ROADMAP.md says what comes next.
  docs/PROTOCOL.md says what the server does on the wire, state by state.
- **Bytes come from the oracle.** Don't hand-encode packets. Follow
  docs/ORACLE.md: record the official server, generate constants, prove
  the result byte for byte. This is the fastest route as well as the safest.
- **Generated files** (`generated/`, `tests/corpus/*-core-pack*`,
  `tests/corpus/play-opening.scenario`) are never edited by hand: change
  the extractor and regenerate. `make test` checks they match.
- **Done means** `make test` passes (it rebuilds what changed, checks the
  generated files, the boundaries, the goldens and the live TCP tests), and
  for protocol work the differential in docs/ORACLE.md step 6 exits 0.
- **Boundaries**: `src/protocol` and `src/network` never name the kernel or
  the world (`tools/check_boundaries.py`).
- Build: `make` (gnatmake, Ada 2022). Tests: `make test`.
