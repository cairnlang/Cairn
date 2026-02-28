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
   - `./cairn examples/practical/mini_env.crn [--keys <file> | <file> <key> [fallback]]`
   - `./cairn examples/practical/mini_ini.crn [--sections <file> | <file> <section> <key> [fallback]]`
5. Run the first application-shaped stress test:
   - `./cairn examples/ambitious/orchestrator.crn [optional/jobs.txt]`
6. Run the first bounded web-serving example:
   - `./cairn examples/web/hello_static.crn`
7. Load typed-concurrency examples:
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
8. Inspect loaded prelude: `./cairn --show-prelude examples/prelude/web_helpers.crn`
9. Try diagnostics JSON: `./cairn --json-errors examples/diagnostics/runtime_div_zero.crn`
10. Run practical-only tests: `mix test.practical`

`collections.crn` is the focused collection-helper showcase for `ZIP`, `ENUMERATE`, `TAKE`, `FIND`, `FLAT_MAP`, and `GROUP_BY`. `math.crn` is the focused explicit-float math showcase for `PI`, `E`, `SIN`, `COS`, `FLOOR`, `CEIL`, `ROUND`, `EXP`, `POW`, `LOG`, and `SQRT`. `strings.crn` is the focused native string-helper showcase for `UPPER`, `LOWER`, `REVERSE_STR`, `REPLACE`, and `ENDS_WITH`. `interop.crn` is the focused typed-whitelist host interop showcase for the still-narrow `HOST_CALL` escape hatch. `env_parse.crn` is the focused `.env` config-prelude showcase for `env_map`, `env_keys`, `env_fetch`, and `map_get_or`, `ini_parse.crn` is the matching INI-prelude showcase for `ini_map`, `ini_sections`, and `ini_fetch`, and `web_helpers.crn` is the matching web-prelude showcase for `http_html_ok`, `route_html_file`, `route_or`, and `route_finish`. `mini_grep.crn` is the first utility-style CLI stress test, using argv + file I/O + list/string pipelines with native string normalization instead of host case-folding, `mini_grep_verify.crn` is its paired practical `VERIFY` runner for a pure helper property, `mini_env.crn` is the bounded `.env` query utility, and `mini_ini.crn` is the matching bounded INI query utility that exercises section-aware parsing without needing new core syntax. `examples/ambitious/orchestrator.crn` is the first application-shaped stress test: a verbose local orchestrator that narrates a bounded actor run, observes one worker failure, and restarts once. `ping_pong_types.crn`, `protocol_ping_pong.crn`, and `traffic_light_types.crn` are type-focused. `protocol_ping_pong.crn` is the first bounded protocol-conformance example and now demonstrates protocol-aware helper-function calls inside protocol-bound actors. `ping_once.crn` exercises the current minimal runtime, `self_boot.crn` demonstrates `SELF` through a helper function, `two_pings.crn` demonstrates repeated actor-local `RECEIVE`, `counter.crn`, `traffic_light.crn`, and `guess_binary.crn` now demonstrate the current preferred actor-state pattern: `WITH_STATE` plus `STEP`-driven `REPEAT` loops, `notifier.crn` is a more practical actor-shaped workflow, `restart_once.crn` is the first supervision-oriented restart example, and `supervisor_worker.crn` is the first explicit supervisor/worker split example. Shared actor/state/supervision helpers live under `examples/concurrency/lib/`; the supervision helper layer now exposes `watch_exit`, `await_exit`, and a reusable `restart_once` helper built on `block[T]` plus `MONITOR`/`AWAIT`. Lifecycle-only examples such as `examples/concurrency/linked_failure.crn` and `examples/concurrency/protocol_mismatch.crn` intentionally fail and are not listed under `--examples`.

`examples/web/hello_static.crn` is the first transport milestone: a deliberately tiny static HTTP server that binds to `127.0.0.1:8089` by default, passes each request path into a Cairn handler block, and routes between two explicit pages (`/` and `/about`). The route logic now lives in `examples/web/lib/hello_static.crn`, and it uses the new route helpers (`route_html_file`, `route_or`, `route_finish`) instead of an inline `IF` ladder. You can override the bind and port as `./cairn examples/web/hello_static.crn 0.0.0.0 9090`. The host runtime owns the accept loop and HTTP framing; Cairn owns the route choice and response content. `HTTP_SERVE` can also take an explicit bind address literal like `"0.0.0.0"` from Cairn when you want to listen beyond loopback.

See `docs/practical-pipeline.md` for stage-by-stage inputs, outputs, and invariants.
