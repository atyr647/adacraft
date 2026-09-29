# AdaCraft v1.0 Roadmap

Status: engineering plan under the frozen constitution.
This document does not amend [CONSTITUTION.md](CONSTITUTION.md).
If a step here conflicts with the constitution, the constitution wins.
Changing the version pin, the closed classified-write list, the single simulation owner, or the product/lab split requires an architecture RFC, not a roadmap edit.

Target remains exactly Minecraft Java Edition 26.3, protocol 777, data version 5023.
Java 25 is a test-lab oracle runtime only.

## How work is sequenced

The constitution's phase plan (section 77) starts at protocol code.
The closing instruction of the constitution, and the version-pin correction in front of it, add a gate in front of that plan:

1. Pin the 26.3 artifacts.
2. Generate protocol and registry data from those artifacts.
3. Write `PROTOCOL.md` and `KERNEL.md`.
4. Only then implement.

Do not carry forward a 1.21.1 / protocol 767 / data version 3955 scaffold.
Do not transcribe packet ids, registries, tags, block states, or component layouts from a 1.21.x codebase or from memory.
26.3 is data-driven. The tables are an output of the pin, not a design choice.

Three rules are the review checklist on every change:

1. Authority. Untrusted ingress never directly mutates authoritative simulation state.
2. Ownership. The v1 simulation owner exclusively owns authoritative world mutation.
3. Development. Correct first. Fast second. Parallel third.

## Ship line

v1.0 is the section 78 release gate, reached at the end of Phase 8.

All of these must pass. The gate is mandatory:

| Gate | Pass condition |
|---|---|
| C0 | Unmodified 26.3 client joins, receives terrain, moves, stays alive on keepalive, disconnects cleanly |
| C1 | Survival loop: break, place, inventory, components, crafting, containers, health, hunger, damage, death, respawn, save, relog, basic entities, core commands, permissions |
| SPARK | Section 72 proof obligations discharged on the code that shipped |
| Fuzz | Protocol, NBT, and Data Component parsers reject malformed input without corrupting authoritative state |
| Anvil | Read and write a pinned-version world; oracle can reopen AdaCraft's save |
| Differential | Authoritative state matches the 26.3 oracle on the corpus. Wire equality is not the initial oracle |
| Crash recovery | A failed save cannot look like a successful commit |
| Load | Stress test passes with the single simulation owner intact |
| Performance | 50 ms tick budget reported as average, p95, p99, and maximum. Average alone is not a pass |

Phase 9 (native extensions) is inside the v1 architecture and outside the v1.0 gate.
Section 58: extensions are not required for the C1 release.
Do not hold the release on them, and do not start them before the gate is green.

C2 and C3 are deferred. They are not partial credit toward the gate.

## What is not in this roadmap

Forbidden to arrive as incremental scope (constitution section 79):

Bukkit, Spigot, Paper, a JVM, JNI, Java plugins, Forth, a scripting VM, hot reload, a multi-version protocol core, multi-region authoritative mutation, a custom client, a custom entity ecosystem, world-generation parity, a C2 parity claim, a C3 / full-vanilla claim.

Also forbidden in practice:

- a second registry (client ids, engine ids, and kernel ids must be the same tables)
- NBT as the runtime model of an ordinary `ItemStack`
- `Try_Spawn_Item` or any new `Try_*` promoted because it "feels important"
- one OS thread per player
- TLS substituted for the pinned login encryption
- packet-to-`Chunk.Set_Block` shortcuts, including temporary ones
- workers writing live world state, including lighting, chunk load, and save
- declaring vanilla compatibility instead of demonstrating C0/C1

## Repository shape

Product and laboratory are different trees. The shipped executable links only the product tree.

```text
CONSTITUTION.md          frozen
ROADMAP.md               this plan
docs/PROTOCOL.md         next document
docs/KERNEL.md           next document
docs/TICK.md             written later, from the oracle, during Phase 4b–7
pin/26.3.toml            protocol, data version, jar hashes, oracle Java
generated/               registries, tags, packet ids, block states, components
src/                     Ada/SPARK server, package split per constitution section 76
lab/                     Java 25 + official 26.3 server.jar + differential harness
```

`lab/` may launch the official server. `src/` never does.
A product build must succeed on a machine with no Java installed.
CI is two jobs: `product` (no JDK) and `lab` (JDK 25, not on the release-binary path).

