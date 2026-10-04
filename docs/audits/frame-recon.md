# TCP Framing — Reconnaissance Audit

Pre-implementation audit for the TCP Framing layer (Protocol 777, Minecraft Java
Edition 26.3). This document records the state of the codebase before the
`Adacraft.Protocol.Frame` spec/body is replaced, and identifies any minimal
cleanup needed. It is read-only recon; the actual implementation of the
incremental decoder and encoder is a separate item.

## 1. Protocol Siblings

### 1.1 House byte-array type

`src/protocol/adacraft-protocol.ads` establishes:

- `subtype Octet is Interfaces.Unsigned_8;`
- `type Octets is array (Positive range <>) of Octet;`
- `type Status_Kind is (Ok, Need_More, Rejected);`
- `Max_Packet_Length : constant := 2_097_151;`
- `Max_Varint_Bytes  : constant := 5;`
- `Max_Varlong_Bytes : constant := 10;`
- `Max_Length_Bytes  : constant := 3;`

**Finding — house byte type is `Octets`, not `Ada.Streams`.** The repo already
defines `Octet` / `Octets` (a `Positive`-indexed `Octet` array) and `Status_Kind`
in the root protocol package, and every sibling (`Buffer`, `Varnum`, `Packets`,
`Ingress`, `Network`) uses them. Per the task instruction *"if an established
house byte-array type exists prefer it"*, the new `Adacraft.Protocol.Frame` spec
should use `Octets` and `Positive` / `Natural` throughout — not
`Ada.Streams.Stream_Element_Array` / `Stream_Element_Offset` as the approach
sketch suggested. This avoids a conversion shim at the socket boundary and keeps
the package consistent with its siblings.

`Max_Packet_Length` (2 097 151) and `Max_Length_Bytes` (3) already match the
bounded-change limits, so the new spec can reference them directly instead of
re-declaring constants.

`Status_Kind` stays as-is for `Buffer` / `Varnum` / `Packets`. The new Frame will
likely introduce richer `Frame_Status` and `Encode_Status` enums; that is fine —
they live in the Frame package and do not collide with `Adacraft.Protocol.Status_Kind`.

### 1.2 `Adacraft.Protocol.Buffer` (`adacraft-protocol-buffer.ads/.adb`)

- Defines `Writer (Capacity : Positive) is record ... end record` with
  `Put_Octet`, `Put_Bytes`, `Put_Varint`, `Put_U16`, `Put_U64`, `Put_String`,
  and decoders `Decode_String`, `Decode_U16`, `Decode_U64`.
- Already used by `Protocol.Packets` and `Ingress`. Not directly relevant to
  the new Frame spec (Frame has its own private length codec per A7).
- **No change needed.**

### 1.3 `Adacraft.Protocol.Varnum` (`adacraft-protocol-varnum.ads/.adb`)

- General-purpose `Decode_Varint` (up to 5 bytes, 32-bit) and
  `Decode_Varlong` (up to 10 bytes, 64-bit). Both check non-minimal encoding
  (`Bits = 0` after step > 1) and overflow at the last byte.
- **Audit for framing-length leftover:** none. The functions are general-purpose
  VarInt / VarLong decoders — they accept up to 5 / 10 bytes respectively and
  are not specialised to framing lengths. There is no hard-coded `Max_Length_Bytes`
  check, no length-range check against `Max_Packet_Length`, and no body buffering.
- Per A7 the new Frame will **not** `with` this package — it will have a private
  1–3 byte length codec. This audit confirms that decision: the package is
  clean and should be left to issue #115 (general VarInt / VarLong).
- **No cleanup needed.**

### 1.4 `Adacraft.Protocol.Packets` (`adacraft-protocol-packets.ads/.adb`)

- Packet-level encode / decode (Handshake, Status response, Pong,
  Login_Disconnect, Ping, Login_Hello).
- Uses `Buffer` and `Varnum`; does **not** use `Frame`. Its own `Frame` function
  is a packet-framing helper built on `Buffer.Put_Varint` and is not the TCP
  framing layer.
- **No change needed for this item.**

## 2. Varnum Leftovers

See §1.3. `adacraft-protocol-varnum.ads` and `adacraft-protocol-varnum.adb`
contain no framing-length logic, no hard-coded `Max_Length_Bytes` limit, and no
body buffering. The "abandoned prior run" left no footprint in the varnum
package as it stands. **Nothing to remove.**

## 3. Network References

### 3.1 `src/network/adacraft-network.ads`

```ada
with GNAT.Sockets;

package Adacraft.Network is
   procedure Serve (Port : GNAT.Sockets.Port_Type);
end Adacraft.Network;
```

Only declares `Serve`. No `Protocol.Frame` references.

### 3.2 `src/network/adacraft-network.adb`

Uses `Protocol.Octet`, `Protocol.Buffer.Writer`, `Ingress.Session`, and
`Ada.Streams.Stream_Element_Array` (for the raw socket `Item` buffer and the
`Send_Socket` payload). No `Protocol.Frame` references. The current
`Adacraft.Protocol.Frame` spec (single-shot `Decode_Frame`) is **not** used by
the network layer.

**No stubs to fix.** Replacing the Frame spec will not break anything in
`src/network/`.

