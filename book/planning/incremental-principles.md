# Incremental Build Principles

These rules guide chapter design so the book stays practical and teachable.

## Core Rules

- One evolving project (`Runewarden`) across the full book.
- Each chapter introduces a small number of new language ideas.
- Each chapter ends with a runnable milestone.
- Do not introduce advanced features before a practical need appears.

## Assurance Rhythm

Every major feature arc should include:
- at least one `TEST` chapter slice,
- one `VERIFY` property slice where it makes sense,
- one `PROVE` slice for the supported proof subset.

## Boundary Discipline

- Keep business rules mostly `EFFECT pure`.
- Put IO/HTTP/DB at thin edges.
- Keep backend swaps (mnesia/postgres) outside app-domain logic.

## Narrative Tone

- Whimsical worldbuilding, concrete engineering.
- Use domain language consistently:
  - apprentices,
  - foremen,
  - runepriests,
  - shafts,
  - rituals,
  - safety ledgers.
