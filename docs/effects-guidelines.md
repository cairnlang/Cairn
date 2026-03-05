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
- DB boundary is currently operation-shaped (`DB_*`) rather than capability-shaped.
  - Fine for now, but not ideal for backend pluggability.

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
