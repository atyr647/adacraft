Yes. I checked the current release before filling the pin: Minecraft Java Edition 26.3 is the current release, released September 15, 2026, with protocol 777 and data version 5023; it requires Java 25 for the oracle server. Mojang's official 26.3 release notes confirm the release and its technical changes, while the protocol/data-version mapping is independently corroborated by current version references. 

One important correction to the scaffold you pasted: the old 1.21.1 / protocol 767 / data version 3955 scaffold must not be carried forward. The frozen target is 26.3 / 777 / 5023. Also, 26.3 has substantial current data-driven changes, so the protocol and registry work should be generated directly from the pinned 26.3 artifacts rather than copied from a 1.21.x implementation. 

AdaCraft v1.0

Native High-Assurance Minecraft Java Edition Server

Status: FROZEN CONSTITUTION

Target: Minecraft: Java Edition 26.3
Protocol: 777
Data Version: 5023
Java: Java 25 is required only by the official Minecraft oracle server used by the test lab; it is not a dependency of the shipped AdaCraft server. 


---

1. Mission

AdaCraft is a native Minecraft: Java Edition server written entirely in Ada/SPARK.

Its purpose is to provide a high-performance, deterministic, robust implementation of Minecraft's server-side behavior while exposing the standard Minecraft Java Edition protocol to an unmodified vanilla client.

The shipped AdaCraft executable shall not require:

Java

a JVM

Mojang's server implementation

Bukkit

Spigot

Paper

JNI

Java plugins

a scripting VM

Forth

a custom client


The official Minecraft server.jar may be used by the development and differential-testing harness as a behavioral oracle. It is not part of AdaCraft and is never a runtime dependency.

The governing development philosophy is:

> Correct first. Fast second. Parallel third.




---

2. Version Pin

AdaCraft v1.0 targets exactly:

Minecraft Java Edition: 26.3
Protocol Version:       777
Data Version:           5023
Java Oracle Runtime:    Java 25

There is no 26.x target.

There is no 1.21.x target.

There is no snapshot target.

There is no implicit compatibility with another protocol version.

A future Minecraft release requires an explicit version-update project.

Minecraft 26.3 is the current release and uses protocol 777 and data version 5023. 


---

3. Product vs Test Laboratory

The distinction is absolute.

Shipped AdaCraft

Ada
SPARK
OS/runtime libraries

and nothing Java-specific.

Development/Test Laboratory

AdaCraft
    +
official Minecraft 26.3 server.jar
    +
Java 25
    +
protocol test driver
    +
differential harness

The official server is an oracle, not a dependency.

The test harness may launch it, send it the same scenarios supplied to AdaCraft, and compare authoritative results.

The production AdaCraft executable never launches or embeds it.


---

4. Architecture

VANILLA CLIENTS
                               │
                               ▼
                    ┌────────────────────┐
                    │   Ada Networking   │
                    └─────────┬──────────┘
                              │
                              ▼
                    ┌────────────────────┐
                    │ Protocol 777       │
                    │ Java Edition 26.3  │
                    └─────────┬──────────┘
                              │
                              ▼
                  ┌────────────────────────┐
                  │   SPARK INGRESS        │
                  │      AUTHORITY         │
                  └───────────┬────────────┘
                              │
                              ▼
                  ┌────────────────────────┐
                  │    ADA SIMULATION      │
                  │                        │
                  │ World                  │
                  │ Chunks                 │
                  │ Blocks                 │
                  │ Entities               │
                  │ Players                │
                  │ Physics                │
                  │ AI                     │
                  │ Redstone               │
                  │ Fluids                 │
                  │ Ticks                  │
                  └───────────┬────────────┘
                              │
                    classified operations
                              │
                              ▼
                  ┌────────────────────────┐
                  │ SPARK COMMIT BOUNDARY  │
                  └───────────┬────────────┘
                              │
                              ▼
                  ┌────────────────────────┐
                  │ Authoritative State    │
                  └────────────────────────┘

Supporting systems operate around this core:

┌──────────────┐
       │ Networking   │
       └──────┬───────┘
              │
 ┌────────────┼───────────────┐
 ▼            ▼               ▼
Scheduler  Persistence   Chunk Generation


---

5. Authority Philosophy

SPARK is not Minecraft.

SPARK is the protection around Minecraft's authoritative state.

