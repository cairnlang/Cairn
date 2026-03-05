# Chapter 21: Mnesia Default Backend

A ledger carved on a slate dies with the slate. Ironhold keeps the real books in the deep archive, where a shift change does not erase yesterday. The gate scribes still ask the same questions, but they no longer trust a single page on a single desk.

In this chapter we keep the Chapter 20 route and policy code almost untouched and swap only the datastore implementation underneath `store_*`.

Create:

```text
book/code/runewarden/chapters/ch21_mnesia_default_backend/
  main.crn
  data/
    shift_day_011.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
```

Carry `core`, `shell`, `shared`, and `web` from Chapter 20.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## Same Boundary, New Backend

`lib/web.crn` still calls:

- `store_load_incidents`
- `store_append_incident`
- `store_clear_crimson_incidents`

Only `lib/store.crn` changes.

## Mnesia Store Module

```cairn
IMPORT "shell.crn"

DEF store_key_for_source : str -> str EFFECT pure
  "runewarden:{}" FMT
END

DEF incident_not_crimson : incident -> bool EFFECT pure
  incident_alert Crimson EQ
  IF
    FALSE
  ELSE
    TRUE
  END
END

DEF store_put_incidents : [incident] str -> void EFFECT db
  LET incidents
  LET source_path

  source_path store_key_for_source LET key
  incidents serialize_incidents LET body
  body key data_put
END

DEF store_load_incidents : str -> [incident] EFFECT io
  LET source_path
  source_path store_key_for_source LET key

  key data_get
  MATCH
    Ok {
      parse_incident_lines
    }
    Err {
      DROP
      source_path load_incidents_with_fallback LET seeded
      source_path seeded store_put_incidents
      seeded
    }
  END
END

DEF store_append_incident : incident str -> [incident] EFFECT io
  LET incident
  LET source_path

  source_path store_load_incidents LET incidents
  incidents incident [] CONS CONCAT LET updated
  source_path updated store_put_incidents
  updated
END

DEF store_clear_crimson_incidents : str -> [incident] EFFECT io
  LET source_path

  source_path store_load_incidents
  { incident_not_crimson } FILTER
  LET cleaned
  source_path cleaned store_put_incidents
  cleaned
END
```

The key design point is lazy seeding:

- first read for a source key misses in DB
- store loads from file seed once
- store writes seeded value into Mnesia
- subsequent reads use DB value

This lets us migrate without a dedicated import command.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch21_mnesia_default_backend/data/shift_day_011.txt" argv_head_or LET source_path
8131 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v1.3 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch21_mnesia_default_backend/main.crn
```

## Persistence Check Across Restart

Run once, login, add one incident, stop server, run again, login again.

If Mnesia is active, the second run should still show the added incident even though the seed file did not change.

Example sequence:

```bash
curl -i -c /tmp/watch.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8131/login
curl -i -b /tmp/watch.cookies -X POST \
  -d 'kind=gas_leak&magnitude=5' \
  http://127.0.0.1:8131/add
# stop and restart server
curl -i -c /tmp/admin.cookies -X POST \
  -d 'username=thane&password=anvil' \
  http://127.0.0.1:8131/login
```

In Chapter 22 we keep this same Cairn-side `store_*` contract and switch the runtime data backend to Postgres.
