# Chapter 19: Authorization In Ironhold

Knowing a name is not the same as granting authority. Ironhold does not hand a blasting rune to every miner who can spell it. One guard checks identity; another checks whether that identity may perform the act.

Chapter 18 gave us login and sessions. Chapter 19 adds role-based authorization and a concrete admin-only action.

Create:

```text
book/code/runewarden/chapters/ch19_authorization_in_ironhold/
  main.crn
  data/
    shift_day_009.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

Carry `lib/core.crn`, `lib/shell.crn`, and `lib/shared.crn` from Chapter 18.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## Policy Shape

This chapter uses two identities:

- `warden / ironhold` with role `watch`
- `thane / anvil` with role `admin`

We reuse the prelude guard helpers:

- `guard_require_login`
- `guard_require_role`

Role checks live in route branches, not hidden in runtime code.

## Core Additions

`lib/web.crn` introduces role-aware helpers:

```cairn
DEF current_user_role : map[str str] -> str EFFECT pure
  "role" SWAP "" map_get_or
END

DEF incident_not_crimson : incident -> bool EFFECT pure
  incident_alert Crimson EQ
  IF
    FALSE
  ELSE
    TRUE
  END
END

DEF clear_crimson_incidents : [incident] -> [incident] EFFECT pure
  { incident_not_crimson } FILTER
END
```

`clear_crimson_incidents` is the admin-only mutation used in this chapter.

## Admin Route

`GET /admin` requires both login and role:

```cairn
path "/admin" EQ
IF
  session guard_require_login
  IF
    session "admin" guard_require_role
    IF
      source_path load_incidents_with_fallback LET incidents
      session current_user_name incidents render_admin_page_html
      session with_session
    ELSE
      render_forbidden_page
      session with_session
    END
  ELSE
    render_unauthorized_page
    session with_session
  END
```

This branch makes the difference explicit:

- not logged in: unauthorized
- logged in, wrong role: forbidden
- logged in, admin role: admin page

## Admin-Only Mutation

`POST /admin/clear-crimson` uses the same guard sequence:

```cairn
path "/admin/clear-crimson" EQ
IF
  session guard_require_login
  IF
    session "admin" guard_require_role
    IF
      source_path load_incidents_with_fallback
      clear_crimson_incidents LET cleaned
      source_path cleaned save_incidents_to_path
      session current_user_name cleaned render_admin_page_html
      session with_session
    ELSE
      render_forbidden_page
      session with_session
    END
  ELSE
    render_unauthorized_page
    session with_session
  END
```

This is a real policy gate, not a cosmetic one. The file only changes on the admin path.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch19_authorization_in_ironhold/data/shift_day_009.txt" argv_head_or LET source_path
8129 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v1.1 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch19_authorization_in_ironhold/main.crn
```

Try this sequence:

```bash
# unauthenticated admin page
curl -i http://127.0.0.1:8129/admin

# watch login
curl -i -c /tmp/watch.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8129/login

# forbidden for watch role
curl -i -b /tmp/watch.cookies http://127.0.0.1:8129/admin
curl -i -b /tmp/watch.cookies -X POST http://127.0.0.1:8129/admin/clear-crimson

# admin login
curl -i -c /tmp/admin.cookies -X POST \
  -d 'username=thane&password=anvil' \
  http://127.0.0.1:8129/login

# admin can access and mutate
curl -i -b /tmp/admin.cookies http://127.0.0.1:8129/admin
curl -i -b /tmp/admin.cookies -X POST http://127.0.0.1:8129/admin/clear-crimson
```

After the final POST, `shift_day_009.txt` should no longer contain crimson incidents.

Chapter 20 will separate policy and storage concerns more formally so this web layer stops carrying all orchestration responsibilities itself.
