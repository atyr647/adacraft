# TCP Framing — Design Document

**Path:** `docs/design/tcp-framing.md` (new file; creates the `docs/design/` directory)
**Bounded change:** TCP Framing Logic
**Status:** Proposed
**Resolves:** open questions Q1–Q10 from the framing requirements

---

## 1. Problem

TCP is a byte stream without message boundaries. Adacraft needs a framing layer that converts between discrete packets (opaque byte arrays) and the stream: an **encoder** that prefixes a length header to an outbound payload, and a stateful **decoder** that reassembles inbound chunks into complete, correctly ordered packets — while refusing to allocate memory based on unvalidated, attacker-controlled length headers.

This layer must be transport-agnostic logic: it consumes and produces byte arrays. It must never touch sockets, serialization, encryption, or routing.

## 2. Repository context and placement

The codebase already has the natural home for this component and its neighbors:

| Module | Role in this design |
|---|---|
| `src/protocol/adacraft-protocol-frame.ads/.adb` | **Primary target.** `Adacraft.Protocol.Frame` becomes the framing codec (encoder + decoder + error taxonomy). |
| `src/protocol/adacraft-protocol-varnum.ads/.adb` | `Adacraft.Protocol.Varnum` provides VarInt primitives. This change adds an incremental, boundary-checked decode entry point (see §6.1). It is the **single seam** where the wire format lives. |
| `src/protocol/adacraft-protocol-buffer.ads/.adb` | Candidate for reuse of byte-buffer primitives; evaluated during implementation (see §11, A-V2). Not a hard dependency. |
| `src/ingress/adacraft-ingress.ads/.adb` | **Integration point.** Owns per-connection decoders, feeds socket reads, drains decoded payloads, enforces the terminal-error policy. |
| `src/network/adacraft-network.ads/.adb` | Socket I/O only. No framing logic. Verify read/EOF semantics; change only if EOF is not surfaced. |
| `src/protocol/adacraft-protocol-packets.ads/.adb` | Consumer of decoded payloads. No change expected; framing is upstream and opaque. |
| `tests/adacraft_tests.adb` | Test suite for AC-1…AC-11 plus the extra cases in §8. |
| `docs/PROTOCOL.md` | Documents the frame wire format, limits, and error semantics. |
| `tools/check_boundaries.py` | Run (not changed) to enforce layering: `Adacraft.Protocol.Frame` must **not** depend on `Adacraft.Network`, `Adacraft.Ingress`, or `GNAT.Sockets`. |

Layering rule: the dependency direction is `Ingress → Protocol.Frame → Protocol.Varnum (+ Ada.Streams, Ada.Finalization, Interfaces)`. Nothing below the protocol layer knows about the framing layer, and the framing layer knows nothing about I/O.

## 3. Design decisions (resolving Q1–Q10)

