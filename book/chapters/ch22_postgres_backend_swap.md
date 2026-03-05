# Chapter 22: Postgres Backend Swap

Ironhold keeps two archives: the stone hall under the keep, and the ledger house across the river where merchants reconcile every ingot twice. The forms differ, the clerks differ, but the guard at the gate should not care which archive answers a query.

This chapter performs that exact move. We keep Runewarden’s Cairn app shape unchanged and switch the runtime datastore backend from Mnesia to Postgres.

Create:

```text
book/code/runewarden/chapters/ch22_postgres_backend_swap/
  main.crn
  data/
    shift_day_012.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
```

Carry `lib/core.crn`, `lib/shell.crn`, `lib/store.crn`, and `lib/web.crn` from Chapter 21.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## No New App API

The point of Chapters 20-22 is now visible:

- web routes still call `store_load_incidents`, `store_append_incident`, `store_clear_crimson_incidents`
- `store.crn` still talks through `data_get/data_put`
- the backend decision is runtime configuration, not application rewrites

## Entrypoint With Backend Visibility

`main.crn` now reports which backend is active:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch22_postgres_backend_swap/data/shift_day_012.txt" argv_head_or LET source_path
8132 argv_second_int_or LET port
"127.0.0.1" LET bind_host
"mnesia" data_backend_or LET active_backend

active_backend source_path port bind_host "Runewarden v1.4 web: serving http://{}:{}/ (source={}, backend={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

And `lib/shared.crn` gets one helper:

```cairn
DEF data_backend_or : str -> str EFFECT io
  LET fallback
  [ "CAIRN_DATA_STORE_BACKEND" ] HOST_CALL env_get LET configured
  configured LEN 0 GT
  IF
    configured
  ELSE
    fallback
  END
END
```

## Run On Postgres

You can use a local Postgres and set runtime env vars directly:

```bash
CAIRN_DATA_STORE_BACKEND=postgres \
CAIRN_PG_HOST=127.0.0.1 \
CAIRN_PG_PORT=55433 \
CAIRN_PG_DATABASE=cairn \
CAIRN_PG_USER=postgres \
CAIRN_PG_PASSWORD=postgres \
CAIRN_PG_SSLMODE=disable \
./cairn book/code/runewarden/chapters/ch22_postgres_backend_swap/main.crn
```

If you want a one-command project harness for Postgres integration tests, use:

```bash
bash scripts/test_pg.sh
```

## Isolated Smoke Flow

With backend set to Postgres:

```bash
curl -i -c /tmp/watch.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8132/login
curl -i -b /tmp/watch.cookies -X POST \
  -d 'kind=gas_leak&magnitude=5' \
  http://127.0.0.1:8132/add
# restart the app process
curl -i -c /tmp/admin.cookies -X POST \
  -d 'username=thane&password=anvil' \
  http://127.0.0.1:8132/login
```

After restart, the report should still include the added incident (`incidents: 4`), showing that persistence is now provided by Postgres under the same Cairn-side store contract.

Chapter 23 will focus on operational testing: repeatable checks for these end-to-end behaviors across backend choices.
