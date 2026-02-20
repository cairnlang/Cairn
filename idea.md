# Axiom: An AI-Native Programming Language

## Premise

Human programming languages encode human cognitive constraints: limited working memory (descriptive names, modularity), sequential visual parsing (indentation, syntax highlighting), and step-by-step imperative reasoning. An AI-native language should instead optimize for the actual bottlenecks of large language models: **semantic reasoning cost**, **compositional correctness**, and **context window utilization** — not just raw token density.

The original vision of Axiom focused heavily on compression. This revised design shifts the center of gravity toward **declarative constraint solving**, **content-addressable structure**, and **semantic density** — making programs that are not just short, but fundamentally easier for an AI to reason about, compose, and verify.

---

## Core Design Principles

### 1. Content-Addressable DAG, Not Relative Pointers

**Problem with the original:** Relative stack pointers (`^3`, `^12`) are fragile. Inserting or removing a single operation invalidates every downstream reference. The workaround of "just regenerate the whole function" defeats the purpose of having a structured language — you'd be treating code as disposable text, not a composable artifact.

**Revised design:** Every expression in Axiom is a node in a **content-addressed Directed Acyclic Graph (DAG)**. Each node is identified by a short hash derived from its operation and inputs.

```
a0 = INPUT [int]
a1 = a0 FILTER (2 MOD 1 EQ)
a2 = a1 MAP (SQ)
a3 = a2 SUM
```

- Inserting a new node between `a1` and `a2` does not break `a2`'s reference — `a2` still points at `a1` by hash, not by position.
- Identical subexpressions automatically deduplicate (structural sharing).
- The DAG is the IR *and* the source — there's no separate compilation step to an AST. The code *is* the graph.

**Why this matters for AI:** An LLM can generate, modify, and extend a DAG without needing global context about "what position am I at in the stack." Each node is self-contained and locally verifiable.

---

### 2. Constraint-Declarative Core (The Big Idea)

This is where Axiom should diverge most radically from human languages. Instead of specifying *how* to compute something, Axiom programs primarily declare *what properties the output must satisfy*, and a solver determines the execution strategy.

**Axiom's declarative mode:**
```
SORT : [a] -> [a]
  WHERE output CONTAINS_ALL input
    AND FORALL i : output[i] <= output[i+1]
```

The programmer (AI or human) declares the contract. The Axiom runtime selects an algorithm — quicksort, mergesort, radix sort — based on input characteristics, available hardware, and profiling data. The AI's job becomes **specifying correct constraints**, not choosing algorithms.

**Why this is the right direction:**
- LLMs are *better* at formal specification than at writing bug-free imperative code. Stating "the output is sorted" is easier to get right than implementing quicksort with correct pivot selection and partitioning.
- Constraints are **verifiable** — a constraint solver or property-based testing engine can mechanically check that outputs satisfy the spec, creating a tight feedback loop.
- It naturally supports **progressive refinement**: start with a loose spec, then add constraints to narrow behavior, rather than rewriting implementation details.

**Escape hatch:** Not everything can be declarative. Axiom should support an imperative postfix mode for performance-critical inner loops where the AI knows the exact algorithm it wants:

```
IMPERATIVE sort_impl : [int] -> [int]
  ... stack-based postfix instructions ...
```

The imperative mode is the "assembly language" of Axiom — available when needed, but not the default.

---

### 3. Semantic Naming Over No Naming

**Problem with the original:** Stripping all names in favor of positional references doesn't actually help AI reasoning. Names like `user_id` or `price_total` carry *type-level* and *domain-level* semantics that reduce ambiguity. An LLM benefits from these signals just as much as a human does — they reduce the search space for what a value *could* be.

**Revised design:** Axiom uses **short semantic tags** — not verbose human names, but compressed domain-meaningful identifiers:

```
uid:u32  ptot:f64  items:[Item]
```

- Tags are 2-6 characters, drawn from a controlled vocabulary per project.
- They serve double duty as documentation and as soft type annotations that the constraint checker can leverage.
- The AI is free to use terse tags that a human might find cryptic, but they still carry meaning — they're not just positional indexes.

---

### 4. Postfix Syntax for Imperative Blocks

The original plan's argument for postfix/RPN remains valid for imperative code paths. Bracket matching is genuinely harder for autoregressive generation than linear stack operations.

```
items 2 MOD 1 EQ FILTER SQ MAP SUM
```

- No parentheses, no bracket matching, no comma-separated argument lists.
- Operators consume from the stack and push results.
- Composition reads left-to-right as a pipeline — actually more intuitive than nested function calls even for humans (similar to Unix pipes).

This applies only to imperative blocks. Declarative constraint blocks use a structured `WHERE`/`AND`/`FORALL` syntax that prioritizes clarity of specification over token density.

---

### 5. First-Class Tensors, Distributions, and Similarity

This is retained from the original with some refinement. Axiom's type system includes:

| Primitive        | Notation    | Example                          |
|------------------|-------------|----------------------------------|
| Scalar           | `s:f64`     | `3.14`                           |
| Vector/Tensor    | `t:[f64;N]` | `[1.0 2.0 3.0]`                 |
| Embedding        | `e:emb512`  | 512-dim dense vector             |
| Distribution     | `d:dist`    | `NORMAL 0.0 1.0`                |
| Probability      | `p:prob`    | Value in `[0,1]`                 |

