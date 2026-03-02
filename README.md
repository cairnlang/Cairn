# Cairn

Cairn is a stack-based, postfix programming language for the BEAM.

It is designed around three ideas:
- strong static checking before execution
- explicit contracts and practical verification tools
- message-passing concurrency that stays compatible with the actor model

Today Cairn is an interpreted language with a standalone `cairn` executable, a static type checker, algebraic data types, contracts (`PRE`/`POST`), property-based checking (`VERIFY`), bounded compile-time proofs (`PROVE`), practical scripting plus bounded local persistence, and typed actor primitives.

## What Cairn Looks Like

```crn
DEF deposit : int int -> int
  PRE { OVER 0 GTE SWAP 0 GT AND }
  ADD
  POST DUP 0 GTE
END

100 25 deposit "balance={}" FMT SAID
VERIFY deposit 50
```

Cairn is postfix and stack-based, but it is not just a calculator language. The current codebase includes:
- reusable imports
- an auto-loaded prelude
- maps, lists, strings, blocks, loops, and local state threading
- practical CLI utilities (`mini_grep`, `mini_env`)
- a chatty application-shaped orchestrator example
- a first bounded static HTTP server example
- typed actor workflows on the BEAM (`SPAWN`, `SEND`, `RECEIVE`, `SELF`, `MONITOR`, `AWAIT`)

## Getting Started

```bash
# Build the standalone executable
mix escript.build

# Run a file
./cairn examples/hello_world.crn

# Start the REPL
./cairn

# Browse runnable examples
./cairn --examples

# Show CLI help
./cairn --help
```

`./cairn` is a built escript snapshot. If you change Elixir runtime code under `lib/cairn/*.ex` (for example the evaluator, HTTP runtime, or CLI), rebuild it before testing:

```bash
mix escript.build
```

If you want a production-style run to ignore inline `VERIFY` and `PROVE` directives, set `CAIRN_SKIP_ASSURANCE=1`.

Run native Cairn test files with:

```bash
./cairn --test examples/web/afford_test.crn
```

For the guided first pass, see [Getting Started](docs/getting-started.md).

Good first programs to run:
- `./cairn examples/collections.crn`
- `./cairn examples/math.crn`
- `./cairn examples/strings.crn`
- `./cairn examples/practical/mini_grep.crn`
- `./cairn examples/practical/mini_env.crn`
- `./cairn examples/practical/mini_ini.crn`
- `./cairn examples/ambitious/orchestrator.crn`
- `./cairn examples/web/hello_static.crn`
- `./cairn examples/web/todo_app.crn`
- `./cairn examples/concurrency/guess_binary.crn`

## What It Does Well Today

- Typed, contract-checked functions with readable diagnostics
- Property-based regression checking with `VERIFY`
- Bounded compile-time proof checks with `PROVE` on the supported sequential subset
- Native concrete test cases with `TEST ... END` and basic assertions
- Practical scripting with argv, file I/O, imports, and an auto-loaded prelude
- Bounded but usable actor workflows with explicit local state (`WITH_STATE`, `STEP`, `REPEAT`)

## Documentation

The README is intentionally the front page. The reference material lives in dedicated docs:

- [CLI Quick Reference](docs/cli.md)
  - executable usage, flags, env vars, output conventions
- [Getting Started](docs/getting-started.md)
  - first build, first runs, first examples
- [Language Reference](docs/language-reference.md)
  - syntax, operators, contracts, examples, architecture notes
- [PROVE Reference](docs/prove.md)
  - solver-specific behavior, supported proof surface, trace modes
- [Practical Pipeline](docs/practical-pipeline.md)
  - the staged practical example chain under `examples/practical/`
- [Roadmap](docs/roadmap.md)
  - completed milestones and next directions

## Example Tour

- `examples/collections.crn`: collection helpers (`ZIP`, `ENUMERATE`, `FIND`, `GROUP_BY`, ...)
- `examples/math.crn`: explicit float math (`PI`, `SIN`, `POW`, `LOG`, ...)
- `examples/strings.crn`: native string helpers (`LOWER`, `UPPER`, `REPLACE`, ...)
- `examples/prelude/env_parse.crn`: auto-loaded config helpers (`env_map`, `env_keys`, `env_fetch`)
- `examples/prelude/ini_parse.crn`: auto-loaded INI helpers (`ini_map`, `ini_sections`, `ini_fetch`)
- `examples/prelude/web_helpers.crn`: auto-loaded web helpers (`http_html_ok`, `html_escape`, `http_text_method_not_allowed`, `route_get_html_file`, `route_get_text`, `route_finish_get`)
- `examples/practical/mini_grep.crn`: bounded grep-like CLI utility
- `examples/practical/mini_env.crn`: bounded `.env` query utility
- `examples/practical/mini_ini.crn`: bounded INI query utility
- `examples/ambitious/orchestrator.crn`: verbose local orchestrator with monitored failure and restart
- `examples/policy/approval/main.crn`: typed access-control policy gate with a paired `verify.crn` runner and native `test.crn` scenarios
- `examples/web/hello_static.crn`: tiny multi-route server with Cairn-owned `GET` route helpers, parsed query visibility, explicit bind address support, bounded transport defaults, and a safe dynamic HTML greeting route that escapes user input (`HTTP_SERVE`)
- `examples/web/todo_app.crn`: Mnesia-backed web todo app with escaped HTML rendering plus bounded `POST /add` and `POST /done` form mutations
- `examples/web/afford_app.crn`: affordability decision web app with a clean `POST` form shell and a paired `examples/web/afford_verify.crn` runner that proves the core policy helpers
- `examples/concurrency/protocol_ping_pong.crn`: bounded protocol-checked actor handshake
- `examples/concurrency/guess_binary.crn`: stateful actor workflow with bounded repeated steps

## Status

Cairn is still evolving, but it is already usable for small, strongly-checked experiments and practical scripts.

The codebase includes:
- a standalone executable (`./cairn`)
- curated runnable examples
- broad automated coverage (`mix test`)
- a roadmap that tracks both the practical language path and the deeper research path

If you want the full surface area, start with the [Language Reference](docs/language-reference.md). If you want the quickest feel for the language, run `./cairn --examples` and pick one of the practical or concurrency examples.