Package separation follows constitution section 76: protocol, network, auth, registry, components, kernel, world, chunks, blocks, entities, players, inventory, commands, physics, ai, redstone, fluids, lighting, persistence, scheduler, extensions, diagnostics, tests, differential, tools.
The Ada package names may differ. Those boundaries may not.
`extensions/` stays empty through the v1.0 gate.

## Milestone 0 — Pin and specify

This milestone is in front of Phase 1. No server gameplay code lands here.
An extractor and an empty Alire skeleton may land, because the two documents depend on the extractor.

### 0.1 Pin the artifacts

`pin/26.3.toml` records:

- Minecraft Java Edition 26.3
- protocol 777
- data version 5023
- SHA-256 of the official server jar used as the oracle
- SHA-256 of the client artifact used to generate protocol and registry data
- oracle runtime: Java 25
- the command the lab uses to launch the oracle

The extractor refuses to run if the bytes on disk do not match the pin.
A unit test fails if 767 or 3955 is recorded as the target.

### 0.2 Generate the tables

One tool reads the pinned artifacts and emits the single registry universe:

- packet ids, both directions, by protocol state
- registries the configuration phase must sync
- tags
- block states
- items and their data-component layouts
- known packs the 26.3 client expects
- command-tree nodes required for C1, once that slice is generated

Output lives in `generated/` with a provenance header: pin hash, tool version, data version, protocol.
Hand-editing generated files is a bug.
The server, the kernel, and the wire codec all import this output.
There is no parallel hand-maintained id list.

### 0.3 `docs/PROTOCOL.md`

Normative for protocol 777. Packet numbers in it are copied from `generated/`, not invented.

Must be written before the codec it describes:

- state machine: `HANDSHAKE`, `STATUS`, `LOGIN`, `CONFIGURATION`, `PLAY`
- which packets are legal in which state and direction; everything else is rejected
- frame layout, packet length, packet id, payload bounds
- VarInt and VarLong, including overlong-encoding rejection
- no unchecked buffer access
- compression framing and the rule that the compressor cannot see world state
- login encryption for this release: RSA key exchange, encryption request/response, session authentication, shared secret, AES/CFB8. Not TLS. Crypto is a well-tested native library, not a home-grown cipher
- online versus offline mode, and the offline UUID rule (deterministic, never treated as an online identity)
- configuration as its own state: known packs, registry data, tags, required brand/plugin-message behavior, transition to play
- C0 play packets needed for spawn, chunks, movement correction, keepalive, and disconnect
- translation rule: wire types are not world types

Phase 1 may start when framing, the state machine, and the generated id path are specified, and the C0 handshake/status packets are fully specified.
Phase 2 may not start until login, encryption, compression, and configuration are specified in this file.
Phase 4b may not start until the C0/C1 play packets it sends are specified.

C2/C3 packets can be listed in the generated catalog and marked deferred. They are not implemented.

### 0.4 `docs/KERNEL.md`

Normative signatures for the closed set:

`Try_Move`, `Try_Break_Block`, `Try_Place_Block`, `Try_Inventory_Transaction`, `Try_Execute_Command`, `Try_Chunk_Transition`, `Try_Retire_Handle`, `Try_Save`, `Try_Set_Permission`.

For each operation the document fixes:

- Ada signature, including the explicit success/failure result
- preconditions and postconditions
- the authority domain
- failure means `State_after = State_before` for that domain, with no partial commit
- what the simulation is allowed to mutate afterward, on success only

Also fixed here, before any body is written:

- generation-checked handles; retirement increments the generation; stale handles reject
- block break includes its drops and resulting item/entity creation. There is no `Try_Spawn_Item`
- inventory conservation for ordinary move/split/merge, and the exceptions that are explicit gameplay rules
- stack limits come from the item definition, never a hardcoded 64
- `Try_Save` owns the snapshot/commit transition; a failed durability step is not a successful commit
- permission mutation is only startup configuration or `Try_Set_Permission`
- the section 72 proof obligations, listed per operation, marked undischarged until Phase 6

`KERNEL.md` lands before Phase 1 code so the implementation cannot grow a side door that the kernel then has to bless.

### Milestone 0 exit

- Pin hashes checked in and verified locally against the jars
- Generated tables build and carry data version 5023 / protocol 777
- `PROTOCOL.md` and `KERNEL.md` merged
- A reader can see that both documents cite the constitution and do not add a tenth classified write
- Product tree still has no Java dependency

