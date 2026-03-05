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

## Postgres Migration Track (Planned)

Objective: move the todo web app from the Mnesia default backend to PostgreSQL while preserving the same Cairn-side effect discipline (`EFFECT db`) and avoiding direct host interop in Cairn source.

### Slice F Postgres DataStore Backend (Bounded)

- Implement `Cairn.DataStore.Backend.Postgres` with the same contract as `Cairn.DataStore`.
- Keep parity with current key/value behavior for first cut:
  - string key
  - string value
  - list pairs
- Backend selection stays runtime-configurable through `:data_store_backend`.
- Failures map to runtime errors/result paths consistently with current DB behavior.

Why second: establishes a production-oriented backend without changing Cairn syntax or app contracts.

### Slice G Environment + Boot Wiring

- Add bounded runtime config for Postgres connection inputs (host/port/db/user/password/sslmode).
- Keep a safe default path:
  - Mnesia remains default if Postgres config is absent.
  - explicit opt-in switches backend to Postgres.
- Add startup diagnostics so backend choice is visible and misconfiguration fails fast.

Why third: makes backend switching operationally usable and debuggable.

### Slice H Verification + Regression Matrix

- Add integration coverage for both backends:
  - Mnesia path
  - Postgres path (gated by env/config)
- Add behavior-parity tests for todo operations across backends.
- Keep existing fake-backend delegation tests as fast guardrails.

Why fourth: locks in backend-agnostic behavior and prevents regressions during later DB features.

## Postgres Discipline Rules

- Cairn source stays in `EFFECT db`; no direct `HOST_CALL` in app code.
- Host/database specifics remain in runtime Elixir boundaries (`DataStore` and backends).
- Result/error mapping remains edge-local and explicit.
- Postgres rollout must preserve Mnesia default behavior unless explicitly configured.
