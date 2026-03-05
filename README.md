# Cairn

Cairn is a stack-based, postfix programming language for the BEAM.

It is built around:
- strong static checking before execution
- explicit contracts and assurance tools
- actor-model concurrency with typed message flow

## Quick Start

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

If you change runtime code under `lib/cairn/*.ex`, rebuild `./cairn` with `mix escript.build`.

## Cairn In Book Order

The project and examples follow the same progression as the Runewarden tutorial book.

### 1) Stacks, words, contracts

```crn
DEF deposit : int int -> int
  PRE { OVER 0 GTE SWAP 0 GT AND }
  ADD
  POST DUP 0 GTE
END

100 25 deposit "balance={}" FMT SAID
```

Cairn starts with explicit stack effects, typed signatures, and `PRE`/`POST` contracts.

### 2) Types, collections, and parsing

Cairn supports algebraic data types, generics, and aliases:
- `TYPE incident = CaveIn int | GasLeak int`
- generic functions (`DEF id[T] : T -> T`)
- generic aliases (`TYPEALIAS pair[T U] = tuple[T U]`)

Core practical structures are available (`list`, `map`, `tuple`, strings, blocks), plus reusable imports and an auto-loaded prelude.

### 3) Assurance loop: TEST, VERIFY, PROVE

- `TEST ... END` for concrete Cairn-native tests
- `VERIFY fn N` for property checks
- `PROVE fn` for bounded compile-time proofs on the supported sequential subset

```bash
./cairn --test examples/web/afford_test.crn
```

For production-style runs that must ignore inline assurance directives in loaded code:

```bash
CAIRN_SKIP_ASSURANCE=1 ./cairn your_app.crn
```

### 4) Pure core, effectful shell

Functions can declare bounded effects:
- `EFFECT pure`
- `EFFECT io`
- `EFFECT db`
- `EFFECT http`

Current enforced rule: `pure` functions cannot call effectful functions or effectful built-ins.

### 5) Practical CLI programs

Examples under `examples/practical/` show bounded utilities implemented in Cairn:
- `mini_grep`
- `mini_env`
- `mini_ini`

### 6) Web boundary

Cairn includes a bounded HTTP runtime with Cairn-side routing and helpers:
- route helpers and response builders
- escaping helpers for dynamic HTML
- form handling and method-aware routing
- cookies and server-side sessions
- login/auth example flows

### 7) Data boundary

Web examples use a runtime-side datastore boundary:
- default backend: Mnesia
- optional backend: Postgres via env configuration
- Cairn-side `data_*` prelude helpers over the runtime boundary

### 8) Actors, protocols, supervision

Cairn supports typed actor workflows on the BEAM:
- `SPAWN`, `SEND`, `RECEIVE`, `SELF`, `MONITOR`, `AWAIT`
- explicit state threading (`WITH_STATE`, `STEP`)
- bounded protocol checking for message order
- restart/supervision patterns in examples

## Suggested Example Path

Run these in order for a fast tour:
- `./cairn examples/collections.crn`
- `./cairn examples/math.crn`
- `./cairn examples/strings.crn`
- `./cairn examples/practical/mini_grep.crn`
- `./cairn examples/web/hello_static.crn`
- `./cairn examples/web/todo_app.crn`
- `./cairn examples/concurrency/guess_binary.crn`

## Documentation

- [Getting Started](docs/getting-started.md)
- [CLI Quick Reference](docs/cli.md)
- [Language Reference](docs/language-reference.md)
- [Effect Guidelines](docs/effects-guidelines.md)
- [PROVE Reference](docs/prove.md)
- [Practical Pipeline](docs/practical-pipeline.md)
- [Roadmap](docs/roadmap.md)

## Book

The project tutorial-book lives under `book/`:
- chapter sources: `book/chapters/`
- chapter code: `book/code/runewarden/`
- built manuscript: `book/dist/runewarden.md`

## Status

Cairn is interpreted today and already usable for strongly-checked scripts, bounded web services, and actor-based experiments.

The repository includes:
- standalone executable (`./cairn`)
- curated runnable examples
- broad automated coverage (`mix test`)
- active roadmap for practical and research tracks