## Phase 1 — Protocol foundation

No gameplay.

Build the native codec in SPARK-friendly Ada from the start: bounded decoding, no unchecked access, overlong VarInt/VarLong rejected.
TCP accept, frame decoder, packet encoder/decoder, state machine.
Golden-corpus runner exists and has handshake and framing cases.
Initial differential-driver skeleton exists. It does not claim to compare worlds yet.
Fuzz VarInt, VarLong, and framing. Malformed input rejects.

Exit: round-trip tests for every packet whose specification is marked Phase 1, illegal state transitions rejected, fuzz target running in CI, decoder free of obvious buffer over-read by construction.
Proofs may still be assumed; the code must already be in the shape Phase 6 can prove.
Do not put world arrays in the protocol packages.

## Phase 2 — Login and configuration

Status, handshake, login, online authentication, RSA, AES/CFB8, compression, configuration, known packs, registry data, tags, transition to play.

The registry initialized here is the registry. Later phases are not allowed to introduce their own.

This phase ends at **C0-protocol**, which is not C0.
A vanilla 26.3 client can complete configuration and enter play.
Keepalive and disconnect work.
Spawn and real chunks are not required yet.
Offline mode is a configuration switch with its own UUID tests.

Cryptography links a maintained library that already implements the primitives the protocol requires.
Do not invent RSA or AES.

Exit: C0-protocol against an unmodified client; session-auth tests for online mode; compression bounds tests; registry bytes sent to the client come from `generated/`.

## Phase 3 — Persistence

Anvil, for the pinned version: region files, chunk NBT, player data, entity data, world metadata.
NBT parser enforces size, depth, type, and allocation limits, and rejects malformed input.
Runtime items are still not NBT trees. NBT is a serialization format where 26.3 uses it.

Chunk load path is fixed:

disk → worker decode → simulation owner integrates → authoritative world.

Save path is fixed:

simulation owner snapshots → workers serialize that snapshot → temporary storage → durability → atomic commit.

Startup recovers to the last valid commit.
A half-written region plus a success flag must be impossible.

World generation parity is out of scope.
AdaCraft must open, simulate, modify, save, and reopen an existing 26.3 world.
Missing chunks stay unloaded. A generator interface may exist and do nothing.

Exit: a world saved by the 26.3 oracle opens; AdaCraft saves it; the oracle opens the result; crash injection during commit rolls back; NBT fuzz rejects without a partial world.

## Phase 4a — Authority boundary, unproven

Implement every `Try_*` from `KERNEL.md`.
Bodies may be incomplete. Signatures, failure behavior, and visibility may not be.
On `False`, executable tests show the authority domain unchanged.
This is the test that keeps the later proof honest. It is not a substitute for the proof.

Ada visibility enforces the ingress rule.
The protocol and network packages cannot name the world-mutation operations.
There is no packet-facing `Set_Block`.
Formal proof is still allowed to wait. The boundary is not.

Exit: the nine operations exist, rejected operations leave state unchanged under test, and a dependency check fails if protocol code withs the world store.

## Phase 4b — Basic gameplay

One simulation owner.
Workers still do not write world state.

Implement player creation, movement as a request, collision, `Try_Break_Block` (including drops), `Try_Place_Block` as one commit of block plus item changes, compact block state, basic entities, handle allocation, and authoritative position correction.

Movement the client sends is not truth.
A rejected move leaves position unchanged, and the server may correct the client.

Start the tick loop. Its order is not invented in the abstract.
Observe the oracle and record the order in `docs/TICK.md`.
That file becomes part of the behavioral specification (constitution section 46).
Thread timing must not be observable as gameplay.

Land the section 52 counters now, even if the numbers are poor.
Phase 8 is not allowed to be the first time the server can report MSPT.

**C0 checkpoint** is here, not at Phase 2.
Join, configuration, spawn, chunk delivery, basic movement, keepalive, disconnect.

Exit: C0 pass against an unmodified 26.3 client, on a world loaded in Phase 3, with differential comparison of player position after accepted and rejected moves.

## Phase 5 — Items and inventory

`ItemStack` is item type, count, and a typed component set.
The registry from Phase 2 decides which components an item may carry.
The same representation feeds inventory, crafting, commands, equipment, serialization, encoding, comparison, and mutation.