The Ada simulation engine is allowed to be large, complex, and performance-oriented.

The SPARK authority layer is deliberately narrow and mathematically tractable.

The key rule is:

> Untrusted input cannot directly mutate authoritative simulation state.



And:

> Simulation may mutate state it already owns during its tick.




---

6. Simulation Ownership

AdaCraft v1 has exactly one authoritative simulation owner.

The authoritative world simulation runs on one simulation owner.

Workers do not directly write simulation-owned state.

This is deliberately stronger than merely saying "controlled ownership."

The v1 model is:

SIMULATION OWNER
                           │
          ┌────────────────┼────────────────┐
          │                │                │
        World            Entities         Players
          │                │                │
          └────────────────┼────────────────┘
                           │
                     authoritative
                        mutation

Workers may perform independent work such as:

network processing

disk I/O

compression

decompression

chunk generation

serialization

lighting calculations where isolated

preparation of read-only results


but they do not mutate simulation-owned world state.

Multi-region authoritative mutation is explicitly deferred.


---

7. Classified Writes

The following list is closed for v1.

Only these externally significant state transitions require the authority boundary:

1. Packet admission


2. Movement request


3. Block break/place


4. Inventory transaction


5. Command execution


6. Chunk residency


7. Handle retirement


8. Save commit


9. Permission mutation



Block break includes any authoritative consequences of the break operation, including block drops and resulting item/entity creation.

There is no separate Try_Spawn_Item constitutional operation.

Try_Set_Permission exists because permission mutation is explicitly classified.

No other operation may be promoted into the SPARK kernel merely because an implementer later decides it feels important.

Such changes require an architecture RFC.


---

8. Simulation-Owned Operations

The following remain inside the Ada simulation engine:

physics

AI

redstone

fluids

block updates

scheduled ticks

crops

mob behavior

pathfinding

lighting

environmental simulation

ordinary entity movement caused by simulation

ordinary world-state evolution


The simulation may freely mutate state that it already owns during its tick.

It does not invoke the authority boundary for every internal simulation operation.

This prevents SPARK from becoming a performance bottleneck or accidentally becoming the entire game engine.


---

9. Ingress Rule

Ingress is never permitted to access world arrays directly.

The flow is:

Packet
  ↓
Decode
  ↓
Validate
  ↓
Translate to typed request
  ↓
Try_*
  ↓
Simulation mutation

Never:

Packet
  ↓
Chunk.Set_Block(...)

This architectural restriction exists from the first implementation commit.

Formal proof may arrive later.

The boundary does not.


---

10. Try_* API

The authority package exposes typed operations.

Conceptually:

Try_Move
Try_Break_Block
Try_Place_Block
Try_Inventory_Transaction
Try_Execute_Command
Try_Chunk_Transition
Try_Retire_Handle
Try_Save
Try_Set_Permission

The actual signatures are defined by KERNEL.md.

Every operation has:

preconditions

postconditions

explicit success/failure result

defined state-preservation behavior on failure



---

11. Failure Semantics

The fundamental rule is:

> A rejected authoritative operation does not partially mutate authoritative state.



For an operation:

Try_X → False

the relevant authoritative state must remain unchanged.

Formally:

State_after = State_before

for the operation's authority domain.

This is particularly important for:

movement rejection

inventory transactions

permissions

handle operations

chunk transitions

persistence commits



---

12. Handle System

Objects with externally meaningful lifetime use generation-checked handles.

Conceptually:

type Entity_Handle is record
   ID         : Entity_Index;
   Generation : Interfaces.Unsigned_32;
end record;

A handle is valid only if:

Registry(ID).Generation = Handle.Generation

and the referenced object is live.

Retirement invalidates all outstanding handles.

Conceptually:

Try_Retire_Handle

increments the generation.

Therefore:

old handle
    ↓
generation mismatch
    ↓
reject

rather than accessing a recycled object.


---

13. Entity Identity

Entity storage is pool-oriented.

The identity of an entity is not equivalent to its physical memory address.

This permits:

object recycling

compact storage

deterministic lifetime

stale-reference detection

efficient allocation


Raw authoritative pointers are never part of the external extension or ingress contract.


---

14. Player State

Player state is internally componentized.

Conceptually:

Player
├── Identity
├── Position
├── Rotation
├── Velocity
├── Health
├── Hunger
├── Experience
├── Inventory
├── Equipment
├── Effects
├── Abilities
├── Permissions
├── Statistics
└── Session