| Q | Decision | Rationale |
|---|---|---|
| Q1 | **Length-prefixed frames**: `[length header][payload]` | Assumption A1; the only method compatible with opaque payloads and the fragmentation/coalescing ACs. Delimiters and fixed-size frames explicitly out of scope. |
| Q2 | **VarInt header** (unsigned LEB128, 1–5 bytes) | The repository implements a Minecraft-family protocol (`docs/PROTOCOL.md`, `generated/26.3/reports/packets.json`, existing `Adacraft.Protocol.Varnum`). A fixed-width header would fork the wire format this stack already speaks and would be dead code. All ACs are satisfiable with a varint header. |
| Q3 | **Unsigned**, LEB128 (byte order N/A). **Bit 31 is reserved: must be 0.** | Matches the protocol family's length fields. Reserving bit 31 gives "negative length" (AC: Invalid Values) a concrete, testable rejection: any header a signed reader would interpret as negative raises `Invalid_Length`, and the valid range is bounded by 2³¹−1. |
| Q4 | Length counts **payload only** (header excluded) | Matches the round-trip AC ("length of the payload") and the outer length prefix of the repo's protocol. Simplifies the encoder. |
| Q5 | **Zero-length payloads are permitted** by the framing layer | The layer must not inspect payload contents (constraint), so it cannot reject empties based on "must contain a packet ID". `Has_Payload` disambiguates "empty frame" from "nothing decoded" (§6.1). Higher layers may reject empty packets. |
| Q6 | **Per-instance configurable maximum** (`Max_Payload` discriminant). Default **2 MiB inbound**; larger configurable for outbound (chunk data). | The maximum is the allocation-attack bound; it must be tunable per direction. Default to be confirmed (§11, A-V4). |
| Q7 | **Terminal error state.** After any framing error, every subsequent operation raises `Decoder_Compromised`. **No `Reset`.** The connection owner closes the socket. | After a framing error, the byte offset of the next header is unknowable; any continuation would misattribute bytes to frames (desync). Length-prefix framing has no resync marker, so recovery requires fail-stop. |
| Q8 | Compatible with the protocol described in `docs/PROTOCOL.md`. The format-specific logic is isolated behind `Varnum.Try_Decode` so a format swap is a one-function change. | The framing logic itself is generic; only the header codec is protocol-specific. |
| Q9 | Ada / GNAT. **No tasking inside the codec.** One `Decoder` per connection, owned by the connection's task (or the single-threaded ingress loop). Not declared task-safe. | Keeps the codec deterministic and unit-testable; matches the existing scheduler/ingress structure. |
| Q10 | **No additional header fields** (no type/version/flags). | Required by the opaque-payload constraint and the AC's out-of-scope list. |

**Rejected alternative (recorded):** fixed 4-byte big-endian unsigned header. Simpler to specify, but incompatible with the wire format the rest of the protocol stack uses, so it would either break interop or never be exercised. Retained as the fallback if verification (§11, A-V1) shows the repo does not use varint framing; the swap is confined to the `Varnum` seam.

## 4. Wire format

```text
frame        ::= length_varint payload
length_varint::= unsigned LEB128, 1..5 bytes, value < 2**31
payload      ::= length_varint bytes (opaque, may be empty)
```

Rules:

- **Encode:** always emits a *minimal* varint. Empty payload ⇒ frame is the single byte `16#00#`.
- **Decode:** accepts minimal and non-minimal varints up to 5 bytes (lenient, matching common peer implementations).
- A varint longer than 5 bytes, a value ≥ 2³¹ (bit 31 set ⇒ "negative"), or a value > `Max_Payload` is a framing error (see §6.5).
- The maximum in force is the endpoint's configured `Max_Payload`; the wire format itself imposes only the 2³¹−1 ceiling.

Note on the zero-length frame: a stream of `00 00 00 …` is a sequence of valid empty frames. The decode loop always consumes ≥ 1 byte per iteration, so coalesced empty frames cannot spin (explicit infinite-loop guard, tested in T5/T10).

## 5. Public API (sketch)

