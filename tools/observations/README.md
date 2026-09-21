# Offline observation archives

`quest_observations.py` is a Python 3 standard-library CLI for an exported
`RIKQ1` packet. It does not contact a server, read client memory, launch the game,
write settings, ingest a quest corpus, or promote observations into world facts.

Save the complete exported packet to a text file, then inspect it:

```text
python quest_observations.py inspect quest-export.txt
```

Create a durable archive with explicit identity checks:

```text
python quest_observations.py import quest-export.txt --out observation.json --expect-product forever --expect-build 1.60.1.69913 --expect-locale enUS
```

The output must not already exist, and its parent directory must exist. Existing
files, directories, and symlinks are never overwritten. A failed validation
creates no output. The importer accepts one terminal LF or CRLF added by a text
editor, records this normalization, and rejects all other packet whitespace.

Verify a saved archive without changing it:

```text
python quest_observations.py verify observation.json --expect-product forever --expect-build 1.60.1.69913 --expect-locale enUS
```

Verification rereads bounded durable bytes, decodes the retained packet again,
and compares its hashes, identity, lossless snapshot and inspection with the
archive. Duplicate JSON fields and modified derived content are rejected.
The recorded parser hash remains historical provenance; verification does not
execute archived code or authenticate the originating client.

All three commands print a JSON summary with declared identity, log coverage/counts,
ordered quest IDs/titles, packet hash, and limitations. Exit status is 0 on
success or 2 on an input/IO error. The optional expected identity flags reject a
mismatch; without flags, another identity is preserved exactly, never relabelled
as Forever. The archive has no implicit current-character or current-build role.

## Archive contract

`rikui-observation-archive-v1` retains the original packet, input-file and packet
SHA256, Adler32, parser revision and source hash, and the decoded snapshot. Both
the archive and decoded snapshot have `origin: imported-untrusted`. Original
packet bytes remain unchanged even when the packet originally claimed another
origin. Hashes and checksums establish byte integrity only, not authenticity.

The `snapshotEncoding` is `lua-table-pairs-utf8-or-bytes-v1`:

- Every Lua table is `{ "$table": [[key, value], ...] }`, including empty tables.
- Valid UTF-8 byte strings become JSON strings; other byte strings become
  `{ "$bytes": "lowercase-hex" }`.
- Finite numbers and booleans remain JSON scalars.
- Keys retain numeric/string types. Numeric `1` and string `"1"` remain distinct.

This representation preserves data that plain JSON objects cannot represent
without collisions or coercion. The original `packet` is also retained for exact
future decoding. The human-readable `inspection` is only an inventory, not a
replacement for the lossless snapshot.

The decoder follows `quest-transfer.lua`'s structural snapshot contract. It does
not infer stronger validation of arbitrary quest fields, prerequisite chains,
XP, historical turn-in, NPC locations, or travel. `objectivesComplete` remains
just an observed field. Imported history is isolated from settings transport.

Limits match RIKQ1: 131,072 wire bytes, 65,528 payload bytes, 16,384 decode nodes,
depth 16, 2,048 bytes per string/numeric scalar, 256 ordered quests, bounded
integer IDs, and exact canonical lengths/numbers. Archive output is capped at
2 MiB. No Lua code or other packet content is executed by the importer.

## Session journal selection

Current addon exports preserve the complete current snapshot and context, then
include the largest fitting newest contiguous suffix of the 48-entry session
journal. `journal.export` records available, exported and omitted entry counts;
`journal.dropped` independently counts entries already lost from the ring. The
copy window discloses export omissions. A packet is not a complete session history
when either count is nonzero. Export never trims the current snapshot to make it
fit, mutates live observations, or hides invalid older records through selection.

Initial observations are not progress. Contextual gossip offers do not establish
universal quest requirements, player interaction positions are not NPC positions,
and received turn-in XP is not base XP. Historical packets retain their original
labels and fields; this importer does not rewrite them using newer interpretations.

## Validation

```text
python -m unittest -v test_quest_observations
```

The 39 tests include valid/partial snapshots, mixed keys, arbitrary bytes,
control characters, preserved identity, duplicate/invalid keys, checksum and
framing corruption, nonfinite/noncanonical numbers, wire/node/depth boundaries,
quest/order mismatch, output preservation, and simulated failed writes.

For a differential check against real repository Lua sources:

```text
python validate_lua_transfer.py --schema PATH/quest-schema.lua --transfer PATH/quest-transfer.lua --out NEW_PROOF_DIRECTORY
```

This requires `luajit` on PATH (or `--luajit PATH`), but the importer itself has no
Lua dependency. `lua_transfer_probe.lua` generates a clearly synthetic snapshot
using the actual encoder; Python decodes it, archives it, and compares acceptance
of 460 valid/malformed packets to the actual Lua decoder. The generated fixture
includes 1,028 boundary/random numbers and mixed keys/byte strings. These are
protocol fixtures, not native observations or verified quest content.

The integrated proof runs directly against repository sources without modifying
their validation rules. Keep generated proof artifacts and character packets
outside Git and addon settings.
