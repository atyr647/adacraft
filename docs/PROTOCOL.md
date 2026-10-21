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

## Configuration

The server's side of configuration is the official 26.3 server's, byte for byte. `tools/capture_configuration.py` drives the pinned jar (offline mode, white-list off, compression off) in the lab as a vanilla client and records every configuration frame in `generated/26.3/configuration/oracle-core.jsonl`. `tools/extract_configuration.py` turns that capture into `generated/adacraft-protocol-configuration_data.ads` and the captured golden scenario `configuration-core-pack`. `make test` fails if either differs from the capture. Nothing in `src/` builds a registry entry or a tag by hand.

1. Login Acknowledged, empty, moves to CONFIGURATION. The server sends `custom_payload` (`minecraft:brand`, `vanilla`), `update_enabled_features` (`minecraft:vanilla`) and `select_known_packs` offering `minecraft:core` `26.3`.
2. The client may send Client Information, plugin messages, keep-alive and pong answers, resource-pack and cookie answers, custom click actions and the code-of-conduct answer. None is answered.
3. The client's `select_known_packs` must be well formed (at most 64 packs, no bytes left over) and name `minecraft:core` `26.3`. The server then sends the 32 `registry_data` packets, `update_tags` and `finish_configuration`, in the oracle's order. The pack known, registry entries carry no data: the client has it. The state is then CONFIGURATION awaiting the client's Finish Configuration.
4. The client's `finish_configuration`, empty, moves to PLAY. Nothing is sent: there is no play codec yet. Any packet in PLAY closes the connection.

A client that does not know the core pack would need every registry entry's full data (about 140 KB, all of it in the generated reports' datapack). That is not served yet: such a `select_known_packs`, a second one, a Finish Configuration before ours, or any other packet closes the connection.

Keep-alive from the server during configuration, the code of conduct, server links, dialogs and resource packs are not sent.

## Bounds

Strings are bounded by the declared character maximum and by the bytes actually present. Packet length cannot exceed 2,097,151. The connection buffer is 8192 bytes, which covers handshake, status, and login. A declared length above that is rejected. The send buffer is 128 KiB, which holds the whole of configuration's answer (about 68 KB) at once.

## What is deliberately absent

Chunk packets, registry data for a client without the core pack, encryption, compression, and the rest of the play catalog. Their ids exist in the generated table so they cannot be invented later from a 1.21.x scaffold. Their bodies get specified here before the code that sends them, per the roadmap.