```ada
with Ada.Streams;

package Adacraft.Protocol.Frame is

   subtype Payload_Count is Ada.Streams.Stream_Element_Count;

   Header_Max_Bytes    : constant := 5;                          -- VarInt ceiling
   Default_Max_Payload : constant Payload_Count := 2 * 2**20;    -- 2 MiB; confirm, §11 A-V4

   --  Error taxonomy. All descend from Framing_Error so a caller can catch
   --  the root and treat every variant as fatal-for-the-connection.
   Framing_Error       : exception;
   Frame_Too_Large     : exception;  -- declared length > Max_Payload (allocation attack)
   Invalid_Length      : exception;  -- varint > 5 bytes, 32-bit overflow, bit 31 set ("negative")
   Truncated_Frame     : exception;  -- end-of-stream with a partial frame buffered
   Decoder_Compromised : exception;  -- operation attempted in terminal state

   ---------- Encoder (pure, stateless) ----------

   function Encoded_Size
     (Payload_Length, Max_Payload : Payload_Count) return Payload_Count;
   --  Raises Frame_Too_Large when Payload_Length > Max_Payload.

   procedure Encode
     (Payload : Ada.Streams.Stream_Element_Array;
      Max     : Payload_Count;
      Output  : out Ada.Streams.Stream_Element_Array;
      Last    : out Ada.Streams.Stream_Element_Offset);
   --  Output(Output'First .. Last) = [ VarInt(Payload'Length) ; Payload ].
   --  Validates BEFORE writing: on Frame_Too_Large, no byte of Output is set.

   ---------- Decoder (stateful, one per connection) ----------

   type Decoder (Max_Payload : Payload_Count) is limited private;

   procedure Feed (D : in out Decoder; Chunk : Ada.Streams.Stream_Element_Array);
   --  Ingest raw socket bytes. Raises Framing_Error'Class on invalid input;
   --  afterwards D is terminal (Has_Failed = True).

   function Has_Payload (D : Decoder) return Boolean;
   --  True iff >= 1 complete frame is buffered. REQUIRED to distinguish a
   --  valid empty payload from "nothing decoded" (Q5).

   function Next_Payload
     (D : in out Decoder) return Ada.Streams.Stream_Element_Array;
   --  Removes and returns the oldest complete payload (may be null length).
   --  Precondition: Has_Payload (D). Returns a fresh copy owned by the caller.

   procedure Finish (D : in out Decoder);
   --  Signal end-of-stream. Raises Truncated_Frame if an incomplete frame
   --  (partial header or partial payload) is buffered; nothing is emitted
   --  for it. One-shot: the decoder is spent afterwards.

   function Has_Failed (D : Decoder) return Boolean;
   --  Terminal-state indicator. Deliberately no Reset (Q7).

private
   --  Controlled type; heap-allocated fixed-size store sized
   --  Header_Max_Bytes + Max_Payload at construction; queue of completed
   --  frames as a singly linked list; see §6.2/§6.3.
end Adacraft.Protocol.Frame;
```

Supporting change in `Adacraft.Protocol.Varnum` (additive, the wire-format seam):

```ada
   type VarInt_Status is (Incomplete, Ok, Malformed);
   function Try_Decode
     (Data     : Ada.Streams.Stream_Element_Array;
      From     : Ada.Streams.Stream_Element_Offset;
      Value    : out Interfaces.Unsigned_32;
      Consumed : out Ada.Streams.Stream_Element_Count) return VarInt_Status;
```

## 6. Component design

### 6.1 `Varnum.Try_Decode` — the wire-format seam

`Try_Decode` is the **only** place the framing layer reads length-prefix bits. Everything upstream of it deals in "how many bytes of header have I buffered, and is the accumulated value legal yet?". That separation lets the framing state machine stay declarative and lets the bit-level rules live in one function, which is also the natural place to test the boundary cases (Q3, Q5, Q7).

**Contract:**

- `Incomplete` — `Data(From .. Data'Last)` is a legal varint prefix; no terminator byte is present. No byte is "consumed" (Consumed = 0). Caller buffers and waits.
- `Ok` — `Value` is the decoded unsigned 32-bit integer; `Consumed` ∈ `1 .. 5` is the number of bytes starting at `From` that produced it.
- `Malformed` — the input cannot start a legal varint: more than 5 continuation bytes, an accumulated value with bit 31 set, a non-terminal zero group, or the 5th byte's payload exceeds 4 bits (i.e. would set bit 31). No byte is consumed. The framing layer treats this as a desynchronization and enters terminal state (Q7).

The function is **stateless** and **re-entrant**: it takes only the buffer slice and a starting offset and returns everything the caller needs to advance its own cursor. This is the property that makes it usable mid-varint (header split across TCP segments) without reslicing.

Why a new function and not a wrapper over `Decode_Varint`? Because `Decode_Varint` returns a `Status_Kind` that conflates "need more" with one of the rejected cases at the buffer boundary, and because it must inspect a buffer that *contains* a complete candidate varint — the state machine holds a *prefix*, not a candidate. `Try_Decode` is the in-loop primitive; `Decode_Varint` remains the one-shot "is this whole buffer a legal varint?" check used by the higher-level packet parsers (e.g. `Frame.Decode_Frame`).

### 6.2 Decoder state machine

States: `Reading_Header` → `Reading_Payload` → (loop back) ; `Failed` (terminal) ; `Closed` (after `Finish`).