### 3.3 Cross-reference (out of scope for this task, noted for the next item)

A repo-wide grep for `Decode_Frame` finds two callers outside `src/network/`:

- `src/ingress/adacraft-ingress.adb` — uses `Protocol.Frame.Decode_Frame` to
  parse the first packet of a connection.
- `tests/adacraft_tests.adb` — uses `Protocol.Frame.Decode_Frame` in the
  handshake round-trip block (~line 102) and in the fuzz block (~line 268).

When the Frame spec is replaced in the next item, both callers will need to be
updated to the new `Decoder` / `Encode` API. **That is the next item's job, not
this one's.**

## 4. Build / Test Harness

### 4.1 Makefile

- `FLAGS := -gnat2022 -gnata -D obj` — `-gnata` enables assertions; **no
  `-gnatp`**, so runtime checks are NOT suppressed. ✅
- `SRC := -Igenerated -Isrc -Isrc/protocol -Isrc/kernel -Isrc/auth -Isrc/ingress -Isrc/network`
  — `-Isrc/protocol` is present, so every `src/protocol/*.adb` compiles. ✅
- `make all` builds `bin/adacraft` and `bin/adacraft_tests`.
- `make test` builds `bin/adacraft_tests` from `tests/adacraft_tests.adb` and
  runs it. `gnatmake` auto-discovers `.ads` / `.adb` dependencies, so the
  existing `adacraft-protocol-frame.ads` / `.adb` files are picked up without a
  source-list edit. No `gprbuild` / `.gpr` project file in use.
- `make server` runs `bin/adacraft`.
- `make clean` removes `obj/` and `bin/`.
- `make check` runs `tools/check_boundaries.py` (boundary discipline check,
  unrelated to the framing work).
- **Current state:** `make test` passes — verified by running it on the
  workbench. The existing single-shot `Decode_Frame` is exercised by the
  handshake round-trip and the fuzz block; both pass.

### 4.2 Test entry point

- `tests/adacraft_tests.adb` — single procedure `Adacraft_Tests`.
- Built directly with `gnatmake`; no separate test framework, no runner
  registration — all tests are inline in `Adacraft_Tests`.

## 5. Test Harness Conventions

Observed in `tests/adacraft_tests.adb` (lines 1–313):

- **Helper `Check (Cond : Boolean; Name : String)`** — prints `"FAIL " & Name`
  and increments `Failures : Natural` if `Cond` is false. Every test calls
  `Check` (or a sequence of `Check`s).
- **Helper `Hex (D : Auth.Digest) return String`** — formats a 16-byte digest
  as 32 lowercase hex chars. Not relevant for Frame.
- **Helper `Bytes (Text : String) return Protocol.Octets`** — converts a
  `String` to an `Octets` array (one byte per char, `Character'Pos`). Useful
  for the new Frame tests when feeding literal byte sequences.
- **Test grouping** — each logical test is an anonymous `declare ... begin ...
  end;` block at the top level of `Adacraft_Tests`. There are no nested
  procedures; all tests share the outer `Failures` counter. New Frame tests
  should follow the same pattern.
- **RNG** — the fuzz block uses a linear congruential generator:
  `Seed := Seed * 1664525 + 1013904223` (Numerical Recipes constants), seeded
  with `Interfaces.Unsigned_32 := 16#A5A5_1234#`. Bytes are taken as
  `Protocol.Octet (Seed mod 256)`. The new Frame tests should reuse this
  generator with a distinct seed value so failures are reproducible.
- **Exit status** — `Ada.Command_Line.Set_Exit_Status
  (Ada.Command_Line.Failure)` is called if `Failures > 0`. Final line is
  `"adacraft tests passed"` on success or `"adacraft tests failed: N"` on
  failure.
- **Imports** — `with` of every relevant package at the top, plus
  `use type` clauses for the numeric / enum types compared in tests. The new
  Frame tests will need `use type Protocol.Frame.Frame_Status` and
  `use type Protocol.Frame.Encode_Status` once those types are declared.

## 6. Decision Recorded

Per the task: the new Frame implementation uses the **existing**
`src/protocol/adacraft-protocol-frame.ads` and
`src/protocol/adacraft-protocol-frame.adb` files (repo convention
`Adacraft.Protocol.<X>` ↔ `adacraft-protocol-x.ads`). **No new source files,
no Makefile source-list churn.** The spec is replaced in place; the body is
replaced in place.

A corollary of §1.1: the new spec uses `Octets` and `Positive` / `Natural` (the
house types), not `Ada.Streams`. The approach sketch's `Stream_Element_Array` /
`Stream_Element_Offset` / `Stream_Element` types are superseded by this
finding.

## 7. Minimal Cleanup Required

**None.** The audit found:

- No framing-length leftover in `adacraft-protocol-varnum.*`.
- No `Protocol.Frame` references in `src/network/*` — no stubs to fix.
- No suppressed runtime checks in the Makefile (`-gnatp` is absent).
- No new files needed (decision recorded in §6).

The next item can proceed directly to replacing the `Frame` spec and body, and
to updating the two callers (`src/ingress/adacraft-ingress.adb` and
`tests/adacraft_tests.adb`) to the new `Decoder` / `Encode` API.
