# CLI Quick Reference

## `mix cairn.run`

Run a Cairn source file:

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

1. Run: `mix cairn.run examples/hello_world.crn`
   - Or try the collection-helper showcase: `mix cairn.run examples/collections.crn`
   - Or try explicit float math: `mix cairn.run examples/math.crn`
   - Or try native string helpers: `mix cairn.run examples/strings.crn`
   - Or try narrow host interop: `mix cairn.run examples/interop.crn`
2. Browse examples: `mix cairn.run --examples`
3. Run practical workflows:
   - `mix cairn.run examples/practical/all_practical.crn`
   - `mix cairn.run examples/practical/main.crn`
   - `mix cairn.run examples/practical/ledger.crn`
   - `mix cairn.run examples/practical/todo.crn`
   - `mix cairn.run examples/practical/ledger_cli.crn [optional/path.csv]`
   - `mix cairn.run examples/practical/expenses.crn [optional/path.csv]`
   - `mix cairn.run examples/practical/cashflow.crn [optional/ledger.csv] [optional/expenses.csv]`
   - `mix cairn.run examples/practical/cashflow_alerts.crn [optional/ledger.csv] [optional/expenses.csv]`
   - `mix cairn.run examples/practical/mini_grep.crn [-i] [-n] [-v] [pattern] [file]`
   - `mix cairn.run examples/practical/mini_grep_verify.crn`
4. Load typed-concurrency examples:
   - `mix cairn.run examples/concurrency/ping_pong_types.crn`
   - `mix cairn.run examples/concurrency/protocol_ping_pong.crn`
   - `mix cairn.run examples/concurrency/traffic_light_types.crn`
   - `mix cairn.run examples/concurrency/ping_once.crn`
   - `mix cairn.run examples/concurrency/self_boot.crn`
   - `mix cairn.run examples/concurrency/two_pings.crn`
   - `mix cairn.run examples/concurrency/counter.crn`
   - `mix cairn.run examples/concurrency/traffic_light.crn`
   - `mix cairn.run examples/concurrency/notifier.crn`
   - `mix cairn.run examples/concurrency/restart_once.crn`
   - `mix cairn.run examples/concurrency/supervisor_worker.crn`
   - `mix cairn.run examples/concurrency/guess_binary.crn`
5. Inspect loaded prelude: `mix cairn.run --show-prelude examples/prelude/result_flow.crn`
6. Try diagnostics JSON: `mix cairn.run --json-errors examples/diagnostics/runtime_div_zero.crn`
7. Run practical-only tests: `mix test.practical`

`collections.crn` is the focused collection-helper showcase for `ZIP`, `ENUMERATE`, `TAKE`, `FIND`, `FLAT_MAP`, and `GROUP_BY`. `math.crn` is the focused explicit-float math showcase for `PI`, `E`, `SIN`, `COS`, `FLOOR`, `CEIL`, `ROUND`, `EXP`, `POW`, `LOG`, and `SQRT`. `strings.crn` is the focused native string-helper showcase for `UPPER`, `LOWER`, `REVERSE_STR`, `REPLACE`, and `ENDS_WITH`. `interop.crn` is the focused typed-whitelist host interop showcase for the still-narrow `HOST_CALL` escape hatch. `mini_grep.crn` is the first utility-style CLI stress test, using argv + file I/O + list/string pipelines with native string normalization instead of host case-folding, and `mini_grep_verify.crn` is its paired practical `VERIFY` runner for a pure helper property. `ping_pong_types.crn`, `protocol_ping_pong.crn`, and `traffic_light_types.crn` are type-focused. `protocol_ping_pong.crn` is the first bounded protocol-conformance example and now demonstrates protocol-aware helper-function calls inside protocol-bound actors. `ping_once.crn` exercises the current minimal runtime, `self_boot.crn` demonstrates `SELF` through a helper function, `two_pings.crn` demonstrates repeated actor-local `RECEIVE`, `counter.crn`, `traffic_light.crn`, and `guess_binary.crn` now demonstrate the current preferred actor-state pattern: `WITH_STATE` plus `STEP`-driven `REPEAT` loops, `notifier.crn` is a more practical actor-shaped workflow, `restart_once.crn` is the first supervision-oriented restart example, and `supervisor_worker.crn` is the first explicit supervisor/worker split example. Shared actor/state/supervision helpers live under `examples/concurrency/lib/`; the supervision helper layer now exposes `watch_exit`, `await_exit`, and a reusable `restart_once` helper built on `block[T]` plus `MONITOR`/`AWAIT`. Lifecycle-only examples such as `examples/concurrency/linked_failure.crn` and `examples/concurrency/protocol_mismatch.crn` intentionally fail and are not listed under `--examples`.

See `docs/practical-pipeline.md` for stage-by-stage inputs, outputs, and invariants.
