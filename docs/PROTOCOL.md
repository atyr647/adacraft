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
| Protocol Version | VarInt |
| Server Address | String, at most 255 bytes |
| Server Port | Unsigned Short |
| Intent | VarInt: 1 status, 2 login |

Status is answered for any protocol version, so a client can see that this server is 777. Login is refused unless the version is 777.

Serverbound status request: empty. Clientbound status response: one JSON string.

```json
{"version":{"name":"26.3","protocol":777},"players":{"max":20,"online":0},"description":{"text":"AdaCraft"}}
```

Ping and pong are an unsigned 64-bit value, echoed unchanged.

Serverbound login `minecraft:hello`:

| Field | Type |
|---|---|
| Name | String, 1 to 16 bytes |
| Player UUID | 16 bytes |

Offline mode computes UUID version 3 of the UTF-8 bytes of `OfflinePlayer:` concatenated with the name (MD5, version nibble 3, IETF variant). The client UUID must match. That identity is not an online authenticated identity. Online mode (RSA, Mojang session server, AES/CFB8) is specified by the constitution and is not in this build. This build then sends login disconnect:

```json
{"text":"AdaCraft accepted the offline identity; play is not in this build"}
```

Login disconnect is clientbound id 0, a JSON text component encoded as a protocol string.

There is no configuration or play codec yet. Entering those states closes the connection. Registry bytes for that phase are the generated reports, not a second table.

## Bounds

Strings are bounded by the declared character maximum and by the bytes actually present. Packet length cannot exceed 2,097,151. The connection buffer is 8192 bytes, which covers handshake, status, and login. A declared length above that is rejected.

## What is deliberately absent

Chunk packets, registry-data encoding, encryption, compression, and the rest of the play catalog. Their ids exist in the generated table so they cannot be invented later from a 1.21.x scaffold. Their bodies get specified here before the code that sends them, per the roadmap.
