# Runewarden Prose Style Guide

The book should feel written by a careful engineer with literary discipline, not by a chat assistant.

We are aiming at the tone of classic technical texts: direct, curious, and precise. The chapter should open with a concrete problem. It should then build one idea at a time until the mechanism is clear, and close by putting that mechanism to work inside the project. The reader should feel led, not managed.

The main failure mode is list-heavy writing. Lists are useful for inventories and checklists, but they flatten thought when used for explanation. Most explanation should be paragraph prose. Code blocks carry the burden of exactness; prose carries the burden of meaning.

Another failure mode is defensive hedging. We do not need to apologize for every design choice or wrap every paragraph in caveats. When a limitation matters, say it once, clearly, at the point where it matters. Then continue.

Avoid assistant habits: no motivational filler, no meta-commentary about being helpful, no repetitive "you can also" branches every few lines. Keep the reader inside the project.

Each chapter should open with a short in-world literary setup. Keep it charming but tight: one or two paragraphs, then begin the technical work.

When we discuss assurance (`TEST`, `VERIFY`, `PROVE`), describe them as engineering tools in the development loop. A test catches regressions in concrete behavior. A property check searches broad input space for broken invariants. A proof discharges a bounded class of obligations. These are not badges; they are instruments.

## Default Chapter Shape

1. Start from one practical tension in Runewarden.
2. Introduce the smallest new Cairn concept that resolves it.
3. Implement the concept in project code.
4. Check behavior with an assurance step.
5. End with a runnable milestone and a natural bridge to the next chapter.

## Language Conventions

- Prefer active voice.
- Prefer specific nouns from the setting (shaft, inspection, rune seal, foreman).
- Keep sentence length varied, but do not drift into ornate prose.
- Use humor rarely and dryly.
- Let examples do the persuasion.
