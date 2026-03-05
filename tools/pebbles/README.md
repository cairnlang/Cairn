# Pebbles (v1)

Single-agent local task tracker in Cairn.

## Commands

```bash
./cairn tools/pebbles/main.crn init
./cairn tools/pebbles/main.crn add "draft migration notes"
./cairn tools/pebbles/main.crn ls
./cairn tools/pebbles/main.crn next
./cairn tools/pebbles/main.crn do 1
./cairn tools/pebbles/main.crn done 1
./cairn tools/pebbles/main.crn reopen 1
./cairn tools/pebbles/main.crn block 2 "waiting on review"
./cairn tools/pebbles/main.crn note 2 "unblocked after deploy"
./cairn tools/pebbles/main.crn edit 1 "final migration notes"
./cairn tools/pebbles/main.crn ls blocked
./cairn tools/pebbles/main.crn find review
./cairn tools/pebbles/main.crn export pebbles.snapshot
./cairn tools/pebbles/main.crn import pebbles.snapshot
```

## Notes

- `ls` prints a summary line plus sorted pebble rows.
- `ls <status>` supports `all|open|doing|blocked|done`.
- rows show note counts as `(notes:N)` when notes exist.
- `find <text>` matches title, reason, and notes (case-insensitive).
- `export/import` uses a plain text `pebbles-v1` snapshot format for portability.
- v1 now supports lifecycle transitions, edits, search, and snapshots.
- Storage uses Cairn `DB_*` via prelude `data_*` helpers (default backend: Mnesia).
- Data location follows existing runtime configuration (`CAIRN_DB_DIR`, backend settings).
- Workflow conventions are in `tools/pebbles/WORKFLOW.md`.
