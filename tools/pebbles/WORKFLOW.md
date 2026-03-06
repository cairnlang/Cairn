# Pebbles Workflow Reference

## Daily Loop

Start of session:

```bash
./cairn tools/pebbles/main.crn ls
./cairn tools/pebbles/main.crn next
```

While working:

```bash
./cairn tools/pebbles/main.crn do <id>
./cairn tools/pebbles/main.crn note <id> "<progress note>"
./cairn tools/pebbles/main.crn block <id> "<blocking reason>"
./cairn tools/pebbles/main.crn find <keyword>
```

When scope changes:

```bash
./cairn tools/pebbles/main.crn edit <id> "<new title>"
./cairn tools/pebbles/main.crn reopen <id>
./cairn tools/pebbles/main.crn done <id>
```

End of session backup:

```bash
./cairn tools/pebbles/main.crn export pebbles.snapshot
```

## Status Conventions

- `open`: ready to pick up.
- `doing`: currently in flight.
- `blocked`: waiting on external dependency; always include reason.
- `done`: finished and closed.

## Query Patterns

- focus queue: `ls open`
- blocked review: `ls blocked`
- recent concerns: `find risk`
- migration-related work: `find migration`

## Writing Conventions

- Title: imperative short phrase (`implement X`, `fix Y`, `document Z`).
- Notes: one concrete progress fact per line.
- Block reason: external and actionable (`waiting on API token`, `review pending`).

## Slice Discipline

- A Pebble is a work unit, not a git commit unit.
- A coherent slice is the smallest set of Pebbles that delivers visible value while respecting dependencies.
- Use dependency notes (`depends on #X #Y`) to form slice boundaries.
- Prefer slices that end with green tests and documentation updates.

Current default grouping model:

- Slice A: scope + read-model core.
- Slice B: route handler + base rendering.
- Slice C: filtering/search + hardening.
- Slice D: assurance and integration tests.
- Slice E: docs + roadmap + smoke verification.

## Commit Discipline

- Do not commit one-by-one per Pebble by default.
- Commit per coherent slice with:
  - implementation
  - tests
  - docs/roadmap notes
- Keep Pebbles runtime state out of git; commit source/docs/tests only.

## Runtime Note

- In this repository, if `./cairn tools/pebbles/main.crn ...` does not persist reliably across invocations, use:
  - `mix cairn.run tools/pebbles/main.crn ...`
