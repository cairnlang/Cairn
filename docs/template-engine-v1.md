# Cairn Template Engine v1 (Bounded Spec)

## Intent

Add a native Cairn templating path for HTML rendering that is:

- safe by default (escape-on-interpolate),
- small enough to ship quickly,
- compatible with current effect discipline,
- friendly to both humans and LLMs.

This is a practical web ergonomics feature, not a general macro system.

## Why This Shape

Liquid-through-FFI is fast, but it weakens Cairn's type/effect story and makes templates feel foreign to the language.
String concatenation works, but scales poorly for bigger views.

So v1 is a Cairn-owned template format with bounded control flow and strict escaping.

## Non-Goals (v1)

- No arbitrary expression language inside templates
- No user-defined filters
- No inheritance/layout DSL
- No compile-time solver integration for templates
- No backward compatibility with external template syntaxes

## v1 Authoring Model

Templates live as files (proposed extension: `.ctpl`) and use a minimal mustache-like syntax.

Supported constructs:

1. Escaped interpolation: `{{name}}`
2. Raw interpolation (explicit escape hatch): `{{{html}}}`
3. Conditional section:
   - `{{#if is_admin}} ... {{/if}}`
4. List section:
   - `{{#each items as item}} ... {{/each}}`

Bounded rules:

- Names are simple identifiers (`name`, `user_name`, `item`)
- `if` accepts a boolean field only
- `each` accepts a list field only
- Sections cannot call functions; compute values before rendering

Warning: `{{{...}}}` must be treated as trusted HTML only. Untrusted user input must use `{{...}}`.

## Type and Effect Story

v1 keeps runtime parsing/rendering in the web/runtime boundary, but keeps template-facing usage typed in Cairn code.

Planned split:

1. Effectful loading/parsing
   - `TPL_LOAD : str -> result[template str] EFFECT io`
2. Pure rendering (given compiled template + prepared context map)
   - `TPL_RENDER : template map[str any] -> result[str str]`

To keep usage type-safe in app code, each template should have a typed Cairn wrapper:

- wrapper input is a record alias (or tuple alias where needed),
- wrapper explicitly maps typed fields into the render context,
- wrapper is where compile-time type checking happens.

This keeps runtime generic while keeping application boundaries typed.

Cookbook wrapper pattern (bounded, practical):

```cairn
TYPE hello_view = HelloView str

DEF hello_view_new : str -> hello_view EFFECT pure
  HelloView
END

DEF hello_view_ctx : hello_view -> template_ctx EFFECT pure
  MATCH
    HelloView {
      M[] "name" ROT PUT
    }
  END
END

DEF render_hello : hello_view -> template_result EFFECT io
  hello_view_ctx
  "examples/web/templates/hello_name.ctpl"
  template_render_file
END
```

## Security Baseline

1. Escape by default for `{{...}}`
2. Raw interpolation only via `{{{...}}}` (opt-in, explicit risk)
3. Reject unknown/missing placeholders with `Err` (no silent blanks)
4. Keep path handling under existing safe static/template loader constraints

## Integration Boundaries

- Prelude module entrypoint: `lib/prelude/web.crn` (template helpers grouped under web)
- Runtime implementation: Elixir side parser + renderer for bounded syntax
- App usage: typed helper modules in `examples/web/lib/*`

No framework lock-in: templates are optional; direct string rendering remains available.

## Acceptance Slices

### T1. Runtime Parser + Escaped Placeholders

- Parse literal text + `{{name}}`
- Render with HTML escaping
- Return structured `Err` on parse or missing field

Accept when:

- `hello_static` can render one dynamic value from template
- tests cover escaping and missing-key errors

### T2. Raw Escape Hatch + Hardening

- Add `{{{name}}}` behavior
- keep escaped and raw behavior explicitly distinct

Accept when:

- tests prove escaped and raw branches differ as expected
- docs warn raw is for trusted HTML only

### T3. Bounded Sections (`if`, `each`)

- Add `if` and `each` parser/render support
- reject malformed nesting with parse `Err`

Accept when:

- one template uses both sections correctly
- malformed section tests fail cleanly

### T4. Typed Wrapper Pattern

- Add cookbook pattern for typed per-template wrappers in Cairn
- migrate one web example to wrapper style

Accept when:

- wrapper signatures use aliases/records, not raw loose maps
- example compiles and runs unchanged in behavior

### T5. Docs + Book Sync

- Add template reference section to language/web docs
- add one book chapter or chapter extension showing migration from string concat to templates

Accept when:

- new user can render a page from a `.ctpl` file with one typed wrapper and one route

## Open Questions (Deferred)

1. Should we add partial includes in v1.1?
2. Should template parse happen at startup only, or support reload in dev mode?
3. Should we expose a tiny template linter command in CLI?

These are intentionally deferred until v1 usage feedback lands.