The implementation may optimize this into data-oriented structures.

It is not required to use an object-per-player design.


---

15. Item Runtime Model

Minecraft 26.3 uses the modern Data Component model.

AdaCraft therefore represents runtime items as:

ItemStack
├── Item_Type
├── Count
└── Component_Set

not:

Item_ID
Count
NBT

Data Components are typed native Ada structures.

The registry determines which components are valid for each item.

The component representation is shared by:

inventory

crafting

commands

entity equipment

serialization

network encoding

item comparison

item mutation


The runtime item model is not an NBT tree.


---

16. NBT

NBT remains a first-class serialization format where Minecraft 26.3 actually uses it.

It is used for applicable:

world persistence

player persistence

entity persistence

block entity persistence

protocol structures that use NBT

other version-defined NBT payloads


NBT is not the runtime representation of ordinary ItemStack state.

NBT parsing must enforce:

size limits

recursion/depth limits

type validity

allocation limits

malformed-input rejection



---

17. Registry System

There is exactly one authoritative registry subsystem.

It is initialized during the protocol/configuration phase and subsequently consumed by the entire engine.

The same definitions drive:

protocol registry synchronization

items

blocks

entities

dimensions

biomes

damage types

components

tags

commands

recipes

other version-defined registries


There shall not be multiple independent representations of the Minecraft registry universe.

This prevents the classic:

client knows Item X
engine knows Item Y
kernel knows Item Z

failure mode.


---

18. Configuration Phase

Minecraft 26.3's configuration phase is a first-class protocol state.

AdaCraft implements:

configuration packets

known-packs synchronization

registry data

tags

brand/plugin-message behavior where required by the vanilla contract

transition into play


The configuration state is not treated as merely an extension of login.

The data established here becomes authoritative input to subsequent gameplay.


---

19. Protocol State Machine

The protocol state machine is version-specific to 26.3.

Conceptually:

HANDSHAKE
   │
   ├── STATUS
   │
   └── LOGIN
         │
         ▼
     CONFIGURATION
         │
         ▼
        PLAY

Every packet is valid only in its appropriate state and direction.

Invalid state transitions are rejected.


---

20. Network Framing

The protocol implementation shall provide native Ada implementations of:

VarInt

VarLong

packet length

packet ID

packet payload

bounded decoding

bounded encoding


The parser must reject malformed or overlong encodings.

No unchecked buffer access is permitted in the protocol decoder.


---

21. Compression

Minecraft's configured compression mechanism is implemented directly.

The compression layer operates on packet framing according to the pinned protocol.

Compression shall be:

bounded

streaming where beneficial

allocation-conscious

isolated from authoritative state


The compression subsystem must not have direct access to world state.


---

22. Encryption

AdaCraft implements Minecraft Java Edition's native login encryption mechanism for the pinned release.

It shall not substitute TLS for Minecraft's protocol encryption.

The implementation covers:

server public/private key handling

encryption request

encryption response

session authentication flow

shared-secret establishment

AES/CFB8 stream encryption


Cryptographic primitives should use a well-tested native cryptographic implementation rather than attempting to invent cryptography.


---

23. Authentication

Online-mode authentication follows the Minecraft Java Edition authentication/session contract for the pinned version.

The server must distinguish:

online authentication
offline/testing mode

according to explicit configuration.

Offline mode must have a deterministic UUID policy and must never accidentally be treated as authenticated online identity.


---

24. Networking Architecture

The network layer is asynchronous and event-driven.

It should not require one OS thread per player.

Conceptually:

Socket
 ↓
Receive Buffer
 ↓
Frame Decoder
 ↓
Packet Decoder
 ↓
Typed Packet
 ↓
Ingress

and:

Simulation State
 ↓
Replication Builder
 ↓
Packet Encoder
 ↓
Compression
 ↓
Encryption
 ↓
Socket

Network I/O never directly mutates world state.


---

25. Internal vs Wire Representation

Protocol structures are not world structures.

The server performs translation once at the boundary.

For example:

Wire Item
   ↓
Native ItemStack

Wire Chunk Section
   ↓
Native Chunk Section

Wire Entity Metadata
   ↓
Native Entity State

The world engine is optimized for simulation, not packet representation.


---

26. Chunk Architecture