Persistent state across `Feed` calls: partial header accumulator (`Header_Val`, `Header_Len`), remaining payload count (`Remaining`), a byte store (`Store` with cursor), and a FIFO of completed frames.

```
Feed (D, Chunk):
  if D.State = Failed/Closed -> raise Decoder_Compromised
  append Chunk to Store (capacity check is a defensive assertion, §6.3)
  loop
    case D.State is
      when Reading_Header =>
        try to complete the varint from Store at the cursor:
          byte with continuation bit, Header_Len = 5 already
            -> Invalid_Length                      (overlong varint)
          value would set bit 31
            -> Invalid_Length                      ("negative" length)
          accumulated value > Max_Payload
            -> Frame_Too_Large                     (EARLY ABORT: fires even
                                                     mid-varint, before the
                                                     terminator byte arrives)
          varint incomplete, more bytes needed
            -> return (buffer, emit nothing)
          varint complete and valid:
            consume header bytes; Remaining := Value
            if Remaining = 0 -> enqueue empty frame; stay in Reading_Header; continue
            else -> State := Reading_Payload
      when Reading_Payload =>
        if buffered >= Remaining:
          copy out exactly Remaining bytes as a frame; advance cursor
          State := Reading_Header; continue
        else return
    end case
  end loop

Finish (D):
  if State in Failed/Closed -> raise Decoder_Compromised
  clean end  iff State = Reading_Header and Header_Len = 0 and no payload pending
  otherwise  -> raise Truncated_Frame
  State := Closed
```

Properties delivered by construction:

- **Reassembly / fragmentation** (AC-2): a frame can arrive as N TCP segments in any grouping — header split, payload split, or both — and is reassembled in order, because partial state is held in `Header_Val` / `Header_Len` / `Remaining` and the cursor never advances past unconsumed bytes.
- **Coalescing** (AC-2): the outer `loop` continues until the store is drained or a `Reading_Payload` wait is hit, so multiple complete frames in one chunk are emitted in order.
- **Ordering** (AC-2): the queue is FIFO; `Next_Payload` returns the oldest.
- **Fidelity** (AC-2 round-trip): the encoder emits `[VarInt(N), payload]`; the decoder's `Next_Payload` returns the exact `payload` bytes after stripping that header, and `Has_Payload` is the unambiguous "got something" signal for the zero-length case.
- **Allocation-attack bound** (AC-3): the check `Value > Max_Payload` happens **before** any frame is enqueued, so memory for the payload is allocated only after the length has been validated. The same check fires mid-varint — a length of 5 GB declared across bytes 1..4 is rejected as soon as the partial accumulation crosses `Max_Payload`, not only when the terminator arrives.
- **Negative-length** (AC-3): folded into `Invalid_Length` at the `Try_Decode` level via "bit 31 set" — a single, testable, wire-level predicate.
- **Truncated stream** (AC-3): `Finish` checks the state and raises `Truncated_Frame` unless no work is pending. The connection owner treats this as a `Close` (Q7), not a reconnect.
- **Terminal state** (AC-3 / Q7): every error path sets `State := Failed`. `Feed`, `Next_Payload`, and `Finish` all check this and raise `Decoder_Compromised`. There is no `Reset` — desync is unrecoverable for a length-prefixed format.

### 6.3 Store sizing and ownership

`Store` is a single heap-allocated buffer sized `Header_Max_Bytes + Max_Payload`, allocated at `Decoder` construction via Ada `Finalization`. The cursor and the partial-header state are stored alongside it in the controlled record. Completed frames are kept as a singly linked list of *external* heap-allocated copies (`Next_Payload` returns a copy the caller owns and must free), so a slow consumer does not stall the producer. A bounded queue (cap = 8 frames) prevents an unbounded backlog from a malicious peer emitting many small frames; on overflow the decoder raises `Frame_Too_Large` (misuse class) and enters terminal state.

The store itself is *not* a ring buffer: it is compacted (cursor and tail are reset) every time a frame is dequeued. This costs an O(n) copy on dequeue, but `n` is bounded by `Header_Max_Bytes + Max_Payload` and dequeue is rare relative to `Feed`, so the simplicity is worth it.

