# Chapter 20: Datastore Boundary

The stone ledgers of Ironhold are not kept at the gate. The gate decides who may pass; the archive decides how records are read and written. If one clerk changes writing tools, the guard rotation should not change with him.

That is the chapter move: split persistence orchestration out of route handlers and into a datastore boundary module.

Create:

```text
book/code/runewarden/chapters/ch20_datastore_boundary/
  main.crn
  data/
    shift_day_010.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
```

Carry `core`, `shell`, and `shared` from Chapter 19.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## Why A Boundary

In Chapter 19, web handlers still performed read/transform/write sequences directly.

That was workable, but it coupled HTTP routes to storage mechanics. The coupling gets painful as soon as you add a second backend.

The boundary in this chapter is a new module, `lib/store.crn`, with exactly three operations.

## Store Module

```cairn
IMPORT "shell.crn"

DEF incident_not_crimson : incident -> bool EFFECT pure
  incident_alert Crimson EQ
  IF
    FALSE
  ELSE
    TRUE
  END
END

DEF store_load_incidents : str -> [incident] EFFECT io
  load_incidents_with_fallback
END

DEF store_append_incident : incident str -> [incident] EFFECT io
  LET incident
  LET source_path

  source_path load_incidents_with_fallback LET incidents
  incidents incident [] CONS CONCAT LET updated
  source_path updated save_incidents_to_path
  updated
END

DEF store_clear_crimson_incidents : str -> [incident] EFFECT io
  LET source_path

  source_path load_incidents_with_fallback
  { incident_not_crimson } FILTER
  LET cleaned
  source_path cleaned save_incidents_to_path
  cleaned
END
```

The web layer no longer knows how file parsing or serialization works. It asks the store for domain values.

## Web Layer Changes

`lib/web.crn` imports `store.crn` and replaces direct shell persistence calls.

Add incident route, before:

```cairn
source_path load_incidents_with_fallback LET incidents
form form_to_incident LET added
incidents added [] CONS CONCAT LET updated
source_path updated save_incidents_to_path
```

After:

```cairn
form form_to_incident LET added
source_path added store_append_incident LET updated
```

Admin clear route, before:

```cairn
source_path load_incidents_with_fallback
clear_crimson_incidents LET cleaned
source_path cleaned save_incidents_to_path
```

After:

```cairn
source_path store_clear_crimson_incidents LET cleaned
```

The route intent is now obvious: authenticate, authorize, call store operation, render.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch20_datastore_boundary/data/shift_day_010.txt" argv_head_or LET source_path
8130 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v1.2 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch20_datastore_boundary/main.crn
```

Smoke check:

```bash
curl -i http://127.0.0.1:8130/health
curl -i -c /tmp/watch.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8130/login
curl -i -b /tmp/watch.cookies -X POST \
  -d 'kind=gas_leak&magnitude=5' \
  http://127.0.0.1:8130/add
curl -i -c /tmp/admin.cookies -X POST \
  -d 'username=thane&password=anvil' \
  http://127.0.0.1:8130/login
curl -i -b /tmp/admin.cookies -X POST \
  http://127.0.0.1:8130/admin/clear-crimson
```

Chapter 21 will keep the same `store_*` surface and swap implementation details underneath it using Mnesia.