`Try_Inventory_Transaction` is the path for externally initiated inventory changes: slots, cursor, pickup, place, split, merge, swap, crafting, containers, equipment, component edits.
Ordinary transfers conserve counts.
Negative counts, foreign slots, illegal components, and oversize stacks are failures and do not partially apply.
Maximum stack size is data, not 64.

Exit: conservation tests, component-rejection tests, container and crafting coverage required by C1, and no NBT object as the live item model.

## Phase 6 — SPARK proof

Prove the boundary that already exists. Do not reshape it.

Required (constitution section 72):

- protocol decoder: no buffer over-read, no invalid indexing, bounded decoding, no runtime errors
- handles: generation check, stale rejection, retirement
- inventory: conservation, bounds, slot validity, component validity, no partial transaction
- authorization: an unauthorized operation cannot commit
- classified writes: failure preserves authoritative state
- persistence: the save-commit state machine holds its invariants

The simulation engine is not proved.
Physics, AI, redstone, fluids, and lighting stay Ada.

`gnatprove` runs in the product CI job.
A proof failure is a red build, not a warning to be waived in prose.
Assumptions left open have to be named in `KERNEL.md` and eliminated before the release gate, not papered over.

Exit: the section 72 obligations are discharged on the Phase 5 tree.

## Phase 7 — C1 survival

Health, hunger, damage, death, respawn, basic entities, commands, permissions, persistence across relog, and the remaining C1 mechanics.

Commands are parsed into typed values and authorized through the authority layer.
v1 includes the C1 survival and administration set, including the constitution's examples (`/tp`, `/gamemode`, `/give`, `/kill`, `/teleport`, `/time`, `/weather`, `/difficulty`, `/setworldspawn`) plus whatever else the C1 scenarios actually require.
The exact tree comes from the 26.3 generated data.
The client receives command metadata for completion and permission-aware visibility.
The wire tree and the internal typed command are different types.

No new classified operation is added in this phase.
If a mechanic cannot be expressed as simulation-owned mutation or as one of the nine `Try_*` operations, stop and write an RFC.

Re-run the Phase 6 proofs after C1 behavior lands.
They still have to pass.

**C1 checkpoint** is here.
Differential comparison is on state: position, health, inventory, components, block state, entity state, chunk state, player data after relog.
Packet-byte equality is a later, selective check (login, configuration, registry, known packs, keepalive, chunks, position correction, inventory, disconnect), not the survival oracle.

Exit: C1 scenarios pass against an unmodified client and against the oracle.

## Phase 8 — Optimization

The harness already exists. This phase tunes. It does not begin testing.

Profile before changing structure.
Legal targets: network syscalls and copies, packet processing, allocation on the hot path, chunk access, entity iteration, serialization, compression, inventory, tick-phase time.

Prefer pools, arenas, fixed-capacity containers, recycling, and contiguous layout where a profile says the cost is real.
Do not rip out an abstraction because it looks abstract.
Do not "optimize" by letting workers write the world, by collapsing the authority boundary, or by skipping validation.

Performance pass condition is the tail, not the mean: average, p95, p99, and maximum tick time, inside the 50 ms budget under the stated load test.
Also report the section 52 counters so a regression is visible after release.

Exit: section 78 performance line is green, and C0, C1, proofs, fuzz, Anvil, differential, and crash tests are still green on the same commit.

## v1.0 tag

Tag only on a commit where every section 78 row is green on that commit.
Not on a commit that was green last week.
Not with a waived proof, a skipped fuzz target, or an average MSPT and no tail.

The tag notes the pin: 26.3, protocol 777, data version 5023, and the jar hashes from `pin/26.3.toml`.

## Phase 9 — Native extensions, after the tag

Not a v1.0 blocker.

Extension API, static linking or native shared libraries loaded at startup, lifecycle, capabilities, commands, server services, documented contracts.
No hot reload.
No second language.
Failed initialization leaves no partial authoritative state.
Extensions see typed values and handles.
They do not see chunk arrays, allocators, registry memory, scheduler internals, or raw authoritative pointers.

## Cross-cutting, from the milestone that introduces them

| Workstream | Starts | Rule |
|---|---|---|
| Golden corpus | Phase 1 | Every protocol regression adds a case |
| Fuzzing | Phase 1, extended as each parser appears | Malformed input rejects; authoritative state unchanged |
| Differential lab | Driver in Phase 1, state comparisons from Phase 4b | Compare state first. Do not fail the build on packet order, timestamps, or entity id allocation |
| Instrumentation | Tick loop in Phase 4b | Phase 8 consumes counters; it does not invent them |
| Single registry | Milestone 0 | Generated once, imported everywhere |
| SPARK shape | First codec and first `Try_*` | Phase 6 discharges proofs; it does not rewrite the API |
| Crash-safe save | Phase 3 | Re-tested at the release gate, including under load |