A chunk is divided into sections and associated state.

Conceptually:

Chunk
├── Sections[]
│   ├── Block Palette
│   ├── Block Indices
│   ├── Lighting
│   └── Section Metadata
├── Block Entities
├── Entities
├── Scheduled Work
└── Metadata

The implementation should use compact representations appropriate to actual Minecraft storage patterns.

Empty/uniform sections should have extremely cheap representations.


---

27. Chunk Residency

Chunk lifecycle is authoritative.

Conceptually:

UNLOADED
   ↓
LOADING
   ↓
LOADED
   ↓
ACTIVE
   ↓
INACTIVE
   ↓
SAVING
   ↓
UNLOADED

No subsystem may operate on a chunk as active simulation state unless its residency state permits it.

Chunk transitions use the classified authority operation.


---

28. Chunk Loading

Chunk loading may occur on a worker.

The worker prepares the data.

The simulation owner integrates the resulting chunk into authoritative state.

Therefore:

disk
 ↓
worker
 ↓
decoded chunk
 ↓
simulation owner
 ↓
authoritative world

rather than allowing arbitrary disk threads to mutate the world.


---

29. Persistence

Anvil persistence is mandatory for v1.

AdaCraft must read and write the pinned version's applicable:

region files

chunks

NBT structures

player data

entity data

world metadata


A private internal representation may exist, but the externally visible world-storage contract remains compatible with the pinned Minecraft version.


---

30. Save Transaction

Saving is a classified operation.

Conceptually:

Authoritative State
       ↓
Stable Snapshot
       ↓
Serialization
       ↓
Temporary Storage
       ↓
Durability
       ↓
Atomic Commit

The simulation must not mutate the state being serialized in a way that invalidates the snapshot.

A save failure must not be reported as a successful durable commit.


---

31. Save Concurrency

The v1 rule is deliberately simple:

> The simulation owner establishes the save snapshot; workers serialize/write that snapshot.



The simulation-owned state being snapshotted cannot be concurrently mutated in a way that violates snapshot consistency.

Try_Save/Commit_Save owns the authoritative transition.


---

32. World Generation

World generation is deliberately deferred from the v1 parity requirement.

AdaCraft v1 must:

load an existing 26.3 world

simulate it

modify it

save it

reopen it correctly


Full vanilla world-generation parity is a later milestone.

The architecture nevertheless leaves room for a native Ada generator.


---

33. Block System

Blocks are registry-defined typed state.

A block instance consists conceptually of:

Block_Type
+
Block_State

rather than arbitrary objects.

Block state must remain compact because block access is among the hottest operations in the server.


---

34. Block Break

Try_Break_Block is an authoritative transaction.

It validates:

player identity

player state

world/chunk residency

target coordinates

reach

game mode

block break legality

applicable tool/state rules


On success, the simulation applies the resulting state transition, including appropriate drops.

On failure, authoritative state is unchanged.


---

35. Block Placement

Try_Place_Block validates:

player identity

held item

component state

target position

collision

placement rules

world/chunk residency

permissions

applicable block behavior


The resulting block and item changes are committed as one authoritative operation.


---

36. Movement

Movement from the client is an input request, not authoritative truth.

The flow is:

Client position request
       ↓
Try_Move
       ↓
validate
       ↓
collision / bounds / movement rules
       ↓
commit or reject

A rejected movement request leaves authoritative position unchanged.

The server may subsequently send the client authoritative position state.


---

37. Inventory System

Inventory is one of the primary SPARK proof targets.

The system handles:

slots

cursor

pickup

placement

splitting

merging

swapping

crafting

containers

equipment

component mutation


Every externally initiated inventory mutation passes through:

Try_Inventory_Transaction

or an appropriate classified operation derived from it.


---

38. Component-Aware Inventory Validation

The inventory kernel must reason about:

item type

count

stackability

maximum stack size

component compatibility

component mutations

slot validity

container validity

transaction state


It must not assume every item has maximum stack size 64.

The maximum and stacking behavior come from the actual item definition/component model.


---

39. Inventory Conservation

A successful ordinary move/split/merge operation must preserve item quantities except where the operation explicitly represents a gameplay rule that creates or destroys items.

For ordinary inventory transfers:

Source_before + Destination_before
=
Source_after + Destination_after

subject to the operation's explicit semantics.

