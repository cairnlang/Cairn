# Pebbles v1 Plan (Single-Agent CLI)

Date: March 5, 2026

## Status

- P1 landed: scaffold + storage boundary + `init/add/ls`.
- P1 durability fix landed: Mnesia log sync after writes/deletes so separate CLI invocations observe persisted state.
- P2 landed: domain transitions + lifecycle commands (`next/do/done/block`) with transition validation.
- P3 landed: notes command + improved `ls` formatting + hardened test coverage.
- P4 landed: snapshot `export/import` portability flow with header validation and id-sync recovery.
- P5 landed: quality-of-life commands (`reopen/edit/find`) + `ls` status filtering + workflow reference.
- D1 landed: read-only web dashboard (`tools/pebbles/dashboard.crn`) with grouped status sections, blockers panel, and query filtering (`status`, `q`).
- Implemented files:
  - `tools/pebbles/main.crn`
  - `tools/pebbles/lib/store.crn`
  - `tools/pebbles/lib/domain.crn`
  - `tools/pebbles/lib/dashboard/model.crn`
  - `tools/pebbles/lib/dashboard/web.crn`
  - `tools/pebbles/dashboard.crn`
  - `tools/pebbles/README.md`
  - `tools/pebbles/test.crn`
  - `tools/pebbles/test_dashboard.crn`
  - `test/cairn/pebbles_test.exs`

## Goal

Build a small Cairn-native task tracker inspired by Yegge-style beads:

- single agent
- CLI-first
- optional read-only web dashboard
- practical daily planning/flow tracking

This is intended to replace ad-hoc roadmap accretion with a lightweight operational tool.

## Project Placement

Start inside this repository:

- `tools/pebbles/`

Reason:

- fastest dogfooding loop
- reuses existing Cairn runtime/test/docs workflow
- can be split into a separate repo later if it outgrows this tree

## Storage Decision (v1)

Use Cairn `DB_*` (`Cairn.DataStore`) with default Mnesia backend.

Why:

- avoids file-locking/compaction/recovery complexity
- already available and tested in this codebase
- good fit for single-agent local CLI

Keep a strict storage boundary so backend can move to Postgres later without changing command/domain logic.

## Key Model

- `meta/next_id` -> next monotonic integer id
- `pebble/<id>` -> serialized pebble record
- optional `event/<n>` -> append-only audit event (deferred in v1 unless needed)

## Pebble Domain Shape

Fields:

- `id`
- `title`
- `status` (`open | doing | blocked | done`)
- `priority` (bounded enum later; optional in earliest slice)
- `created_at`
- `updated_at`
- `blocked_reason`
- `notes` (list-like encoded field or bounded single note for v1)

## MVP Commands

- `pebbles init`
- `pebbles add <title>`
- `pebbles ls [status]`
- `pebbles next`
- `pebbles do <id>`
- `pebbles done <id>`
- `pebbles reopen <id>`
- `pebbles block <id> <reason>`
- `pebbles note <id> <text>`
- `pebbles edit <id> <title>`
- `pebbles find <text>`
- `pebbles export <path>`
- `pebbles import <path>`

## Minimal Architecture

- `tools/pebbles/main.crn`
  - argv parsing + dispatch
- `tools/pebbles/lib/store.crn`
  - only place that uses `DB_*`
- `tools/pebbles/lib/domain.crn`
  - transitions/validation/render helpers (`EFFECT pure`)
- `tools/pebbles/test.crn`
  - Cairn-native command/domain checks

## Rules / Invariants

- ids are monotonic and never reused
- unknown id operations return explicit errors
- invalid transitions are rejected (example: `done -> do` without reopen command)
- command handlers do not call `DB_*` directly (store boundary only)

## Operational Policy

- Track at Pebble granularity, deliver at slice granularity.
- A slice is a dependency-respecting set of Pebbles that yields user-visible value.
- Default commit unit is one coherent slice (implementation + tests + docs), not one commit per Pebble.

## Delivery Slices

1. Slice P1: scaffold + storage boundary + `init/add/ls`
2. Slice P2: transitions (`next/do/done/block`) + validation
3. Slice P3: notes + better output formatting + tests hardening
4. Slice P4: export/import command for portability
5. Slice P5: edit/reopen/find + status-filtered listing + workflow reference
6. Slice D1: read-model projection helpers + dashboard HTTP view

## Acceptance (v1 usable)

- can initialize a workspace and persist pebbles
- can list and pick next work item deterministically
- can move through basic lifecycle (`open -> doing -> done` / `blocked`)
- has at least one Cairn-native test file and one Elixir smoke/integration entry
- documented quickstart in `tools/pebbles/README.md`
