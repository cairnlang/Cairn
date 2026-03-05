# Cairn Effect Guidelines (Slice A Audit)

Date: March 5, 2026

## Purpose

Keep effectful code disciplined while preserving Cairn's current practical model.
This document defines the canonical pattern for `pure`/`io`/`db`/`http` and records the current baseline before Slice B ergonomics work.

## Effect Model Today

- Effects are declared per function: `EFFECT pure | io | db | http`.
- If omitted, a function defaults to `io`.
- `pure` functions cannot call effectful functions or use effectful built-ins.
- Runtime PROVE checks only run on `pure` functions.

Checker-marked effectful operators currently include:

- `ARGV`, `READ_LINE`, `SAY`, `PRINT`, `SAID`
- `READ_FILE`, `WRITE_FILE`, `READ_FILE!`, `WRITE_FILE!`
- `HTTP_SERVE`
- `DB_PUT`, `DB_GET`, `DB_DEL`, `DB_PAIRS`
- `AUTH_CHECK`
- `ASK`, `ASK!`
- `RANDOM`
- `HOST_CALL`

## Canonical Pattern

### 1) Pure Core, Effectful Shell

- Put business rules/transforms in `EFFECT pure`.
- Put boundary interactions (I/O, DB, HTTP, interop) in thin effectful functions.

### 2) Result-First Boundaries

- Boundary functions should return `result[...]` where practical.
- Convert to user-facing response shape at the edge.
- Keep pure logic operating on typed values, not ambient boundary state.

### 3) Explicit Error Mapping at Edges

- Boundary shells should map raw failure to domain-level strings/messages once.
- Core functions should avoid ad-hoc `Err` text construction where possible.

## Preferred Function Shape

```text
DEF parse_input : str -> result[domain str] EFFECT pure
  ...
END

DEF run_file_flow : str -> result[domain str] EFFECT io
  READ_FILE
  result_and_then parse_input
END
```

## Audit Snapshot

### Good

- Prelude is mostly effect-disciplined:
  - `lib/prelude/result.crn`: pure helpers.
  - `lib/prelude/config.crn`: pure parsing helpers.
  - `lib/prelude/web.crn`: mostly pure, with explicit `http` where file-serving is used.
- Web examples already separate rendering/policy (`pure`) from transport (`http`) and storage (`db`) reasonably well.

### Inconsistencies / Debt

- Many older non-library examples still omit `EFFECT`, implicitly becoming `io`.
  - This weakens readability and can mask accidental impurity.
- Some signatures still use bare `result` instead of parameterized `result[T E]` outside the shared library surface.
  - Works due current normalization but is less explicit.
- DB usage in Cairn source is still operation-shaped (`DB_*`), but runtime routing now goes through `Cairn.DataStore`.
  - This improves backend pluggability without changing core language syntax yet.

## Rules For New Code (Starting Now)

- Always write `EFFECT` explicitly on new functions.
- Prefer `result[T E]` explicitly in signatures, avoid bare `result`.
- Keep `pure` helper functions small and composable.
- Keep effectful functions thin and boundary-focused.

## Slice B Result Ergonomics (Completed)

- Added prelude result combinators:
  - `result_map`
  - `result_map_err`
  - `result_and_then`
  - `result_tap_err`
- Migrated representative examples to use compositional result flow:
  - `examples/prelude/result_flow.crn`
  - `examples/practical/mini_env.crn`
  - `examples/practical/mini_ini.crn`

## Slice C Shared-Surface Annotation Discipline (Completed)

- Added explicit `EFFECT` annotations across shared helper modules:
  - `lib/prelude/ini.crn`
  - `examples/practical/lib/*.crn`
- Correctly marked effectful helper emitters (`emit_lines`) as `EFFECT io`.
- Removed the remaining bare `result` signature in `examples/option.crn`:
  - `safe_div : int int -> result[int str]`