The proof must also establish that:

counts cannot become negative

invalid slots cannot be accessed

invalid components cannot enter an item

destination limits cannot be exceeded

stale inventory state cannot commit



---

40. Entity Simulation

The entity engine is native Ada.

Entities may use a hybrid data-oriented architecture:

Dense hot columns
+
type-specific side storage
+
entity pools

Hot fields such as:

position

velocity

rotation

flags

type

generation


should be efficiently iterable.

Heterogeneous state remains in specialized storage.


---

41. Physics

Physics remains simulation-owned.

It includes:

collision

gravity

movement

projectiles

falling blocks

fluids

vehicle movement

entity interaction


Physics does not call the SPARK kernel for every internal calculation.

It commits ordinary simulation-owned state directly within the simulation owner.


---

42. AI

AI is native Ada.

Subsystems may include:

goals

targeting

navigation

pathfinding

behaviors

combat

spawning


AI does not possess authority to bypass classified operations.

For example, if AI causes an ordinary entity movement, that is simulation-owned.

If an operation requires a classified authority transition, it goes through that operation.


---

43. Redstone

Redstone is simulation-owned.

It uses specialized scheduling and propagation structures.

Potential optimization techniques include:

dirty queues

dependency tracking

compact update records

localized propagation

deterministic ordering


Redstone does not become a SPARK transaction on every dust update.


---

44. Fluids

Fluids are simulation-owned.

Their propagation must remain deterministic within the simulation owner.

Optimization should focus on:

active-cell tracking

localized updates

compact state

avoiding unnecessary full-chunk scans



---

45. Lighting

Lighting may be calculated by worker threads where the work is safely isolated from authoritative mutation.

The worker produces a result.

The simulation owner commits that result.

The worker does not directly mutate live world state.


---

46. Tick Architecture

The simulation executes a deterministic tick loop.

Conceptually:

Tick N
│
├── ingest accepted player actions
├── commands
├── player interactions
├── scheduled block work
├── block updates
├── fluids
├── entities
├── AI
├── physics
├── redstone
├── environment
├── authoritative commits
├── replication preparation
└── tick completion

The exact ordering shall be pinned against the vanilla oracle during implementation.

The phase ordering itself becomes part of the behavioral specification.


---

47. Determinism

Where Minecraft semantics require ordering, AdaCraft must define the ordering explicitly.

Thread timing must never determine gameplay.

V1 achieves this naturally through the single simulation owner.

This is one of the major reasons aggressive multi-region mutation is deferred.


---

48. Scheduler

The scheduler is an ordinary Ada subsystem.

It supports:

worker pools

asynchronous jobs

I/O tasks

background serialization

generation

compression

decompression

isolated computation


The scheduler does not own authoritative gameplay state.


---

49. Memory Management

The engine avoids unpredictable hot-path allocation.

Preferred techniques:

pools

arenas

fixed-capacity containers

object recycling

scratch allocators

bounded queues


The goal is predictable memory behavior.

AdaCraft does not use a garbage collector.


---

50. Data-Oriented Performance

The implementation should favor:

contiguous memory

compact representations

cache locality

reduced pointer chasing

batch processing

predictable branches

specialized hot loops


However, abstractions should not be removed merely because they look abstract.

Performance decisions must be supported by profiling.


---

51. Networking Performance

The network stack should minimize:

system calls

copies

allocations

context switches

lock contention


Packet batching and buffer reuse should be used where appropriate.

Zero-copy is an optimization, not a religion.

The goal is:

> minimum necessary data movement.




---

52. Performance Instrumentation

Performance instrumentation is part of the server.

Measure:

TPS

MSPT

p50 tick time

p95 tick time

p99 tick time

worst tick

packet throughput

packet latency

network queue depth

chunk load latency

chunk save latency

serialization time

compression time

allocation rate

memory usage

worker utilization

simulation time by subsystem



---

53. Performance Target

Minecraft's nominal 20 TPS tick budget is:

50 ms / tick

The goal is not merely average throughput.

AdaCraft should minimize tail latency.

Therefore performance reports must include:

average
p95
p99
maximum

rather than only average MSPT.


---

54. Security Boundary

Every external input is untrusted.

This includes:

packets

commands

usernames

authentication data

NBT

component payloads

inventory actions

movement

block interactions

configuration input

network data


The rule is:

