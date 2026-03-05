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

Functions can now also declare a bounded effect:
- `EFFECT pure`
- `EFFECT io`
- `EFFECT db`
- `EFFECT http`

The first enforced rule is simple and practical: `pure` functions cannot call effectful functions or use effectful built-ins.

The current intended pattern is:
- keep rule engines and data transforms `EFFECT pure`
- keep HTTP, DB, and I/O shells effectful

That lets Cairn make purity visible in production code without forcing a full effect calculus yet.

Cairn also now supports explicit generic functions such as `DEF id[T] : T -> T`.
This is a bounded, explicit first version: generic functions, generic `TYPE`
declarations, and call-site instantiation are supported.

For signature ergonomics, Cairn also supports `TYPEALIAS` (including generic aliases),
which is useful for large web/actor shape signatures.

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
- [Effect Guidelines](docs/effects-guidelines.md)
  - canonical `pure/io/db/http` usage pattern and boundary discipline
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
- `examples/prelude/web_helpers.crn`: auto-loaded web helpers (`http_html_ok`, `html_escape`, `http_add_header`, `http_text_method_not_allowed`, `http_text_unauthorized`, `http_text_forbidden`, `session_has_user`, `guard_require_role`, `route_get_html_file`, `route_get_text`, `route_finish_get`)
- `examples/practical/mini_grep.crn`: bounded grep-like CLI utility
- `examples/practical/mini_env.crn`: bounded `.env` query utility
- `examples/practical/mini_ini.crn`: bounded INI query utility
- `examples/ambitious/orchestrator.crn`: verbose local orchestrator with monitored failure and restart
- `examples/policy/approval/main.crn`: typed access-control policy gate with a paired `verify.crn` runner and native `test.crn` scenarios
- `examples/web/hello_static.crn`: tiny multi-route server with Cairn-owned `GET` route helpers, parsed query/header/cookie visibility, explicit bind address support, bounded transport defaults, and safe dynamic routes for escaped HTML and `Set-Cookie` headers (`HTTP_SERVE`)
- `examples/web/todo_app.crn`: DataStore-backed web todo app (mnesia by default, postgres via env) with escaped HTML rendering plus bounded `POST /add` and `POST /done` form mutations
  - now routed through prelude `data_*` helpers (`data_put`, `data_get`, `data_del`, `data_pairs`) over the runtime `Cairn.DataStore` boundary
  - `Cairn.DataStore` now supports `mnesia` (default) and bounded `postgres` backend selection via runtime config/env
- `examples/web/afford_app.crn`: affordability decision web app with a clean `POST` form shell and a paired `examples/web/afford_verify.crn` runner that proves the core policy helpers
- `examples/web/session_demo.crn`: bounded server-side session demo with cookie-backed request state and a Mnesia-backed default session store
- `examples/web/login_app.crn`: bounded login/logout demo with a protected profile page and an admin-only route, built on server-side sessions and a runtime-side user-store boundary
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
