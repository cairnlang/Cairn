# CLI Quick Reference

## `cairn`

Standalone executable behavior:

```bash
cairn [options]
cairn [options] <file.crn> [args...]
```

- No file: start the REPL
- File: run the file with `ARGV` bound to the remaining args

Build it once with:

```bash
mix escript.build
```

## `mix cairn.run`

Development wrapper for the same file-mode behavior:

```bash
mix cairn.run [options] <file.crn> [args...]
```

### Options

- `--help`: show command help
- `--examples`: show categorized runnable examples
- `--show-prelude`: print loaded prelude modules/functions before running
- `--verbose`: alias for `--show-prelude`
- `--json-errors`: emit structured JSON diagnostics on failures

### Environment

- `CAIRN_NO_PRELUDE=1`: disable auto-loading `lib/prelude.crn` in file mode
- `CAIRN_PROVE_TRACE=summary|verbose|json`: enable PROVE trace diagnostics on stderr

### Output conventions

- Program values are printed to stdout (top of stack last)
- Diagnostics are printed to stderr
- Run summary is always on stderr:
  - success: `RUN SUMMARY: status=ok values=<n> elapsed_ms=<ms>`
  - error: `RUN SUMMARY: status=error kind=<static|runtime|contract> elapsed_ms=<ms>`

### Failure diagnostics

Default text mode:

- `ERROR kind=<static|runtime|contract>`
- `message: ...`
- optional `location: <path>:<line> (word <n>)`
- optional `snippet: ...`
- `hint: ...`

JSON mode (`--json-errors`) emits a single JSON object with fields like:

- `kind`, `message`, optional `word`
- optional `location` (`path`, `line`, `snippet`)
- optional `hint`
- optional `details` (for multi-error static failures)

## Suggested workflow

1. Build once: `mix escript.build`
2. Run: `./cairn examples/hello_world.crn`
   - Or try the collection-helper showcase: `./cairn examples/collections.crn`
   - Or try explicit float math: `./cairn examples/math.crn`
   - Or try native string helpers: `./cairn examples/strings.crn`
   - Or try narrow host interop: `./cairn examples/interop.crn`
3. Browse examples: `./cairn --examples`
4. Run practical workflows:
   - `./cairn examples/practical/all_practical.crn`
   - `./cairn examples/practical/main.crn`
   - `./cairn examples/practical/ledger.crn`
   - `./cairn examples/practical/todo.crn`
   - `./cairn examples/practical/ledger_cli.crn [optional/path.csv]`
   - `./cairn examples/practical/expenses.crn [optional/path.csv]`
   - `./cairn examples/practical/cashflow.crn [optional/ledger.csv] [optional/expenses.csv]`
   - `./cairn examples/practical/cashflow_alerts.crn [optional/ledger.csv] [optional/expenses.csv]`
   - `./cairn examples/practical/mini_grep.crn [-i] [-n] [-v] [pattern] [file]`
   - `./cairn examples/practical/mini_grep_verify.crn`
5. Load typed-concurrency examples:
   - `./cairn examples/concurrency/ping_pong_types.crn`
   - `./cairn examples/concurrency/protocol_ping_pong.crn`
   - `./cairn examples/concurrency/traffic_light_types.crn`
   - `./cairn examples/concurrency/ping_once.crn`
   - `./cairn examples/concurrency/self_boot.crn`
   - `./cairn examples/concurrency/two_pings.crn`
   - `./cairn examples/concurrency/counter.crn`
   - `./cairn examples/concurrency/traffic_light.crn`
   - `./cairn examples/concurrency/notifier.crn`
   - `./cairn examples/concurrency/restart_once.crn`
   - `./cairn examples/concurrency/supervisor_worker.crn`
   - `./cairn examples/concurrency/guess_binary.crn`
6. Inspect loaded prelude: `./cairn --show-prelude examples/prelude/result_flow.crn`
7. Try diagnostics JSON: `./cairn --json-errors examples/diagnostics/runtime_div_zero.crn`
8. Run practical-only tests: `mix test.practical`

`collections.crn` is the focused collection-helper showcase for `ZIP`, `ENUMERATE`, `TAKE`, `FIND`, `FLAT_MAP`, and `GROUP_BY`. `math.crn` is the focused explicit-float math showcase for `PI`, `E`, `SIN`, `COS`, `FLOOR`, `CEIL`, `ROUND`, `EXP`, `POW`, `LOG`, and `SQRT`. `strings.crn` is the focused native string-helper showcase for `UPPER`, `LOWER`, `REVERSE_STR`, `REPLACE`, and `ENDS_WITH`. `interop.crn` is the focused typed-whitelist host interop showcase for the still-narrow `HOST_CALL` escape hatch. `mini_grep.crn` is the first utility-style CLI stress test, using argv + file I/O + list/string pipelines with native string normalization instead of host case-folding, and `mini_grep_verify.crn` is its paired practical `VERIFY` runner for a pure helper property. `ping_pong_types.crn`, `protocol_ping_pong.crn`, and `traffic_light_types.crn` are type-focused. `protocol_ping_pong.crn` is the first bounded protocol-conformance example and now demonstrates protocol-aware helper-function calls inside protocol-bound actors. `ping_once.crn` exercises the current minimal runtime, `self_boot.crn` demonstrates `SELF` through a helper function, `two_pings.crn` demonstrates repeated actor-local `RECEIVE`, `counter.crn`, `traffic_light.crn`, and `guess_binary.crn` now demonstrate the current preferred actor-state pattern: `WITH_STATE` plus `STEP`-driven `REPEAT` loops, `notifier.crn` is a more practical actor-shaped workflow, `restart_once.crn` is the first supervision-oriented restart example, and `supervisor_worker.crn` is the first explicit supervisor/worker split example. Shared actor/state/supervision helpers live under `examples/concurrency/lib/`; the supervision helper layer now exposes `watch_exit`, `await_exit`, and a reusable `restart_once` helper built on `block[T]` plus `MONITOR`/`AWAIT`. Lifecycle-only examples such as `examples/concurrency/linked_failure.crn` and `examples/concurrency/protocol_mismatch.crn` intentionally fail and are not listed under `--examples`.

See `docs/practical-pipeline.md` for stage-by-stage inputs, outputs, and invariants.