> Untrusted data must be validated before it becomes authoritative state.




---

55. Permissions

V1 permissions are configuration/op-list based.

Permission changes occur:

at startup through validated configuration, or

through the classified Try_Set_Permission operation.


No subsystem may directly mutate authoritative permission state.

Commands perform authorization through the authority layer.


---

56. Commands

Commands are core Minecraft functionality.

V1 includes the commands required for C1 survival and administration, including appropriate implementations of commands such as:

/tp

/gamemode

/give

/kill

/teleport

/time

/weather

/difficulty

/setworldspawn

other C1-required vanilla commands


The exact command tree is version-specific.

Commands are parsed into typed representations.

They are not executed as arbitrary strings.


---

57. Client Command Tree

The server exposes the version-appropriate command tree to the client.

The client must therefore receive command metadata sufficient for:

autocomplete

command suggestions

argument parsing

permission-aware command visibility where applicable


The internal typed command representation is distinct from the wire representation.


---

58. Native Extensions

AdaCraft supports native Ada/SPARK extensions.

They are not required for the C1 release.

The extension API exists after the core C1 implementation is established.

Extensions may provide:

commands

gameplay rules

administration

world tools

custom server systems

metrics

automation


Heavy engine-level modifications may eventually use native Ada packages.


---

59. Extension Loading

V1 supports either:

static linking

or:

native shared-library loading at startup

There is no runtime hot reload.

An extension that fails initialization must not leave the server in a partially initialized authoritative state.


---

60. Extension Isolation

Extensions use official APIs.

They do not receive arbitrary access to:

internal chunk arrays

allocator internals

registry memory

scheduler internals

raw authoritative pointers


The API uses typed values and validated handles.


---

61. No Second Language

V1 deliberately contains no:

Forth

Lua

JavaScript

embedded DSL

scripting VM

bytecode VM


The server language is:

> Ada/SPARK.



If future requirements establish a compelling need for sandboxed gameplay scripting, that becomes a separate RFC.

It does not enter the frozen v1 architecture.


---

62. Vanilla Compatibility

Compatibility is demonstrated rather than declared.

The target is:

> An unmodified Minecraft Java Edition 26.3 client can connect to AdaCraft and observe behavior matching the C0/C1 conformance specification.



Full vanilla parity is not a v1 claim.

C0/C1 is.


---

63. Conformance Classes

C0 — Joinable

C0 requires:

handshake

status

login

authentication

encryption

compression

configuration

known packs

registries

tags

play transition

player spawn

chunk delivery

basic movement

keepalive

disconnect


C1 — Survival Loop

C1 adds:

movement

block breaking

block placement

inventory

Data Components

crafting

containers

health

hunger

damage

death

respawn

persistence

relogging

basic entities

core commands

permissions


C1 is the v1 shipping target.


---

64. C2 — Deferred

C2 includes the broader world machine:

fluids parity

redstone parity

advanced scheduled ticks

lighting parity

spawning

more complex entity interactions


C2 is not required for v1.


---

65. C3 — Deferred

C3 represents full vanilla behavioral parity.

Potential areas include:

complete mob AI

villagers

raids

sculk systems

piston edge cases

portals

complex structures

complete world generation

remaining obscure mechanics


C3 is a future target.


---

66. World Generation Policy

AdaCraft v1 is a server implementation first, not a world-generator implementation.

Existing 26.3 worlds are first-class.

New world generation may initially be limited or delegated during early development.

Parity generation is explicitly deferred until the server itself is functional.


---

67. Differential Test Laboratory

The development environment contains:

Official Minecraft 26.3 server.jar
             │
             ├── Oracle
             │
             ▼
      Differential Harness
             ▲
             │
          AdaCraft

Both servers receive equivalent scenarios.

The harness compares authoritative outcomes.


---

68. Differential Test Priority

Initial comparison focuses on state.

Examples:

Player Position
Player Health
Player Inventory
Item Components
Block State
Entity State
Chunk State
Player Persistence

Wire-level packet equality is not initially required.

This avoids false failures caused by:

packet ordering

timestamps

implementation-specific entity IDs

harmless packet grouping

other non-semantic differences



---

69. Packet-Level Conformance

Once authoritative-state equivalence exists, selected wire behavior can be compared.

Priority areas:

login

configuration

registry data

known packs

keepalive

chunk packets

player position correction

inventory packets