### 6.4 Encoder

`Encode` validates the payload length against `Max` **first** and only then writes the varint header and the payload bytes into `Output`, setting `Last` to the index of the last byte written. The caller is responsible for sizing `Output` (`Output'Length >= Encoded_Size (Payload'Length, Max)`); on `Frame_Too_Large` no byte of `Output` is set, so a partially-sized buffer is never left in an inconsistent state. `Encoded_Size` is a pure function (no allocation, no I/O) so the caller can size `Output` cheaply.

The encoder emits a **minimal** varint. Empty payload produces the single byte `16#00#`, matching the wire format note in §4.

### 6.5 Error mapping (wire → exception)

| Wire condition | Detected at | Exception |
|---|---|---|
| 6th byte with continuation bit set | `Try_Decode` (overlong) | `Invalid_Length` |
| 5th byte's data bits > 15 | `Try_Decode` (bit-31) | `Invalid_Length` |
| Non-terminal zero group | `Try_Decode` (overlong) | `Invalid_Length` |
| Accumulated value > `Max_Payload` (mid-varint) | `Feed` | `Frame_Too_Large` |
| Accumulated value ≥ 2³¹ (mid-varint) | `Try_Decode` | `Invalid_Length` |
| Stream closed with partial frame buffered | `Finish` | `Truncated_Frame` |
| Operation on `Failed`/`Closed` decoder | any | `Decoder_Compromised` |

All five descend from `Framing_Error`, so a single `when others => ...` arm handles them; consumers that need to distinguish (e.g. to decide whether to log a malformed peer vs. a normal close) inspect the specific tag.

## 7. Integration with `Adacraft.Ingress`

`Adacraft.Ingress` becomes the owner of one `Decoder` per session, sitting between the socket read and `Ingest`:

```ada
type Session is record
   State     : Protocol.Protocol_State := Protocol.Handshake;
   Version   : Interfaces.Unsigned_32  := 0;
   Framer    : Protocol.Frame.Decoder (Protocol.Frame.Default_Max_Payload);
   Read_Buffer : ...;   -- 8 KiB, matches docs/PROTOCOL.md connection buffer
   In_Buffer   : ...;   -- drained into Framer per loop iteration
end record;
```

Per loop iteration: read up to 8 KiB into `Read_Buffer`, `Feed` the framer, drain every `Next_Payload` into `Ingest` (the existing protocol dispatcher). On `Frame_Too_Large` or `Invalid_Length`: set `Close_Now`, do **not** re-enter the framer. On `Truncated_Frame` from `Finish` (EOF): same. The `Ingest` API stays the same — frames are still consumed as `Octets` slices, opaque to the dispatcher.

The existing `Ingest`'s `Consumed` mechanism, which already supports coalesced frames, is kept: the framer is the new front edge, and `Ingest` is unchanged behind it.

## 8. Test plan

`tests/adacraft_tests.adb` grows new procedures, one per AC plus the boundary cases from §6.5:

- **T1** Encode empty payload → 1-byte frame `00`; decode round-trip = empty.
- **T2** Encode N-byte payload (small, mid, max-1, max) → length matches; decode round-trip = original.
- **T3** Encode over-limit payload → `Frame_Too_Large`; `Output` untouched.
- **T4** Decode `[00]` → `Has_Payload` immediately, `Next_Payload` = empty slice.
- **T5** Decode stream of 1024 × `00` → 1024 empty frames, no spin.
- **T6** Decode frame split across 1, 2, 3, 4, 5 TCP-sized chunks → reassembled identically.
- **T7** Decode two complete frames coalesced in one chunk → emitted in order, round-trip equal.
- **T8** Decode a 6-byte varint → `Invalid_Length`, terminal.
- **T9** Decode a varint whose accumulated value sets bit 31 (e.g. 5 bytes `FF FF FF FF 0F` → 0xFFFFFFFF, then `10` → 0x80000000 on a 6th attempt is rejected) → `Invalid_Length`. Same for the degenerate 5th-byte case `FF FF FF FF 7F` (allowed by some readers, but the protocol pin in `docs/PROTOCOL.md` rejects it).
- **T10** Decode a length of `Max_Payload + 1` → `Frame_Too_Large`, terminal; verify the partial frame did **not** allocate a payload buffer.
- **T11** Decode a length of `Max_Payload * 10` carried across 4 bytes where the 3rd byte already crosses the limit → `Frame_Too_Large` at the moment of crossing, before the terminator (early-abort test).
- **T12** `Finish` on a clean stream → no error. `Finish` after a partial header → `Truncated_Frame`.
- **T13** After any error, `Feed`, `Next_Payload`, `Finish` all raise `Decoder_Compromised`.
- **T14** `Has_Payload` is `False` between `Feed` and the first complete frame, `True` thereafter until the frame is drained.
- **T15** Layering: `tools/check_boundaries.py` passes (no new edges from `Protocol.Frame` to `Network`/`Ingress`).

