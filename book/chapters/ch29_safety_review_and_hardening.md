# Chapter 29: Safety Review And Hardening

A city survives not by one perfect shift, but by habits that make bad shifts less dangerous. Ironhold assumes malformed reports, wrong forms, and careless clients will appear every day. The gate must refuse bad input clearly and still keep the ledger sane.

This chapter is a hardening pass over the Chapter 28 capstone.

Create:

```text
book/code/runewarden/chapters/ch29_safety_review_and_hardening/
  main.crn
  data/
    shift_day_015.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
    supervision.crn
    mine_watch.crn
    hardening.crn
```

Carry the capstone modules from Chapter 28. Add `hardening.crn` and update `web.crn`.

## Hardening Helpers

`lib/hardening.crn` centralizes boundary response policy:

```cairn
DEF http_html_bad_request : str -> str map[str str] int EFFECT pure
  400
  M[ "Content-Type" "text/html; charset=utf-8" ]
  ROT
END

DEF harden_response_headers : str map[str str] int -> str map[str str] int EFFECT pure
  "X-Content-Type-Options" "nosniff" http_add_header
  "X-Frame-Options" "DENY" http_add_header
  "Referrer-Policy" "no-referrer" http_add_header
  "Cache-Control" "no-store" http_add_header
  "Content-Security-Policy" "default-src 'self'; style-src 'self' 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'" http_add_header
END
```

Every HTML renderer now ends with `harden_response_headers`.

## Strict Incident Input Validation

`form_to_incident` now returns `result[incident str]` instead of silently coercing invalid input:

```cairn
DEF form_to_incident : map[str str] -> result[incident str] EFFECT pure
```

Rules:

- `kind` must be one of: `gas_leak`, `cave_in`, `rune_flare`
- `magnitude` must parse as integer
- `magnitude` must be in `0..10`

In the `/add` route, invalid input returns a hardened `400 Bad Request` page.

## Login Form Cleanup

Login form fields no longer prefill credentials. They now use autocomplete hints only:

- `autocomplete="username"`
- `autocomplete="current-password"`

## Capstone Entrypoint

`main.crn` remains the Chapter 28 assembly shape, with updated path/port/version:

```cairn
"book/code/runewarden/chapters/ch29_safety_review_and_hardening/data/shift_day_015.txt" argv_head_or LET source_path
8135 argv_second_int_or LET port
...
"capstone=v1.6 web serving http://{}:{}/ (source={}, backend={})" FMT SAID
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch29_safety_review_and_hardening/main.crn
```

Check startup:

```bash
curl -i http://127.0.0.1:8135/health
```

Check headers on a rendered page:

```bash
curl -i -X POST -d 'username=warden&password=ironhold' http://127.0.0.1:8135/login
```

You should see `CSP`, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, and `Cache-Control`.

Check strict bad request path (authenticated):

```bash
curl -i -c /tmp/ch29.cookies -X POST -d 'username=warden&password=ironhold' http://127.0.0.1:8135/login
curl -i -b /tmp/ch29.cookies -X POST -d 'kind=oops&magnitude=999' http://127.0.0.1:8135/add
```

Expected result: `HTTP/1.1 400 Bad Request` with a bounded error page.

Chapter 30 closes the book with a clear map of what to build next and what to stabilize before broader usage.
