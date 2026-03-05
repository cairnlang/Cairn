# Pebbles (v1)

Single-agent local task tracker in Cairn.

## Commands

```bash
./cairn tools/pebbles/main.crn init
./cairn tools/pebbles/main.crn add "draft migration notes"
./cairn tools/pebbles/main.crn ls
```

## Notes

- v1 is intentionally small: `init`, `add`, and `ls`.
- Storage uses Cairn `DB_*` via prelude `data_*` helpers (default backend: Mnesia).
- Data location follows existing runtime configuration (`CAIRN_DB_DIR`, backend settings).