- Added regression guard tests in `test/cairn/effects_style_test.exs`:
  - Every `DEF` in `lib/prelude`, `examples/practical/lib`, and `examples/web/lib` must declare `EFFECT`.
  - Bare `-> result` signatures are rejected in the same shared surface.

## Slice D Data Boundary (Completed)

- Added `Cairn.DataStore` as a runtime-side app-data boundary with a Mnesia default backend.
- Routed `DB_PUT`, `DB_GET`, `DB_DEL`, and `DB_PAIRS` through `Cairn.DataStore` instead of directly calling `Cairn.DB`.
- Added prelude data wrappers in `lib/prelude/data.crn`:
  - `data_put`
  - `data_get`
  - `data_del`
  - `data_pairs`
- Migrated `examples/web/lib/todo_web.crn` off raw `DB_*` calls and onto `data_*` helpers.
- Added delegation coverage in `test/cairn/db_test.exs` with a fake backend to prove runtime backend swapping works.

## Slice E Domain Store Boundary (Completed)

- Added `examples/web/lib/todo_store.crn` as a Cairn-side domain storage module on top of generic `data_*` helpers.
- Moved todo persistence/key-shape logic out of `todo_web.crn` into that domain module:
  - list items
  - add open item
  - mark item done
- Kept runtime generic (no todo-specific runtime module), preserving clean language/framework boundaries.

## Slice F Postgres DataStore Backend (Completed)

- Implemented `Cairn.DataStore.Backend.Postgres` with the same key/value contract as `Cairn.DataStore`:
  - string key
  - string value
  - ordered key/value pairs
- `DB_*` runtime operations continue to flow through `Cairn.DataStore`; selecting `postgres` switches behavior without changing Cairn source.
- Added bounded Postgres table bootstrapping (`CREATE TABLE IF NOT EXISTS cairn_kv`) and consistent runtime error mapping.

## Slice G Environment + Boot Wiring (Completed)

- Added explicit runtime backend selection via `CAIRN_DATA_STORE_BACKEND=mnesia|postgres`.
- Added bounded Postgres config inputs:
  - `CAIRN_PG_HOST`
  - `CAIRN_PG_PORT`
  - `CAIRN_PG_DATABASE`
  - `CAIRN_PG_USER`
  - `CAIRN_PG_PASSWORD`
  - `CAIRN_PG_SSLMODE=disable|require`
  - `CAIRN_PG_TIMEOUT_MS`
- Kept safe fallback behavior:
  - default remains `mnesia` unless backend is explicitly set to `postgres`.

## Slice H Verification + Regression Matrix (Completed)

- Added gated Postgres integration coverage in `test/cairn/db_test.exs`:
  - `CAIRN_PG_TEST=1` enables real Postgres round-trip tests for `DB_*`.
  - default runs remain clean (tests skip when Postgres is not requested).
- Added gated todo-app parity coverage in `test/cairn/http_test.exs`:
  - same add/mark-done/restart flow is exercised on Postgres backend.
- Kept existing fake-backend delegation tests as fast guardrails.

## Slice I Web Loader + Reproducible PG Test Harness (Completed)

- Added `examples/web/lib/web_config.crn` as a shared config loader for web app entrypoints:
  - `web_bind_host`
  - `web_bind_port`
  - `web_data_backend`
- Migrated web app launchers (`hello_static`, `todo_app`, `session_demo`, `login_app`, `afford_app`) to that loader pattern.
- Extended narrow host interop whitelist with `env_get` so Cairn entrypoints can read runtime env keys without bespoke runtime code.
- Added `scripts/test_pg.sh`:
  - boots an ephemeral Postgres container
  - sets the `CAIRN_PG_*` + `CAIRN_DATA_STORE_BACKEND=postgres` env
  - runs gated Postgres integration suites (`db_test` + `http_test`)
  - tears down automatically

## Slice J Web Effect-Surface Cleanup (Completed)

- Standardized shared web-lib request signatures around prelude aliases:
  - `query`
  - `form`
  - `headers`
  - `cookies`
  - `session`
