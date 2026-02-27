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
3. Run a practical mini-app: `mix axiom.run examples/practical/main.ax`
4. Inspect loaded prelude: `mix axiom.run --show-prelude examples/prelude/result_flow.ax`
5. Try diagnostics JSON: `mix axiom.run --json-errors examples/diagnostics/runtime_div_zero.ax`
