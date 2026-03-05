# Cairn Tutorial Book Workspace

This directory contains the project-based tutorial-book work for Cairn.

## Layout

- `planning/`: editorial and curriculum planning docs.
- `code/`: chapter-by-chapter runnable Cairn source used in the book.
- `chapters/`: one Markdown file per chapter (`ch01_...md` through `ch30_...md`).
- `outline.md`: canonical chapter order.
- `build.sh`: concatenates chapters into `dist/runewarden.md`.
- `dist/`: generated manuscript artifacts.

## Current Book Direction

- Working title: `Runewarden`.
- Setting: The Stone Academy of Ironhold (dwarven rune engineering + mine safety).
- Style: incremental, project-based, whimsical but technically rigorous.

See `planning/` for the agreed scope and chapter plan.
Style constraints for prose live in:
- `book/AGENTS.md` (operational instructions while writing)
- `book/planning/prose-style-guide.md` (editorial baseline)

Build the current manuscript with:

```bash
book/build.sh
```
