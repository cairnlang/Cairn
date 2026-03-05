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
./cairn tools/pebbles/main.crn block 2 "waiting on review"
```

## Notes

- v1 now supports the first lifecycle flow: `open -> doing -> done` and `block`.
- Storage uses Cairn `DB_*` via prelude `data_*` helpers (default backend: Mnesia).
- Data location follows existing runtime configuration (`CAIRN_DB_DIR`, backend settings).
