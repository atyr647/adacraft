# ORACLE.md

How AdaCraft gets its bytes right without anyone hand-encoding them: the
official 26.3 server is run beside it in a lab, what it sends is recorded,
and AdaCraft sends the same, checked byte for byte. Configuration and the
opening of PLAY were done this way (docs/PROTOCOL.md). Every further piece
of protocol should be too, wherever the oracle can show it.

The lab is never part of the shipped server: nothing in `src/` runs Java or
reads `lab/`.

## The rule

Don't write packet bytes from memory, a wiki or another server's source.
Record them from the oracle, generate the Ada constants from the recording,
and prove the result against the recording. If a value genuinely varies
(an entity id, a keep-alive id, a timestamp), find which bytes vary by
recording twice, and fill only those in.

## The recipe

Each step has a command. Do them in order; don't skip the checks.

1. **Start the oracle.**
   `tools/oracle-lab.sh fresh`
   (fetches the pinned jar once, checks its hash, fetches Java 25 if
   needed, writes the settings below, wipes the world, starts it on
   127.0.0.1:25599). `tools/oracle-lab.sh stop` when done.

2. **Record what you need.**
   `python3 tools/capture_configuration.py 127.0.0.1 25599 OUT.jsonl [options]`
   - no option: handshake, login, configuration (a client that knows the
     `minecraft:core` 26.3 pack)
   - `--play N`: also the first N frames of PLAY
   - `--wrong-keep-alive`: answer the first PLAY keep-alive with another id
   - `--silent`: never answer a PLAY keep-alive
   To record something new, add an option there in the same style: drive the
   oracle as a vanilla client would, and let it record.

3. **Record it twice, and compare.**
   `tools/oracle-lab.sh fresh` again, record again, then
   `python3 tools/compare_capture.py FIRST.jsonl SECOND.jsonl`.
   Frames marked `same` can be copied as they are. Frames that differ are
   either a known variation (listed below, and printed `reordered` or
   `per-run`) or something new: find which bytes differ, work out what they
   are, and add a rule to `tools/compare_capture.py` before going on.

4. **Generate.** Write (or extend) a `tools/extract_*.py` that turns the
   recording into an Ada package under `generated/` and a golden scenario
   under `tests/corpus/`, with a `--check` mode, and add the `--check` to
   `make check` in the Makefile. Copy `tools/extract_play.py`: it shows
   how a per-connection field (the entity id) is located, named and
   checked rather than guessed.

5. **Implement** in `src/network/` (or `src/protocol/`) using only the
   generated constants. Bytes in `src/` that came from nowhere fail review.

6. **Prove it.**
   - `make test`: the golden scenario replays through the server's own
     dispatch; the live test drives `bin/adacraft` over TCP.
   - The differential: run `bin/adacraft 25612`, record it with the same
     command as step 2, and
     `python3 tools/compare_capture.py ORACLE.jsonl OURS.jsonl` must exit 0.

7. **Write it down** in docs/PROTOCOL.md: what is sent, what is left out
   and why, and anything the oracle does that AdaCraft doesn't.

## The oracle's settings

Offline mode; white-list off (26.3 turns it on by default, and a capture
then fails at login with "not white-listed"); compression off
(`network-compression-threshold=-1`, so frames are readable); a flat world,
seed 777, no structures, no mobs; view distance 2; `motd=AdaCraft` (the
same text as AdaCraft's status). `tools/oracle-lab.sh` writes exactly these.

## Known variation between oracle runs

- `update_tags` (configuration), `update_recipes` and the dimension list
  in `login` (play) come in hash-map order: the same bytes, another order,
  each time the oracle's process starts. One run's order is as good as
  another's; the goldens keep one.
- The player's entity id (`login`, `entity_event`) counts up per
  connection: 1 for the first player of a fresh process.
- The spawn position in `player_position` moves between fresh worlds, even
  with the same seed.
- Keep-alive ids are the oracle's clock.
- A player who joined before is a returning player: `recipe_book_add`
  and more change. Use `tools/oracle-lab.sh fresh` before recording.

## Pitfalls already met

- Stopping the oracle with `pkill -f <pattern>` can kill the shell that runs
  the command, when the pattern is in its own command line.
  `tools/oracle-lab.sh stop` matches the java process itself.
- Java 21 can't run the 26.3 jar: it needs 25.
- A send buffer smaller than the answer drops it without a word: the whole
  of configuration is about 68 KB.
- A Make target that lists only a test's own file runs a stale binary after
  a source change; every target now asks gnatmake, which rebuilds only what
  changed.
