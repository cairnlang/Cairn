# Chapter 23: Operational Testing

Ironhold does not trust a machine because it worked once in front of a magistrate. Every shift master keeps a short ritual: check the warning bell, check the gate seal, check that yesterday’s record still exists after the lamps are relit. Reliability is a habit, not a speech.

This chapter turns Runewarden into that habit. We add repeatable smoke scripts that exercise the full web flow and restart persistence for both datastore backends.

Create:

```text
book/code/runewarden/chapters/ch23_operational_testing/
  main.crn
  data/
    shift_day_013.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
  scripts/
    common.sh
    run_smoke_mnesia.sh
    run_smoke_postgres.sh
```

Carry `lib/*` from Chapter 22.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## Why Operational Scripts

Unit and property tests are necessary but not sufficient for a web service boundary. We also need short end-to-end checks that answer practical questions quickly:

- does the server start and become healthy?
- do auth gates still behave as expected?
- does mutation persist across process restart?
- do these claims hold on both Mnesia and Postgres?

## Shared Script Helpers

`scripts/common.sh` provides small primitives:

- `wait_for_health PORT`
- `assert_status RESPONSE CODE`
- `assert_contains RESPONSE NEEDLE`
- `start_server SOURCE PORT [ENV...]`

`start_server` records the PID for clean restart checks.

## Mnesia Smoke Script

`scripts/run_smoke_mnesia.sh` checks:

1. unauthenticated `POST /add` is rejected (unauthorized page)
2. watch login sees seeded `incidents: 3`
3. add operation yields `incidents: 4`
4. after restart, admin login still sees `incidents: 4`

Run:

```bash
book/code/runewarden/chapters/ch23_operational_testing/scripts/run_smoke_mnesia.sh
```

Expected tail:

```text
[mnesia] smoke checks passed
```

## Postgres Smoke Script

`scripts/run_smoke_postgres.sh` adds a temporary Postgres container and runs the same flow with backend env wiring:

- `CAIRN_DATA_STORE_BACKEND=postgres`
- `CAIRN_PG_HOST`
- `CAIRN_PG_PORT`
- `CAIRN_PG_DATABASE`
- `CAIRN_PG_USER`
- `CAIRN_PG_PASSWORD`
- `CAIRN_PG_SSLMODE`

Run:

```bash
book/code/runewarden/chapters/ch23_operational_testing/scripts/run_smoke_postgres.sh
```

Expected tail:

```text
[postgres] smoke checks passed
```

## Entrypoint

`main.crn` stays simple and reports the active backend:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch23_operational_testing/data/shift_day_013.txt" argv_head_or LET source_path
8133 argv_second_int_or LET port
"127.0.0.1" LET bind_host
"mnesia" data_backend_or LET active_backend

active_backend source_path port bind_host "Runewarden v1.5 web: serving http://{}:{}/ (source={}, backend={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

The app surface did not change. The tests around it became more operational and repeatable.

Chapter 24 will move us into actor workflows for mine-watch coordination while keeping this operations discipline in place.
