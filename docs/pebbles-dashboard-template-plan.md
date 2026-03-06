# Pebbles Dashboard Template Migration (Bounded)

Date: March 6, 2026

## Intent

Migrate the Pebbles dashboard from inline `FMT`-assembled HTML to Cairn native templates (`.ctpl`) while keeping behavior equivalent:

- same routes (`GET /`)
- same filtering (`status`, `q`)
- same read-only semantics
- same escaping guarantees for untrusted fields

This is a bounded ergonomics + maintainability slice, not a web-framework redesign.

## Current State

- Dashboard HTML is built inline in:
  - `tools/pebbles/lib/dashboard/model.crn`
- Rendering path works and is covered by:
  - `tools/pebbles/test_dashboard.crn`
  - `test/cairn/pebbles_dashboard_test.exs`

## Target State

- Dashboard view HTML lives in `.ctpl` files under:
  - `tools/pebbles/templates/`
- Dashboard Cairn code uses typed wrapper + context helpers:
  - build typed view data in Cairn
  - call `template_render_file` (and `TPL_RENDER` as needed) at one boundary

## Guardrails

- Keep all user-provided text escaped by default (`{{...}}`).
- Use raw placeholders (`{{{...}}}`) only for trusted pre-rendered fragments, and keep those explicitly documented.
- No new runtime/template syntax for this slice.
- No behavior changes in routes/status codes/query semantics.

## Planned Slices

### D2.1 Template Shape and View Model Boundary

- Define dashboard template files and top-level structure.
- Define typed dashboard view aliases/wrappers in Cairn for template context assembly.

Accept when:

- one typed wrapper builds a full page context without changing route behavior.

### D2.2 Render Path Migration (Page + Sections)

- Replace inline `dashboard_render_page` string assembly with template rendering.
- Keep section/row rendering understandable (template sections where practical; bounded pre-rendered fragments where simpler).

Accept when:

- `GET /` renders equivalent content for summary, filter bar, grouped lists, blockers panel.

### D2.3 Escape and Trust Boundary Hardening

- Ensure all pebble-derived text fields stay escaped.
- If any raw placeholders are needed, constrain them to trusted internal fragments only and document why.

Accept when:

- XSS-style payload checks still pass in dashboard integration tests.

### D2.4 Assurance and Docs Sync

- Update Cairn-native and ExUnit dashboard tests for templated output.
- Update `tools/pebbles/README.md` with template implementation note.
- Record completion in `docs/roadmap.md`.

Accept when:

- dashboard tests pass with template-backed rendering
- full suite remains green

## Out of Scope

- Template partials/includes
- Hot-reload/dev template watcher
- New dashboard routes or mutation actions
- CSS redesign
