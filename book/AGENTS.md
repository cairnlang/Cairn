# Book Writing Agent Instructions

These instructions apply to all files under `book/`.

## Voice and Style

- Write in a human technical-author voice, not an assistant voice.
- Prefer flowing prose over lists.
- Do not use "pros and cons" framing by default.
- Do not hedge every claim; say what is true plainly.
- Do not use reassuring filler or praise.
- Do not mirror user tone with flattery.
- Keep rhetorical structure close to classic technical texts (SICP/Why style):
  - state intent,
  - build the idea,
  - show the mechanism,
  - test the mechanism,
  - move on.

## Anti-LLM Rules

- Avoid generic transition clichés ("in today's world", "it's important to note", etc.).
- Avoid repetitive section templates.
- Avoid excessive bullet lists unless the content is truly enumerative.
- Avoid "trade-off matrix" writing unless explicitly requested.
- Avoid over-explaining obvious steps.

## Chapter Construction Rules

- Every chapter must read like part of one continuous project narrative.
- Explanations should be grounded in the Runewarden domain, not abstract toy snippets unless needed for clarity.
- Assurance tools (`TEST`, `VERIFY`, `PROVE`) should be introduced as engineering instruments, not marketing features.
- Start each chapter with a short in-world literary prelude (one or two paragraphs max), then transition into technical content.

## Editing Discipline

- Prefer shorter paragraphs with concrete examples.
- Keep terminology consistent across chapters.
- If an operator stack order is non-obvious while writing examples, verify and document it in `docs/language-reference.md`.