**Native operators:**
- `~` : cosine similarity (`e1 e2 ~ => prob`)
- `?>` : probabilistic branch (`p 0.9 ?> THEN_BLOCK ELSE_BLOCK`)
- `SAMPLE` : draw from a distribution
- Standard tensor ops (matmul, reshape, broadcast) as built-in operators, not library calls.

This eliminates the need for importing numerical frameworks for the most common AI-relevant operations.

---

### 6. Built-In Verification and Contracts

Every function in Axiom carries a **contract** — preconditions, postconditions, and invariants that the runtime can check.

```
sum_sq_odds : [int] -> int
  PRE  input.len > 0
  POST output == input.filter(odd).map(sq).sum
  POST output >= 0
```

- The AI writes the contract *first*, then (optionally) provides an implementation.
- If no implementation is provided, the solver attempts to synthesize one from the constraints.
- If an implementation is provided, the runtime verifies it against the contract on every call (in debug mode) or compiles away the checks (in release mode).

**Why this matters:** The hardest part of AI-generated code isn't writing it — it's *knowing whether it's correct*. Contracts give every function a machine-checkable definition of correctness. An AI can generate code, test it against its own contracts, and iterate — without needing a human to write test cases.

---

## Example: Sum of Squared Odds

**Python (human-native):**
```python
def sum_squared_odds(numbers):
    total = 0
    for n in numbers:
        if n % 2 != 0:
            total += n ** 2
    return total
```

**Axiom (declarative style):**
```
sum_sq_odds : [int] -> int
  POST output == input.filter(i : i 2 MOD 1 EQ).map(SQ).sum
```
Just the contract. The runtime synthesizes the implementation.

**Axiom (imperative style, when you need explicit control):**
```
sum_sq_odds : [int] -> int
  IMPERATIVE
    2 MOD 1 EQ FILTER SQ MAP SUM
```
Stack-based, dense, no brackets — but stable references if embedded in a larger DAG.

**Axiom (hybrid — contract + hint):**
```
sum_sq_odds : [int] -> int
  POST output >= 0
  IMPERATIVE
    2 MOD 1 EQ FILTER SQ MAP SUM
```
The contract acts as a runtime assertion; the implementation is explicit.

---

## Language Architecture Summary

```
┌─────────────────────────────────────────────┐
│              Axiom Program                  │
│                                             │
│  ┌─────────────┐     ┌──────────────────┐   │
│  │ Declarative  │     │   Imperative     │   │
│  │ Constraints  │     │   Postfix Blocks │   │
│  │ (default)    │     │   (opt-in)       │   │
│  └──────┬───────┘     └────────┬─────────┘   │
│         │                      │             │
│         ▼                      ▼             │
│  ┌─────────────────────────────────────┐     │
│  │    Content-Addressable DAG (IR)     │     │
│  │    Structural sharing + dedup       │     │
│  └──────────────┬──────────────────────┘     │
│                 │                             │
│                 ▼                             │
│  ┌─────────────────────────────────────┐     │
│  │  Contract Verifier / Solver         │     │
│  │  - Constraint synthesis             │     │
│  │  - Property-based testing           │     │
│  │  - Runtime assertion checking       │     │
│  └──────────────┬──────────────────────┘     │
│                 │                             │
│                 ▼                             │
│  ┌─────────────────────────────────────┐     │
│  │  Backend Code Generation            │     │
│  │  - Algorithm selection              │     │
│  │  - Hardware-aware optimization      │     │
│  └─────────────────────────────────────┘     │
└─────────────────────────────────────────────┘
```

---

## What Makes This Different From the Original Plan

| Aspect | Original Axiom | Revised Axiom |
|---|---|---|
| **Primary goal** | Token density | Reasoning correctness |
| **References** | Relative stack pointers | Content-addressed DAG nodes |
| **Naming** | None (positional only) | Short semantic tags |
| **Paradigm** | Imperative postfix only | Declarative-first, imperative escape hatch |
| **Correctness** | Not addressed | Contracts + solver verification |
| **Refactoring** | Destructive (regenerate all) | Stable (hash-based references survive edits) |
| **Core bet** | "Make it shorter" | "Make it provably correct" |

---

## Open Questions and Next Steps

1. **Solver feasibility:** How expressive can the constraint language be before synthesis becomes intractable? Need to define a decidable subset (likely linear arithmetic + common collection operations) and clearly delineate what requires manual implementation.

2. **Tokenizer co-design:** Should Axiom have its own tokenizer, or should it be designed to align with an existing LLM tokenizer (e.g., cl100k)? The latter would allow any off-the-shelf model to work with it; the former allows deeper optimization.

3. **Bootstrapping:** The first implementation of the Axiom runtime/solver will need to be written in an existing language (Rust? OCaml?). What's the minimal viable subset of Axiom that's useful before the solver is fully built?

4. **Human-in-the-loop:** Even if Axiom is AI-native, humans still need to audit AI-generated programs. Should there be a "decompile to pseudocode" mode that translates Axiom back to human-readable form for review?

5. **Multi-model collaboration:** If multiple AI agents collaborate on a codebase, the DAG structure and content-addressing naturally support merging and conflict resolution. This is worth exploring as a first-class workflow.
