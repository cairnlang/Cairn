# Chapter 28: Capstone Assembly

A full shift in Ironhold begins before the gate opens. The foreman runs a safety drill, verifies replacements are working, then opens the reporting desk for the day. This chapter assembles our language pieces into that same order.

Runewarden now does two things in one executable flow:

1. actor supervision preflight (fail once, restart once)
2. authenticated web reporting service with datastore boundary

Create:

```text
book/code/runewarden/chapters/ch28_capstone_assembly/
  main.crn
  data/
    shift_day_014.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
    supervision.crn
    mine_watch.crn
```

`core/shell/shared/store/web` are carried from Chapter 23.
`supervision.crn` comes from Chapter 27.
`mine_watch.crn` wraps the Chapter 27 watcher lifecycle as a callable preflight.

## Preflight Module

`lib/mine_watch.crn` exposes:

```cairn
DEF run_mine_watch_preflight : void EFFECT io
```

Behavior:

- starts a failing watcher (`Crash`)
- monitors and records the first exit reason
- starts a healthy watcher (`ScanA5`, `ScanA9`, `ScanA4`, `Report`)
- monitors and records normal second exit

This gives a bounded runtime confidence check before starting the web edge.

## Capstone Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/mine_watch.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch28_capstone_assembly/data/shift_day_014.txt" argv_head_or LET source_path
8134 argv_second_int_or LET port
"127.0.0.1" LET bind_host
"mnesia" data_backend_or LET active_backend

"capstone=run preflight checks" SAID
run_mine_watch_preflight

active_backend source_path port bind_host "capstone=web serving http://{}:{}/ (source={}, backend={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

The important design point is sequencing:

- actor lifecycle checks first
- persistent/reporting service second

## Run

```bash
./cairn book/code/runewarden/chapters/ch28_capstone_assembly/main.crn
```

Expected startup shape:

```text
capstone=run preflight checks
preflight=mine_watch starting failing watcher
preflight first_exit=watcher_crash_simulated
preflight=mine_watch restarting watcher
...scan output...
preflight second_exit=normal
capstone=web serving http://127.0.0.1:8134/ (...)
```

Then verify service is up:

```bash
curl -i http://127.0.0.1:8134/health
```

Chapter 29 will review this assembled system as a safety/hardening pass and identify what still needs explicit guards before production use.