disconnect


The goal is to ensure a vanilla client sees the expected protocol behavior.


---

70. Golden Corpus

The golden corpus begins during Phase 1.

It contains reproducible scenarios for:

handshake

status

login

authentication

encryption

configuration

known packs

registries

play

spawn

movement

block interaction

inventory

commands

disconnect


Every protocol regression adds a case.


---

71. Fuzzing

Fuzz all externally reachable parsers:

VarInt

VarLong

packet framing

packet decoders

NBT

Data Components

commands

compressed payloads

configuration data

inventory requests


The expected outcome of malformed input is rejection without authoritative corruption.


---

72. Formal Verification

Primary v1 SPARK proof obligations:

Protocol

no buffer over-read

no invalid indexing

bounded decoding

absence of runtime errors in the ingress decoder


Handles

generation validity

stale handle rejection

retirement correctness


Inventory

conservation

bounds

valid slot access

component validity

no partial transaction


Authorization

unauthorized operations cannot commit


Classified Writes

failure preserves authoritative state


Persistence

save commit state machine maintains its invariants


The entire simulation engine is not required to be formally verified.


---

73. Testing Stack

AdaCraft uses multiple layers:

Unit tests
     ↓
Subsystem tests
     ↓
Integration tests
     ↓
Differential tests
     ↓
Fuzzing
     ↓
Stress/load tests
     ↓
SPARK proof

No one layer substitutes for another.


---

74. Crash Recovery

Startup must detect incomplete persistence operations.

The server must recover to the last valid committed state.

The persistence design must prevent:

half-written chunk
+
apparently successful save

from becoming normal authoritative state.


---

75. Shutdown

Shutdown is deterministic:

Stop accepting players
        ↓
Stop new ingress
        ↓
Complete authoritative operations
        ↓
Create save snapshots
        ↓
Persist
        ↓
Verify commit
        ↓
Stop workers
        ↓
Close storage
        ↓
Exit

No worker may continue modifying authoritative state after shutdown reaches the appropriate barrier.


---

76. Repository Structure

The implementation should be separated into coherent packages.

Conceptually:

adacraft/
├── protocol/
├── network/
├── auth/
├── registry/
├── components/
├── kernel/
├── world/
├── chunks/
├── blocks/
├── entities/
├── players/
├── inventory/
├── commands/
├── physics/
├── ai/
├── redstone/
├── fluids/
├── lighting/
├── persistence/
├── scheduler/
├── extensions/
├── diagnostics/
├── tests/
├── differential/
└── tools/

The exact Ada package hierarchy may differ.

The architectural separation should not.


---

77. Development Phase Plan

Phase 1 — Protocol Foundation

Implement:

TCP

framing

VarInt/VarLong

packet encoder

packet decoder

state machine

protocol 777

golden corpus

initial differential driver


No gameplay yet.


---

Phase 2 — Login and Configuration

Implement:

status

handshake

login

online authentication

RSA

AES/CFB8

compression

configuration

known packs

registry data

tags

transition to play


The 26.3 registry tables established here become the single registry source used throughout the server. Mojang's 26.3 release introduced/changed substantial data-driven systems, so these definitions must be tied to the exact pinned release rather than an older 1.21.x model. 


---

Phase 3 — Persistence

Implement:

Anvil reader

Anvil writer

NBT

region files

chunk loading

player data

entity persistence

world metadata

crash-safe save path


At the end of this phase AdaCraft should be able to open an existing 26.3 world.


---

Phase 4a — Authority Boundary

Implement the complete unproven Try_* architecture.

No unrestricted packet-facing world mutation APIs.

The boundary exists before the proofs.


---

Phase 4b — Basic Gameplay

Implement:

player creation

movement

collision

block breaking

block placement

basic block state

basic entities

authoritative corrections



---

Phase 5 — Items and Inventory

Implement:

item registry

ItemStack

Data Components

stack rules

slots

cursor

containers

crafting

inventory transactions


Everything uses the registry established in Phase 2.


---

Phase 6 — SPARK Proof

Prove the already-existing authority boundaries.

No architectural rewrite should be required because the API shape was established in Phase 4a.


---

Phase 7 — C1 Survival

Complete:

health

hunger

damage

death

respawn

basic entities

commands

permissions

persistence

relogging

remaining C1 mechanics



---

Phase 8 — Optimization

