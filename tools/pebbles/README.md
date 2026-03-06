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

## Read-Only Dashboard

```bash
./cairn tools/pebbles/dashboard.crn
./cairn tools/pebbles/dashboard.crn 0.0.0.0 8094
```

Query params:

- `status=all|open|doing|blocked|done`
- `q=<text>` (case-insensitive match in title/reason/notes)
- dashboard re-reads datastore on each request, including Pebbles changes made by separate CLI invocations while the server is running

## Notes

- `ls` prints a summary line plus sorted pebble rows.
- `ls <status>` supports `all|open|doing|blocked|done`.
- rows show note counts as `(notes:N)` when notes exist.
- `find <text>` matches title, reason, and notes (case-insensitive).
- `export/import` uses a plain text `pebbles-v1` snapshot format for portability.
- v1 now supports lifecycle transitions, edits, search, and snapshots.
- dashboard is read-only and shares the same underlying Pebbles store.
- dashboard HTML is now template-backed (`tools/pebbles/templates/*.ctpl`) with typed view/context wrappers in `tools/pebbles/lib/dashboard/model.crn`.
- template trust boundary is explicit:
  - user-provided pebble text stays escaped before interpolation
  - raw placeholders (`{{{...}}}`) are used only for trusted internal HTML fragments composed by Cairn code
- Storage uses Cairn `DB_*` via prelude `data_*` helpers (default backend: Mnesia).
- Data location follows existing runtime configuration (`CAIRN_DB_DIR`, backend settings).
- Workflow conventions are in `tools/pebbles/WORKFLOW.md`.