## 9. Out of scope (recap)

- Socket lifecycle, timeouts, keep-alives, reconnection.
- Serialization of packet bodies (Protobuf, JSON, NBT).
- TLS, compression (compression is specified in `docs/PROTOCOL.md` but explicitly disabled for v1 and would be a separate layer above framing).
- Routing / dispatch (already lives in `Ingress` and is unchanged).
- UDP / WebSocket / delimiter framing.

## 10. Open questions and assumptions (verification list)

| # | Item | Action |
|---|---|---|
| A-V1 | Confirm the live protocol uses varint length prefix. | Inspect `Adacraft.Protocol.Packets.Frame` and the existing `Decode_Frame`; cross-check against `docs/PROTOCOL.md`. |
| A-V2 | Decide whether `Protocol.Buffer` is the right host for the encoder/decoder or whether framing deserves its own minimal byte-array abstraction. | Compare ergonomics during implementation; keep the seam narrow. |
| A-V3 | Confirm bit-31 reservation is the right "negative" detection vs. e.g. 2³² wrap detection. | `docs/PROTOCOL.md` says varint is signed-but-ZigZag in some places; for **length headers** it is plain unsigned and bit-31-set is the rejection. Document the choice in `PROTOCOL.md` if not already. |
| A-V4 | Settle on the default `Max_Payload` (2 MiB proposed). | Cross-check against `docs/PROTOCOL.md` "Length … 1 to 2,097,151" and the connection-buffer size 8192. |
| A-V5 | `Next_Payload` returns a copy; confirm the caller (the ingress dispatcher) can free it correctly under the no-tasking invariant (Q9). | Trivial in single-threaded ingress; document the ownership rule on the function. |

## 11. Risks and mitigations

- **R1: Mid-varint early-abort window.** Rejecting on `Value > Max_Payload` before the terminator arrives means a peer can force the decoder to drop a connection by sending a long varint that crosses the limit on byte 4 of 5. This is acceptable (the connection is already misbehaving; fail-stop is the policy) and is the *desired* behavior — it is the same as rejecting the full varint on byte 5, just earlier.
- **R2: Coalesced-empty-frame spin.** Defended by the invariant that the loop always consumes ≥ 1 byte per iteration (either a varint byte, a payload byte, or a complete empty frame), and by the bounded queue cap.
- **R3: Allocation before validation.** Defended by the `Value > Max_Payload` check before `Remaining` is stored and before any `Next_Payload` allocation. T10/T11 prove this.
- **R4: `Decoder` not task-safe.** Documented; owner is the connection's task / the single ingress loop. Re-entrancy is not supported and not required by the call sites.

## 12. Summary of the seam

The framing layer is **two components** in two files plus a small change in a third:

1. `Adacraft.Protocol.Varnum` — gain `VarInt_Status` + `Try_Decode` (done in this change).
2. `Adacraft.Protocol.Frame` — becomes the framing codec with the API in §5 (follow-on change).
3. `Adacraft.Ingress` — owns per-session decoders, drains payloads into the existing dispatcher (follow-on change).

Everything else (`Packets`, `Buffer`, `Network`, `Kernel`) is untouched. Layering is enforced by `tools/check_boundaries.py`.