Profile and optimize:

network

packet processing

memory

chunk access

entity iteration

serialization

compression

inventory

tick phases


The differential harness already exists.

This phase is optimization, not the beginning of testing.


---

Phase 9 — Native Extensions

Introduce:

extension API

static/startup loading

lifecycle

capabilities

commands

server services

documented extension contracts



---

78. Release Gate

AdaCraft v1 ships only when all of the following pass:

C0 PASS
C1 PASS

SPARK proofs PASS

Protocol fuzzing PASS
NBT fuzzing PASS
Component fuzzing PASS

Anvil compatibility PASS

Differential testing PASS

Crash/recovery testing PASS

Load testing PASS

Performance targets PASS

The gate is mandatory.

It is not aspirational.


---

79. Explicit v1 Non-Goals

The following are forbidden from silently entering the v1 constitution:

Bukkit

Spigot

Paper

JVM

JNI

Java plugins

Forth

scripting VM

hot-reload gameplay logic

multi-version core protocol

multi-region authoritative mutation

custom client

custom entity ecosystem

world-generation parity

C2 parity claim

C3/full-vanilla claim


Any addition requires a deliberate architecture change rather than incremental scope creep.


---

80. The Three Governing Rules

Everything in the project can ultimately be reduced to three rules.

Rule 1 — Authority

> Untrusted ingress never directly mutates authoritative simulation state.



Rule 2 — Ownership

> The v1 simulation owner exclusively owns authoritative world mutation.



Rule 3 — Development

> Correct first. Fast second. Parallel third.



Those three rules prevent most of the architectural failure modes we identified during the earlier iterations.


---

81. Final Architecture

MINECRAFT 26.3
                        VANILLA CLIENTS
                              │
                              ▼
                 ┌─────────────────────────┐
                 │      ADA NETWORK        │
                 │ TCP / buffers / crypto  │
                 └────────────┬────────────┘
                              │
                              ▼
                 ┌─────────────────────────┐
                 │   PROTOCOL 777 ENGINE   │
                 │ handshake / login /     │
                 │ configuration / play    │
                 └────────────┬────────────┘
                              │
                              ▼
                 ┌─────────────────────────┐
                 │    SPARK AUTHORITY      │
                 │                         │
                 │ Try_Move                │
                 │ Try_Break_Block         │
                 │ Try_Place_Block         │
                 │ Try_Inventory_Transaction│
                 │ Try_Execute_Command     │
                 │ Try_Chunk_Transition    │
                 │ Try_Retire_Handle       │
                 │ Try_Save                │
                 │ Try_Set_Permission      │
                 └────────────┬────────────┘
                              │
                              ▼
                 ┌─────────────────────────┐
                 │   ADA SIMULATION OWNER  │
                 │                         │
                 │ World                   │
                 │ Chunks                  │
                 │ Blocks                  │
                 │ Entities                │
                 │ Players                 │
                 │ Physics                 │
                 │ AI                      │
                 │ Redstone                │
                 │ Fluids                  │
                 │ Ticks                   │
                 └────────────┬────────────┘
                              │
                    classified commits
                              │
                              ▼
                 ┌─────────────────────────┐
                 │  AUTHORITATIVE STATE    │
                 └─────────────────────────┘

       ┌────────────────┐  ┌────────────────┐
       │ Persistence    │  │ Worker Pool    │
       │ Ada            │  │ Ada            │
       └───────┬────────┘  └───────┬────────┘
               │                   │
               └──────────┬────────┘
                          ▼
                 preparation only
                 until simulation
                    owner commits

82. Frozen Identity

AdaCraft v1.0 is:

> A native Ada/SPARK Minecraft Java Edition 26.3 server targeting protocol 777 and data version 5023, designed around a small formally verified authority boundary, a single-owner deterministic simulation engine, native Data Components, vanilla Anvil persistence, and aggressive but disciplined performance engineering.



It is not a Java server rewritten in Ada.

It is not a Bukkit replacement.

It is not a JVM compatibility project.

It is not a scripting platform.

It is not initially a massively parallel simulation.

It is a native Minecraft server designed from the ground up around Ada/SPARK's strengths.

And now the architecture really is at the point where I would stop revising it.

The next engineering documents should be exactly what you identified: PROTOCOL.md and KERNEL.md. Everything above them is the constitution; everything below them is implementation.
