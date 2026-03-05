# Chapter 15: First Web Endpoint

By the time a message reaches the outer gate, it has already passed through three rooms: the recorder who writes it, the runner who carries it, and the guard who reads it back before opening the latch. Ironhold does not trust silent pipes. It trusts explicit handoff.

Chapter 15 is the first network handoff in Runewarden. We take the reporting flow from previous chapters and serve it over HTTP.

Create:

```text
book/code/runewarden/chapters/ch15_first_web_endpoint/
  main.crn
  data/
    shift_day_005.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

`lib/core.crn` and `lib/shell.crn` carry forward from Chapter 14.

Use this data file:

```text
cave_in,7
gas_leak,2
rune_flare,1
```

Add `lib/shared.crn`:

```cairn
# Chapter-local shared helpers.

DEF argv_head_or : str -> str EFFECT io
  LET fallback
  ARGV LEN 0 GT
  IF
    ARGV HEAD
  ELSE
    fallback
  END
END

DEF argv_second_int_or : int -> int EFFECT io
  LET fallback
  ARGV LEN 1 GT
  IF
    fallback ARGV TAIL HEAD to_int_or
  ELSE
    fallback
  END
END
```

Add `lib/web.crn`:

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

DEF handle_report_request_with_source : str str str map[str str] map[str str] map[str str] map[str str] map[str str] -> str map[str str] int EFFECT io
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

  method "GET" EQ
  IF
    path "/" EQ
    IF
      source_path load_incidents_with_fallback LET incidents
      source_path incidents render_shift_summary_text
      http_text_ok
    ELSE
      "not found\n" http_text_not_found
    END
  ELSE
    "method not allowed\n" http_text_method_not_allowed
  END
END
```

Now `main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch15_first_web_endpoint/data/shift_day_005.txt" argv_head_or LET source_path
8125 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v0.7 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_request_with_source
} HTTP_SERVE
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch15_first_web_endpoint/main.crn
```

Then in another terminal:

```bash
curl http://127.0.0.1:8125/
```

You should get the live shift summary as plain text over HTTP.

The shape is the point. `HTTP_SERVE` owns transport. Our handler owns route policy and response content. The pure renderer is still pure. The I/O shell still owns file fallback and warnings. We added network delivery without collapsing those boundaries.

Chapter 16 will keep the same core and turn this single endpoint into explicit multi-route handling so the web surface can grow without becoming an if/else thicket.
