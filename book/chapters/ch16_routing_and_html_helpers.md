# Chapter 16: Routing And Html Helpers

At shift change, the outer gate does not ask one question. It asks several in order. Are you expected? Are you carrying sealed cargo? Are you here for inspection? The gate works because each path is explicit, and the fallback is explicit too.

Chapter 16 gives Runewarden that same shape for HTTP routes.

In Chapter 15 we had one endpoint and manual branching. Here we introduce a route chain: small route functions, combined with `route_or`, finalized with `route_finish_get`.

Create:

```text
book/code/runewarden/chapters/ch16_routing_and_html_helpers/
  main.crn
  data/
    shift_day_006.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

`lib/core.crn`, `lib/shell.crn`, and `lib/shared.crn` carry forward from Chapter 15.

Use this input file:

```text
cave_in,5
gas_leak,4
rune_flare,2
```

Now `lib/web.crn`:

```cairn
IMPORT "core.crn"
IMPORT "shell.crn"

DEF render_shift_summary_text : [incident] str -> str EFFECT pure
  LET incidents
  LET source_path

  incidents LEN LET incident_count
  incidents shift_total_score LET total_score
  incidents shift_max_score LET max_score
  incidents shift_crimson_count LET crimson_count
  incidents shift_alert_count_pairs LET grouped

  grouped crimson_count max_score total_score incident_count source_path
  "source={}\nincident_count={}\ntotal_score={}\nmax_score={}\ncrimson_count={}\ngrouped_by_alert={}\n" FMT
END

DEF route_get_root_report : str str str -> result[tuple[str map[str str] int] str] EFFECT io
  LET source_path
  LET method
  LET path

  method "GET" EQ
  path "/" EQ
  AND
  IF
    source_path load_incidents_with_fallback LET incidents
    source_path incidents render_shift_summary_text
    http_text_ok
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

DEF route_get_alerts : str str str -> result[tuple[str map[str str] int] str] EFFECT io
  LET source_path
  LET method
  LET path

  method "GET" EQ
  path "/alerts" EQ
  AND
  IF
    source_path load_incidents_with_fallback
    shift_alert_count_pairs
    source_path "source={}\nalerts={}\n" FMT
    http_text_ok
    http_pack_response
    Ok
  ELSE
    "no_match" Err
  END
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
  form DROP
  headers DROP
  cookies DROP
  session DROP

  path method source_path route_get_root_report
  path method route_get_health
  route_or
  path method source_path route_get_alerts
  route_or
  method route_finish_get
END
```

And `main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch16_routing_and_html_helpers/data/shift_day_006.txt" argv_head_or LET source_path
8126 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v0.8 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run the server:

```bash
./cairn book/code/runewarden/chapters/ch16_routing_and_html_helpers/main.crn
```

Then try:

```bash
curl -i http://127.0.0.1:8126/
curl -i http://127.0.0.1:8126/health
curl -i http://127.0.0.1:8126/alerts
curl -i http://127.0.0.1:8126/missing
curl -i -X POST http://127.0.0.1:8126/health
```

Expected shape is straightforward: report text on `/`, `ok` on `/health`, alert summary on `/alerts`, `404` for unknown GET paths, and `405` for non-GET methods.

The key gain is compositional routing. Each route is small and local. The chain reads top to bottom in priority order. Fallback behavior is centralized in `route_finish_get` instead of copied into each route.

Chapter 17 will keep this route structure and add form-based mutation so the web app can change state instead of only reporting it.