- Added/used typed request-envelope adapters consistently:
  - handlers now expose `*_request_env : request_envelope -> ...`
  - launchers call `request_pack` before invoking handler wrappers
- Expanded this uniform boundary pattern to the previously unmigrated web launchers:
  - `session_demo`
  - `login_app`
  - `afford_app`
- Kept effect boundaries explicit:
  - pure rendering/routing functions remain `EFFECT pure`
  - auth/db/boundary shells remain explicitly effectful (`http`/`db`)

## Slice K Web Edge Assurance Harness (Completed)

- Added dedicated `:web_edge` tags for the main effectful edge flows in `test/cairn/http_test.exs`:
  - todo mutation flow (`POST /add` + `POST /done` + persistence check)
  - session lifecycle flow (`remember`/`logout` + cookie/session-store checks)
  - login/auth lifecycle flow (invalid login, login, protected routes, logout)
  - invalid-input hardening flow (`afford_app` rejects malformed numeric input)
- Added one-command harness: `scripts/test_web_edges.sh`
  - runs `mix test --only web_edge test/cairn/http_test.exs`
  - prints clear progress and success/failure output for CI

## Slice L Remaining Web Context Migration (Completed)

- Migrated the remaining shared web handlers to typed `request_ctx` accessor style:
  - `examples/web/lib/session_demo.crn`
  - `examples/web/lib/afford_web.crn`
- Replaced unpacked request-arg signatures and boundary `DROP` cleanup with direct context reads (`request_ctx_path`, `request_ctx_method`, `request_ctx_form`, `request_ctx_session`).
- Kept handler behavior unchanged while making the web surface consistently context-driven across all primary examples.

## Slice M Response Context Combinators (Completed)

- Added bounded response-side context combinators in `lib/prelude/web.crn`:
  - non-session pack/unpack (`response_pack_ctx`, `response_unpack_ctx`)
  - session-aware pack/unpack (`session_response_pack_ctx`, `session_response_unpack_ctx`)
  - attach/return/clear helpers (`response_with_session_ctx`, `session_response_return`, `session_response_clear_ctx`)
  - request-boundary adapters (`respond_with_ctx_session`, `respond_with_ctx_cleared_session`)
- Migrated session/logout flows in:
  - `examples/web/lib/login_web.crn`
  - `examples/web/lib/session_demo.crn`
- Reduced manual response threading and kept behavior/effects unchanged.

## Slice N Middleware-Style Guard Combinators (Completed)

- Added explicit guard combinators for session-aware responses in `lib/prelude/web.crn`:
  - `guard_login_response`
  - `guard_role_response`
- Applied them in the login web flow (`examples/web/lib/login_web.crn`) so auth checks read as composable boundary helpers instead of nested branch duplication.
- Kept the effect model unchanged (`EFFECT pure` helpers over existing `request_ctx` + response context combinators).

## Slice O Route-Level Middleware Composition (Completed)

- Added session-route candidate combinators in `lib/prelude/web.crn` so route trees can compose as values:
  - candidate constructors (`route_session_from_ctx`, `route_session_from_ctx_cleared`)
  - composition/finalization (`route_or_session`, `route_finish_session_allowed`)
  - candidate guards (`route_guard_login_candidate`, `route_guard_role_candidate`)
- Refactored `examples/web/lib/login_web.crn` into route-level composition (`route_get_*`/`route_post_*` + `route_or_session`) instead of one large nested method/path branch tree.
- Kept runtime behavior and effect boundaries unchanged while making web route control flow explicitly compositional.

## Postgres Discipline Rules

- Cairn source stays in `EFFECT db`; no direct `HOST_CALL` in app code.
- Host/database specifics remain in runtime Elixir boundaries (`DataStore` and backends).
- Result/error mapping remains edge-local and explicit.
- Postgres rollout must preserve Mnesia default behavior unless explicitly configured.