## Dependency order

```text
M0 pin + generated tables
        │
        ├── docs/PROTOCOL.md
        └── docs/KERNEL.md
                │
                ▼
             Phase 1 codec
                │
                ▼
             Phase 2 login / configuration / registry
                │
                ▼
             Phase 3 Anvil
                │
                ▼
             Phase 4a Try_* boundary
                │
                ▼
             Phase 4b gameplay + C0 + docs/TICK.md
                │
                ▼
             Phase 5 items / inventory
                │
                ▼
             Phase 6 proofs
                │
                ▼
             Phase 7 C1
                │
                ▼
             Phase 8 optimize
                │
                ▼
             v1.0 tag
                │
                ▼
             Phase 9 extensions
```

Phases are not a license to skip ahead.
Phase 5 inventory does not start with a direct slot write "until the kernel lands."
Phase 8 does not start before the differential suite exists.

## First implementation tasks

In order, after this roadmap:

1. Add `pin/26.3.toml` and the extractor. Fail closed on hash mismatch. Record protocol 777 and data version 5023.
2. Emit `generated/` for packet ids, registries, tags, block states, items, and components. Provenance header required.
3. Write `docs/PROTOCOL.md` for framing, the state machine, and the C0 handshake/status surface, with ids included from `generated/`.
4. Write `docs/KERNEL.md` for all nine operations, failure semantics, handles, and the proof list.
5. Finish the rest of `PROTOCOL.md` through configuration before any login code.
6. Alire project for `src/` whose build does not invoke Java. Empty packages matching section 76. `lab/` is a separate project.
7. SPARK VarInt/VarLong plus frame decoder, with unit tests and a fuzz target.
8. State machine that rejects a packet in the wrong state or direction.
9. Golden-corpus runner, and only then the first real handshake cases.
10. Lab launcher for the official 26.3 jar on Java 25, not linked into the server.

No task on this list adds a block, an entity, or a world mutation API.

## Risk register

| Risk | Why it happens | What to do |
|---|---|---|
| 1.21.x ids leak in | An old scaffold is convenient | Pin hashes, generate tables, test that 767/3955 are not the target |
| Two registries | Protocol, engine, and kernel each "just need a map" | One generated source, imported |
| SPARK becomes the game | Every dust update or entity step calls the kernel | Classified list is closed. Simulation mutates what it owns |
| Boundary added late | Gameplay is more fun than `Try_*` | `KERNEL.md` and Phase 4a before richer play. Visibility forbids `Set_Block` from packets |
| Proof rewrite | Contracts designed after the code calcified | Signatures and postconditions in Milestone 0; proofs in Phase 6 |
| Save lies | Success returned before the rename is durable | `Try_Save` state machine; crash injection in Phase 3 and again at the gate |
| Workers race the world | Chunk I/O or lighting writes in place | Workers return results. Only the simulation owner commits |
| Offline UUID looks online | A missing auth branch defaults the wrong way | Explicit mode. Tests that offline ids never pass an online check |
| Differential noise | Packet order and entity ids differ harmlessly | State oracle first. Selective wire checks only after state matches |
| Java leaks into the binary | Lab code shares a project with the server | Separate trees, separate CI jobs, product build has no JDK |
| C2 sneaks into v1 | Redstone and fluids are nearby | They may exist as simulation code paths; parity is not a v1 claim and is not scheduled before the tag |
| Hot path allocates without bound | NBT, chunks, or packets build unbounded trees | Size, depth, and allocation limits at every external parser |
| Optimization breaks the rules | Tail latency is bad and a lock around the world "fixes" it | Profile first. Ownership rule outranks the number |

## RFC triggers

Stop and write an architecture RFC before:

- adding or renaming a classified operation
- moving authoritative mutation off the single simulation owner
- supporting any protocol other than 777
- putting a JVM, JNI, or plugin loader on the server path
- introducing a scripting language
- claiming C2 or C3 parity
- making world-generation parity a v1.0 requirement
- hot-reloading gameplay code

A roadmap revision that quietly does any of those is out of order.
The constitution stays the constitution.
