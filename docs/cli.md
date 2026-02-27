# CLI Quick Reference

## `mix axiom.run`

Run an Axiom source file:

```bash
mix axiom.run [options] <file.ax> [args...]
```

### Options

- `--help`: show command help
- `--examples`: show categorized runnable examples
- `--show-prelude`: print loaded prelude modules/functions before running
- `--verbose`: alias for `--show-prelude`
- `--json-errors`: emit structured JSON diagnostics on failures

### Environment

- `AXIOM_NO_PRELUDE=1`: disable auto-loading `lib/prelude.ax` in file mode
- `AXIOM_PROVE_TRACE=summary|verbose|json`: enable PROVE trace diagnostics on stderr

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

1. Run: `mix axiom.run examples/hello_world.ax`
2. Browse examples: `mix axiom.run --examples`
3. Run practical workflows:
   - `mix axiom.run examples/practical/all_practical.ax`
   - `mix axiom.run examples/practical/main.ax`
   - `mix axiom.run examples/practical/ledger.ax`
   - `mix axiom.run examples/practical/todo.ax`
   - `mix axiom.run examples/practical/ledger_cli.ax [optional/path.csv]`
   - `mix axiom.run examples/practical/expenses.ax [optional/path.csv]`
   - `mix axiom.run examples/practical/cashflow.ax [optional/ledger.csv] [optional/expenses.csv]`
   - `mix axiom.run examples/practical/cashflow_alerts.ax [optional/ledger.csv] [optional/expenses.csv]`
4. Load typed-concurrency examples:
   - `mix axiom.run examples/concurrency/ping_pong_types.ax`
   - `mix axiom.run examples/concurrency/protocol_ping_pong.ax`
   - `mix axiom.run examples/concurrency/traffic_light_types.ax`
   - `mix axiom.run examples/concurrency/ping_once.ax`
   - `mix axiom.run examples/concurrency/self_boot.ax`
   - `mix axiom.run examples/concurrency/two_pings.ax`
   - `mix axiom.run examples/concurrency/counter.ax`
   - `mix axiom.run examples/concurrency/traffic_light.ax`
   - `mix axiom.run examples/concurrency/notifier.ax`
   - `mix axiom.run examples/concurrency/restart_once.ax`
   - `mix axiom.run examples/concurrency/supervisor_worker.ax`
5. Inspect loaded prelude: `mix axiom.run --show-prelude examples/prelude/result_flow.ax`
6. Try diagnostics JSON: `mix axiom.run --json-errors examples/diagnostics/runtime_div_zero.ax`
7. Run practical-only tests: `mix test.practical`

`ping_pong_types.ax`, `protocol_ping_pong.ax`, and `traffic_light_types.ax` are type-focused. `protocol_ping_pong.ax` is the first bounded protocol-conformance example and now demonstrates protocol-aware helper-function calls inside protocol-bound actors. `ping_once.ax` exercises the current minimal runtime, `self_boot.ax` demonstrates `SELF` through a helper function, `two_pings.ax` demonstrates repeated actor-local `RECEIVE`, `counter.ax` demonstrates stack-carried actor state, `traffic_light.ax` demonstrates named state transitions over that same model, `notifier.ax` is a more practical actor-shaped workflow, `restart_once.ax` is the first supervision-oriented restart example, and `supervisor_worker.ax` is the first explicit supervisor/worker split example. Shared actor/state/supervision helpers live under `examples/concurrency/lib/`; the supervision helper layer now exposes `watch_exit`, `await_exit`, and a reusable `restart_once` helper built on `block[T]` plus `MONITOR`/`AWAIT`. Lifecycle-only examples such as `examples/concurrency/linked_failure.ax` and `examples/concurrency/protocol_mismatch.ax` intentionally fail and are not listed under `--examples`.

See `docs/practical-pipeline.md` for stage-by-stage inputs, outputs, and invariants.
