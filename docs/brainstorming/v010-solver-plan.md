# Cairn Solver: A Phased Implementation Plan

## Preamble

The constraint solver is the core of Cairn's long-term vision, enabling a shift from imperative programming to declarative specification. Its success hinges on a pragmatic, phased implementation. A "big bang" approach is infeasible; instead, we will build the solver in layers, with each layer providing tangible value to the language and its users.

This document outlines a 5-stage plan to incrementally build the solver, moving from simple verification to advanced program synthesis and optimization.

---

## Stage 1: Runtime Contract Checking (v0.0.1 - COMPLETE)

- **Description:** The most basic form of "solving." It answers the question: "For this *concrete* input, does the *concrete* output satisfy the contract?"
- **Implementation:** This is the current `PRE`/`POST` contract checking mechanism in the interpreter.
- **Value:** Provides immediate, essential feedback by turning specifications into runtime assertions. It forms the bedrock for all future solver work.

---

## Stage 2: Advanced Static Analysis & Type Inference (Target: v0.1.0)

- **Description:** Use contracts to inform a static analysis pass. This is a classic constraint satisfaction problem where the solver operates over types, not values.
- **Goal:** The solver acts as a powerful type checker that understands constraints, catching errors before runtime.
- **Example:**
  ```cairn
  DEF safe_sqrt : int -> int
    PRE { DUP 0 GTE }
    POST DUP 0 GTE
  END

  # The solver can infer that the output of safe_sqrt is not just `int`,
  # but a subtype `non_negative_int`. It can then flag this as a static error:
  -10 safe_sqrt # => Static Error: -10 does not satisfy PRE { DUP 0 GTE }
  ```
- **Implementation Plan:**
  - Develop an internal representation for types and their constraints (e.g., `int`, `non_negative_int`, `list(len=5)`).
  - Implement a unification-based algorithm in Elixir to solve for these types.
  - This stage should not require external dependencies.

---

## Stage 3: Integrated Property-Based Testing (Target: v0.2.0)

- **Description:** Leverage contracts to automatically generate test cases. The solver's role shifts from verifying programs to synthesizing *test data*.
- **Goal:** When a function is defined, the system automatically runs hundreds of tests against its contracts, providing a powerful verification feedback loop.
- **Example:**
  ```cairn
  DEF my_func : [int] -> int
    PRE { DUP LEN 5 EQ } # Input must be a list of 5 ints
    POST DUP 100 GT      # Output must be > 100
  END
  ```
  On definition, the solver will:
  1.  Generate 100s of random lists of 5 integers (satisfying the `PRE` condition).
  2.  Run `my_func` on each list.
  3.  Assert the result is `> 100` every time. If not, the test fails, flagging a faulty implementation.
- **Implementation Plan:**
  - Integrate a property-testing library like Elixir's `StreamData`.
  - Write a component that parses a `PRE` condition's AST and translates it into a data generator/filter.

---

## Stage 4: Synthesis for Bounded Domains (Target: v0.3.0)

- **Description:** The first true instance of program synthesis. The solver generates a function's body from its contracts alone, but only for a small, well-defined set of problems.
- **Goal:** Automatically generate correct implementations for simple, common patterns, allowing the programmer to focus on specification.
- **Example Domain:** Linear integer arithmetic and basic list properties.
  ```cairn
  # The user writes only the specification:
  DEF get_len : [a] -> int
    POST output EQ SWAP LEN
  END

  # The solver searches for a sequence of operators that satisfies the post-condition.
  # It finds the implementation: [LEN]
  ```
- **Implementation Plan:**
  - **Primary Option:** Integrate an external SMT (Satisfiability Modulo Theories) solver like **Z3** via an existing Erlang/Elixir library (e.g., `erlz3`).
    1.  Define a small, translatable subset of Cairn (e.g., integer ops, list ops `LEN`).
    2.  Implement a transpiler that converts Cairn contracts in this subset into the SMT solver's input format (SMT-LIB).
    3.  The SMT solution ("model") is then translated back into a sequence of Cairn operators.
  - **Secondary Option:** For trivial domains, an enumerative synthesizer (which tries all operator combinations) can be built in Elixir, but this approach does not scale.

---

## Stage 5: Heuristic Algorithm Selection (Target: v0.4.0)

- **Description:** A practical, high-value form of "solving." Instead of synthesizing an algorithm from scratch, the solver *selects* the best implementation from a library of human-written candidates based on runtime conditions.
- **Goal:** Enable a declarative style for complex operations (like sorting) while retaining high performance by dispatching to optimized imperative code.
- **Example:**
  ```cairn
  # 1. Declarative goal
  DEF sort : [a] -> [a]
    WHERE output CONTAINS_ALL input
      AND FORALL i : output[i] <= output[i+1]
  END

  # 2. Library of imperative providers
  IMPERATIVE quick_sort PROVIDES sort
    WHERE input.len > 20
    # ... highly optimized quicksort implementation
  END

  IMPERATIVE insertion_sort PROVIDES sort
    WHERE input.len <= 20
    # ... insertion sort is faster for small lists
  END
  ```
- **Implementation Plan:**
  - Introduce `PROVIDES` and `WHERE` keywords to the parser.
  - The "solver" becomes a runtime dispatch mechanism. When `sort` is called, it evaluates the `WHERE` clauses of all registered providers and executes the first one that returns true.
  - This is a robust, practical way to bridge the declarative and imperative worlds.
