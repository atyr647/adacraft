# PROTOCOL.md

Normative wire rules for AdaCraft v1.0.
This document is under [CONSTITUTION.md](../CONSTITUTION.md). It does not add a protocol version.

Pin: Minecraft Java Edition **26.3**, protocol **777**, data version **5023**.
Packet ids are not written here. They are `generated/adacraft-protocol-ids.ads`, emitted from the official `PacketReport` in `generated/26.3/reports/packets.json`. See [PROVENANCE.md](../generated/26.3/PROVENANCE.md).

Field layouts below are the protocol 777 layouts for the packets this build decodes. Later play packets stay in the generated catalog and are not implemented.

## States

```text
HANDSHAKE --intent 1--> STATUS
HANDSHAKE --intent 2--> LOGIN --login acknowledged--> CONFIGURATION --finish--> PLAY
```

`intent` 3 (transfer) is rejected. There is no transfer state in the v1 constitution.
A packet whose id is not legal for the current state and direction closes the connection.
The decoder never calls into the world.

## Framing

Uncompressed frame:

| Field | Type | Rule |
|---|---|---|
| Length | VarInt | Length of packet id plus data. 1 to 2,097,151. At most 3 bytes. |
| Packet ID | VarInt | `protocol_id` from the 26.3 packet report. |
| Data | bytes | Remainder of `Length`. |

A length of 0 is rejected. A length that does not fit in the connection buffer is rejected rather than waited on. An incomplete frame returns "need more" and consumes nothing.

Compression is specified and not enabled. This build never sends Set Compression. A compressed frame is not accepted. When compression is added, it stays out of the world packages: zlib inflate into a bounded buffer, threshold from the login packet, data-length 0 meaning uncompressed, uncompressed size capped at 2,097,151.

## VarInt and VarLong

7 data bits and one continuation bit, most significant bit first in the continuation sense (little-endian groups).

| Type | Maximum bytes | Last-byte payload |
|---|---|---|
| VarInt | 5 | at most 4 bits (value ≤ 15) |
| VarLong | 10 | at most 1 bit (value ≤ 1) |

Overlong encodings are rejected. A multi-byte value whose final group is 0 is overlong. Truncation is "need more", not a value. This is stricter than the vanilla note that a length field may use a non-minimal encoding of up to 3 bytes. Constitution section 20 wins: AdaCraft rejects those too. Vanilla clients send minimal encodings.

## Handshake, status, login

Serverbound `minecraft:intention` (handshake id 0):

| Field | Type |
|---|---|
| Protocol Version | VarInt, well-formed, stored verbatim |
| Server Address | String, UTF-8, at most 255 bytes, validated and stored |
| Server Port | Unsigned Short big-endian, stored verbatim |
| Intent | VarInt: 1 status, 2 login, 3 login (transfer handover) |

Exactly one handshake is accepted per connection. A second handshake, an
unknown packet id in HANDSHAKE state, a malformed field, an intent outside
`{1, 2, 3}`, or extra trailing payload bytes is a violation: the connection
closes without sending any bytes. After a valid handshake the connection
stores the protocol version verbatim, the validated server address, the port
verbatim, the raw intention value, and the mapped target state, and leaves
HANDSHAKE state. The address is stored only for later use; it never selects
a virtual host. Status is answered for any protocol version, so a client can
see that this server is 777. Version-mismatch diagnosis belongs to #122.

Serverbound status request (`0x00`): empty payload only, may repeat; each
valid request receives exactly one status response and the connection stays
in STATUS. Serverbound ping request (`0x01`): exactly one signed 64-bit
big-endian long; a valid ping receives exactly one pong echoing the value
unchanged, and after the pong is flushed the server closes the connection.
No further packets are processed after the pong. Short, long, or
non-empty/extra-byte status payloads are violations and close with no bytes.

Clientbound status response (`0x00`): one Minecraft String containing compact
JSON with fixed key order `version`, `players`, `description`,
`enforcesSecureChat`; `version` order is `name`, `protocol`; `players` order
is `max`, `online`; `description` is `{"text":"<MOTD>"}`. `favicon`,
`previewsChat`, and `players.sample` are omitted.

```json
{"version":{"name":"26.3","protocol":777},"players":{"max":20,"online":0},"description":{"text":"AdaCraft"},"enforcesSecureChat":false}
```

The JSON is produced by `Adacraft.Protocol.Status_Json.To_Json` from the
read-only `Adacraft.Protocol.Status_Info.Status_Info` snapshot (defaults:
version `"26.3"`, protocol `777`, max `20`, online `0`, MOTD `"AdaCraft"`,
secure chat `False`, no favicon). MOTD is bounded to 256 UTF-8 bytes and
validated at construction. Escaping: `\"`, `\\`, `\b \f \n \r \t`, `\u00XX`
for remaining controls, raw UTF-8 for non-ASCII. The maximum JSON length
fits the frame maximum by construction. Identical input bytes produce
identical bytes sent, connection state, and close/no-close decisions; status
output carries no timestamps, random values, hostnames, or nondeterministic
key ordering. Handshake and STATUS handling read only the `Status_Info`
snapshot and connection-local fields; they never touch world, player,
chunk, permission, or simulation state. HANDSHAKE and STATUS packets are
never compressed or encrypted.

Idle timeout: 30 s (`Adacraft.Ingress.Default_Idle_Timeout`), reset after
each successfully completed inbound packet in HANDSHAKE/STATUS (and the
LOGIN stub below). Timeout closure sends no bytes.

### LOGIN extension point for #122 (`Handle_Login_Stub`)

On intent `2|3` the connection enters LOGIN carrying the stored handshake
fields (`Stored_Handshake` / `Hs_Version`, `Hs_Address`, `Hs_Port`,
`Hs_Intent` plus the mapped state; raw intention `2` vs `3` is preserved so
#122 can distinguish them later). In this item LOGIN is a stub:
`Adacraft.Ingress.Handle_Login_Stub` closes the connection without sending
any bytes on any inbound packet in LOGIN, under the same idle timeout. #122
replaces the body of `Handle_Login_Stub` with real LOGIN handling
(Login Start/Success/Disconnect, username and UUID policy, session-server
authentication, online/offline mode, version-mismatch diagnosis using the
stored protocol version, transfer semantics, encryption, compression); the
procedure profile and the stored-handshake record are the handover contract.
`Status_Info` stays a finished read-only contract; later items may extend it
(favicon, player sample) only with re-pinned goldens.

There is no configuration or play codec yet. Entering those states closes the connection. Registry bytes for that phase are the generated reports, not a second table.

## Bounds

Strings are bounded by the declared character maximum and by the bytes actually present. Packet length cannot exceed 2,097,151. The connection buffer is 8192 bytes, which covers handshake, status, and login. A declared length above that is rejected.

## What is deliberately absent

Chunk packets, registry-data encoding, encryption, compression, and the rest of the play catalog. Their ids exist in the generated table so they cannot be invented later from a 1.21.x scaffold. Their bodies get specified here before the code that sends them, per the roadmap.
