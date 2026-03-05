# Chapter 18: Sessions Cookies And Login

A gate without memory is no gate at all. If every guard greets every face as a stranger, the city survives only by luck. Ironhold solved this long ago with stamped brass tokens: present one at the right post, and the watch knows who trusted you in the first place.

Today we teach Runewarden the same trick. We keep HTTP stateless at the wire, but we add a session layer so the app can remember who is signed in.

Create:

```text
book/code/runewarden/chapters/ch18_sessions_cookies_and_login/
  main.crn
  data/
    shift_day_008.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

Carry `lib/core.crn`, `lib/shell.crn`, and `lib/shared.crn` from Chapter 17.

Use this seed data:

```text
gas_leak,3
rune_flare,1
```

## One New Boundary Rule

The chapter handler now returns four values instead of three:

- `body`
- `headers`
- `session`
- `status`

That extra `session` value is how `HTTP_SERVE` decides whether to issue `Set-Cookie`, keep the existing session, or clear it.

`lib/web.crn` starts with tiny helpers:

```cairn
IMPORT "shell.crn"

DEF logged_in_p : map[str str] -> bool EFFECT pure
  session_has_user
END

DEF current_user_name : map[str str] -> str EFFECT pure
  "user" SWAP "" map_get_or
END

DEF with_session : map[str str] str map[str str] int -> str map[str str] map[str str] int EFFECT pure
  LET session
  LET body
  LET headers
  LET status
  status session headers body
END
```

`with_session` is just stack plumbing: if a response does not mutate session state, preserve the incoming session untouched.

## Login Page And Report Page

We render either the login page or the authenticated report page.

```cairn
DEF render_login_page : str -> str map[str str] int EFFECT pure
  LET error_message

  error_message LEN 0 GT
  IF
    error_message html_escape
    "<p><mark>{}</mark></p>" FMT
  ELSE
    ""
  END
  LET error_html

  error_html "<!doctype html>\n<html lang=\"en\">\n  <head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n    <title>Runewarden Login</title>\n  </head>\n  <body>\n    <main>\n      <h1>Runewarden Access</h1>\n      <p>Sign in to inspect and amend the shift report.</p>\n      {}\n      <form method=\"post\" action=\"/login\">\n        <label>username <input name=\"username\" value=\"warden\" /></label>\n        <label>password <input name=\"password\" type=\"password\" value=\"ironhold\" /></label>\n        <button type=\"submit\">sign in</button>\n      </form>\n    </main>\n  </body>\n</html>\n" FMT
  http_html_ok
END
```

The authenticated page keeps the Chapter 17 report and adds a logout form.

## Route Flow

The central handler enforces three rules:

1. `GET /` shows report when logged in, login page otherwise.
2. `POST /login` validates credentials and writes session keys.
3. `POST /add` is rejected unless a session user exists.

```cairn
DEF handle_report_routes_with_source : str str str map[str str] map[str str] map[str str] map[str str] map[str str] -> str map[str str] map[str str] int EFFECT io
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

  method "GET" EQ
  IF
    path "/" EQ
    IF
      session logged_in_p
      IF
        source_path load_incidents_with_fallback LET incidents
        session current_user_name LET username
        username source_path incidents render_report_page_html
        session with_session
      ELSE
        "" render_login_page
        session with_session
      END
    ELSE
      path "/login" EQ
      IF
        "" render_login_page
        session with_session
      ELSE
        path method "/health" "ok\n" route_get_text
        route_finish
        session with_session
      END
    END
  ELSE
    method "POST" EQ
    IF
      path "/login" EQ
      IF
        "username" form "" map_get_or TRIM LET username
        "password" form "" map_get_or TRIM LET password

        username "warden" EQ
        password "ironhold" EQ
        AND
        IF
          source_path load_incidents_with_fallback LET incidents
          username source_path incidents render_report_page_html
          LET body
          LET headers
          LET status
          status session headers body "role" "watch" session_put
          "user" username session_put
        ELSE
          "invalid credentials" render_login_page
          session with_session
        END
      ELSE
        path "/logout" EQ
        IF
          "" render_login_page
          LET body
          LET headers
          LET status
          status session headers body session_clear
        ELSE
          path "/add" EQ
          IF
            session logged_in_p
            IF
              source_path load_incidents_with_fallback LET incidents
              form form_to_incident LET added
              incidents added [] CONS CONCAT LET updated
              source_path updated save_incidents_to_path
              session current_user_name LET username
              username source_path updated render_report_page_html
              session with_session
            ELSE
              "login required\n" http_text_unauthorized
              session with_session
            END
          ELSE
            "not found\n" http_text_not_found
            session with_session
          END
        END
      END
    ELSE
      "method not allowed\n" http_text_method_not_allowed
      session with_session
    END
  END
END
```

Note the successful login path:

```cairn
status session headers body "role" "watch" session_put
"user" username session_put
```

The first `session_put` writes role, the second writes user. The runtime serializes that session map and emits the session cookie automatically.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch18_sessions_cookies_and_login/data/shift_day_008.txt" argv_head_or LET source_path
8128 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v1.0 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch18_sessions_cookies_and_login/main.crn
```

Then test with a cookie jar:

```bash
curl -i -c /tmp/runewarden.cookies http://127.0.0.1:8128/
curl -i -b /tmp/runewarden.cookies -X POST \
  -d 'kind=cave_in&magnitude=4' \
  http://127.0.0.1:8128/add
curl -i -b /tmp/runewarden.cookies -c /tmp/runewarden.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8128/login
curl -i -b /tmp/runewarden.cookies -X POST \
  -d 'kind=cave_in&magnitude=4' \
  http://127.0.0.1:8128/add
curl -i -b /tmp/runewarden.cookies -X POST http://127.0.0.1:8128/logout
```

Expected behavior:

- first `/` request renders login page
- unauthenticated `/add` returns `401 Unauthorized`
- `/login` returns report page and sets cookie
- authenticated `/add` mutates the report file
- `/logout` clears session and returns login page

Chapter 19 will keep this session foundation and add authorization policy checks so login is not the only gate.
