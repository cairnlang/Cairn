# Chapter 17: Forms And Mutations

By the time the third bell sounds, the slate in the record hall is already wrong. The mine changed while the page was still drying. A report that cannot be amended is not a report, only a monument.

Today Runewarden learns to accept new incidents from the browser and write them back to disk. We keep the chapter deliberately narrow: one HTML form, one POST route, one file-backed mutation path, and the same route-chain style from Chapter 16.

Create:

```text
book/code/runewarden/chapters/ch17_forms_and_mutations/
  main.crn
  data/
    shift_day_007.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

Carry `lib/core.crn` and `lib/shared.crn` from Chapter 16.

Use this seed file:

```text
gas_leak,3
```

## Shell Boundary: Load And Save

`lib/shell.crn` keeps file IO and serialization out of route code:

```cairn
IMPORT "core.crn"

DEF parse_file_text : str -> result[[incident] str] EFFECT io
  READ_FILE
  { parse_incident_lines Ok } result_and_then
  { "cannot load incidents: {}" FMT } result_map_err
END

DEF emit_load_warning_if_any : result[[incident] str] -> void EFFECT io
  MATCH
    Ok { DROP }
    Err { "warn={}" FMT SAID }
  END
END

DEF load_incidents_with_fallback : str -> [incident] EFFECT io
  parse_file_text LET loaded
  loaded emit_load_warning_if_any
  [] loaded result_unwrap_or
END

DEF incident_to_line : incident -> str EFFECT pure
  MATCH
    CaveIn { "cave_in,{}" FMT }
    GasLeak { "gas_leak,{}" FMT }
    RuneFlare { "rune_flare,{}" FMT }
  END
END

DEF serialize_incidents : [incident] -> str EFFECT pure
  { incident_to_line } MAP
  "\n" JOIN
END

DEF save_incidents_to_path : [incident] str -> void EFFECT io
  LET incidents
  LET source_path

  incidents serialize_incidents LET body
  body LEN 0 GT
  IF
    body "\n" CONCAT LET final
    final source_path WRITE_FILE!
  ELSE
    "" source_path WRITE_FILE!
  END
END
```

The important boundary decision is this: route handlers decide *what* the new list should be; shell helpers decide *how* that list reaches the file.

## Web Layer: GET + POST

`lib/web.crn` adds form parsing and one mutation endpoint.

```cairn
IMPORT "shell.crn"

DEF form_incident_kind : map[str str] -> str EFFECT pure
  "kind" SWAP "gas_leak" map_get_or LOWER
END

DEF form_incident_magnitude : map[str str] -> int EFFECT pure
  "magnitude" SWAP "1" map_get_or
  1 SWAP to_int_or
  DUP 0 LT
  IF
    DROP 0
  END
END

DEF form_to_incident : map[str str] -> incident EFFECT pure
  LET form
  form form_incident_kind LET kind
  form form_incident_magnitude LET magnitude

  kind "cave_in" EQ
  IF
    magnitude CaveIn
  ELSE
    kind "rune_flare" EQ
    IF
      magnitude RuneFlare
    ELSE
      magnitude GasLeak
    END
  END
END

DEF render_incident_item_html : incident -> str EFFECT pure
  incident_to_line
  html_escape
  "<li>{}</li>" FMT
END

DEF render_incident_items_html : [incident] -> str EFFECT pure
  DUP LEN 0 EQ
  IF
    DROP
    "<li>no incidents yet</li>"
  ELSE
    { render_incident_item_html } MAP
    "\n" JOIN
  END
END

DEF render_report_page_html : [incident] str -> str EFFECT pure
  LET incidents
  LET source_path

  incidents LEN LET incident_count
  incidents shift_total_score LET total_score
  incidents shift_max_score LET max_score
  incidents shift_crimson_count LET crimson_count
  incidents shift_alert_count_pairs LET grouped
  incidents render_incident_items_html LET items_html
  source_path html_escape LET safe_source

  items_html grouped crimson_count max_score total_score incident_count safe_source "<!doctype html>\n<html lang=\"en\">\n  <head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n    <title>Runewarden</title>\n  </head>\n  <body>\n    <main>\n      <h1>Runewarden Report</h1>\n      <p>source: {}</p>\n      <p>incidents: {} | total_score: {} | max_score: {} | crimson_count: {}</p>\n      <p>alerts: {}</p>\n      <form method=\"post\" action=\"/add\">\n        <label>kind\n          <select name=\"kind\">\n            <option value=\"gas_leak\">gas_leak</option>\n            <option value=\"cave_in\">cave_in</option>\n            <option value=\"rune_flare\">rune_flare</option>\n          </select>\n        </label>\n        <label>magnitude\n          <input name=\"magnitude\" value=\"1\" />\n        </label>\n        <button type=\"submit\">add incident</button>\n      </form>\n      <ul>\n{}\n      </ul>\n    </main>\n  </body>\n</html>\n" FMT
END

DEF route_get_root_page : str str str -> result[tuple[str map[str str] int] str] EFFECT io
  LET source_path
  LET method
  LET path

  method "GET" EQ
  path "/" EQ
  AND
  IF
    source_path load_incidents_with_fallback LET incidents
    source_path incidents render_report_page_html
    http_html_ok
    http_pack_response
    Ok
  ELSE
    "no_match" Err
  END
END

DEF route_get_health : str str -> result[tuple[str map[str str] int] str] EFFECT pure
  LET method
  LET path
  path method "/health" "ok\n" route_get_text
END

DEF handle_report_routes_with_source : str str str map[str str] map[str str] map[str str] map[str str] map[str str] -> str map[str str] int EFFECT io
  LET source_path
  LET path
  LET method
  LET query
  LET form
  LET headers
  LET cookies
  LET session
  query DROP
  headers DROP
  cookies DROP
  session DROP

  method "GET" EQ
  IF
    path method source_path route_get_root_page
    path method route_get_health
    route_or
    method route_finish_get
  ELSE
    method "POST" EQ
    IF
      path "/add" EQ
      IF
        source_path load_incidents_with_fallback LET incidents
        form form_to_incident LET added
        incidents added [] CONS CONCAT LET updated
        source_path updated save_incidents_to_path
        updated LET incidents
        source_path incidents render_report_page_html
        http_html_ok
      ELSE
        "not found\n" http_text_not_found
      END
    ELSE
      "method not allowed\n" http_text_method_not_allowed
    END
  END
END
```

The POST branch does three things, in order:

1. Read current incidents.
2. Build one new `incident` from form fields.
3. Persist the appended list, then render the updated page.

No silent magic, no hidden mutation point.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch17_forms_and_mutations/data/shift_day_007.txt" argv_head_or LET source_path
8127 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v0.9 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch17_forms_and_mutations/main.crn
```

Then in another shell:

```bash
curl -i http://127.0.0.1:8127/
curl -i -X POST \
  -d 'kind=cave_in&magnitude=4' \
  http://127.0.0.1:8127/add
curl -i http://127.0.0.1:8127/
```

After the POST, the rendered report should show one extra incident, and `shift_day_007.txt` should include the new line.

## Why This Matters

This is the first chapter where the web edge changes program state. It is still small, but it establishes three habits we will keep:

- Keep domain transformations pure when possible.
- Isolate IO in explicit shell helpers.
- Make mutation routes easy to read from top to bottom.

In Chapter 18 we will stop pretending every request is stateless and add cookies plus sessions.
