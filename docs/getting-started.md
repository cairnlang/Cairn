# Getting Started

This is the shortest sensible path to getting a feel for Cairn.

## Build the Executable

```bash
mix escript.build
```

This produces `./cairn`.

`./cairn` is a built snapshot of the runtime. If you change Elixir-side runtime code (for example anything under `lib/cairn/*.ex`), run `mix escript.build` again before testing with the executable.

## First Commands

```bash
# Run a tiny program
./cairn examples/hello_world.crn

# Start the REPL
./cairn

# Browse curated examples
./cairn --examples

# See CLI help
./cairn --help

# Inspect parsed graph IR
./cairn --emit-ir json --fn id examples/generics.crn
```

## Good First Examples

```bash
./cairn examples/collections.crn
./cairn examples/math.crn
./cairn examples/strings.crn
./cairn examples/practical/mini_grep.crn
./cairn examples/practical/mini_env.crn
./cairn examples/practical/mini_ini.crn
./cairn examples/ambitious/orchestrator.crn
./cairn examples/concurrency/guess_binary.crn
```

## See the Diagnostics

```bash
./cairn examples/diagnostics/static_type.crn
./cairn --json-errors examples/diagnostics/runtime_div_zero.crn
```

## Check Contracts

```bash
./cairn examples/bank.crn
```

That runs both:
- `VERIFY` examples (randomized contract checking)
- `PROVE` examples (bounded compile-time proof on the supported subset)

For the exact proof limits and solver behavior, see [PROVE Reference](prove.md).

## Next Docs

- [CLI Quick Reference](cli.md)
- [IR/DAG Visibility](ir.md)
- [Language Reference](language-reference.md)
- [Practical Pipeline](practical-pipeline.md)
- [Roadmap](roadmap.md)
