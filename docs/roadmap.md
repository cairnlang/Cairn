# Axiom Roadmap

Unified plan consolidating the original brainstorming documents (see `docs/brainstorming/`).

Axiom bridges two philosophies: the BEAM's **"Let It Crash"** resilience and formal verification's **"Prove It Won't Crash"** rigor. The language is stack-based, postfix, contract-checked, with a static type checker, algebraic data types, property-based testing (VERIFY), and compile-time proof (PROVE via Z3).

---

## Completed

### v0.0.1 — Interpreter Core
- Stack-based postfix interpreter on the BEAM
- PRE/POST runtime contracts, `Axiom.ContractError`
- Blocks as closures, FILTER/MAP/REDUCE, TIMES/WHILE
- Recursion (functions call themselves by name)
- REPL, `mix axiom.run`, string literals, I/O (SAY, PRINT, ARGV, READ_FILE, WRITE_FILE)
- Content-addressed DAG store (ETS-backed, in place for future use)

### v0.1.0 — Static Type Checker + VERIFY
- Symbolic stack type checker (runs before evaluation)
- Catches: type mismatches, stack underflow, branch shape mismatches, undefined functions, return arity errors
- VERIFY — property-based contract testing via StreamData
- Maps (`M[]`, GET, PUT, DEL, HAS, KEYS, VALUES, MLEN, MERGE)
- Safe Bank milestone (deposit/withdraw with VERIFY)

### v0.2.0 — PROVE (Compile-Time Verification)
- Symbolic execution of function bodies into SMT-LIB v2 formulas
- Z3 integration: `PRE AND NOT(POST)` — if unsat, contract is mathematically proven
- Supports: integer arithmetic, comparisons, logic, stack manipulation

### v0.3.0 — Algebraic Data Types
- `TYPE name = Ctor1 | Ctor2 type | Ctor3 type type` declarations
- `MATCH ... END` pattern dispatch with exhaustiveness checking
- Recursive/mutually recursive type support
- Pre-registration of all function signatures (mutual recursion across functions)

### v0.4.0 — JSON Parser Milestone
- Wildcard MATCH (`_ { body }`) — catch-all pattern, discards fields
- String primitives: CHARS, SPLIT, TRIM, STARTS_WITH, SLICE, TO_INT, TO_FLOAT, JOIN
- ROT4 (4-element stack rotation), PAIRS (map to key-value list), NUM_STR
- VERIFY support for user-defined sum types (StreamData.tree depth-limited generation)
- Complete JSON parser + encoder written in Axiom (`examples/json.ax`)

### v0.4.1 — PROVE: Branches + Function Inlining
- PROVE handles IF/ELSE via `ite` (if-then-else) nodes in SMT-LIB
- ABS, MIN, MAX unlocked as syntactic sugar for conditionals
- Function call inlining during symbolic execution (depth limit 10)
- Compositional proofs: prove a helper, then prove functions that call it
- `examples/proven.ax` — abs, distance, clamp, symmetry proofs
- 610 tests passing

---

## Next Up

### v0.5.0 — Practical Language Features

**Goal:** Make Axiom usable for real programs beyond toy examples. The language has strong verification foundations but lacks practical features that any working language needs.

**Deliverables:**

- **LET bindings** — named local values for readability
  `LET x 42` pushes 42 and binds it to `x`; `x` pushes a copy.
  Stack-only code is fine for small functions but unreadable past 5-6 operations. Even Forth has variables.

- **String interpolation or formatting** — SAY/PRINT are bare-bones, no way to build formatted output

- **Error handling beyond contracts** — currently the only error mechanism is contract violations crashing. Need TRY/CATCH or Result-based error flow for I/O, parsing, and other fallible operations.

- **IMPORT / module system** — no way to split code across files. Every example is a single monolithic `.ax` file. A working language needs `IMPORT "file.ax"` or similar.

- **Standard library extraction** — move common patterns (abs, max, min, clamp, etc.) from inline definitions into a prelude that's always available

**Why now:** Axiom has a JSON parser, algebraic types, a type checker, VERIFY, and PROVE — but you still can't split code across files, name intermediate values, or handle errors gracefully. These gaps block any project larger than a single-file example.

### v0.6.0 — PROVE for Algebraic Types + Refinements

**Goal:** Extend PROVE to handle MATCH and unlock refinement-style reasoning.

**Deliverables:**
- PROVE handles MATCH by enumerating constructor cases (encode as nested `ite`)
- Provable examples: `safe_div`, `unwrap_or`, `map_option`
- PRE conditions narrow types within function bodies (refinement-lite)
- Static detection of unreachable branches after PRE
- Stretch: bounded recursion unrolling for simple recursive functions

**Why after v0.5.0:** More PROVE power is valuable but the language needs practical features first. No one will use PROVE on a program they can't modularize.

### v0.7.0 — Typed BEAM Concurrency

**Goal:** Type-safe message passing on the BEAM — the feature no other language has.

Axiom already has algebraic types and contracts. Combining them with BEAM processes creates typed actors with provable state transition invariants.

**Deliverables:**
- `SPAWN`, `SEND`, `RECEIVE` primitives
- `Pid<MessageType>` — typed process identifiers
- `RECEIVE` with MATCH-style pattern dispatch on message type
- State machine example with contract-checked transitions (traffic light)
- Supervisor integration — contract violations crash the process, supervisor restarts

**New syntax sketch:**
```
TYPE msg = Ping pid[msg] | Pong

DEF pinger : pid[msg] -> void
  DUP SELF Ping SWAP SEND
  RECEIVE
    Pong { "got pong" SAY DROP }
  END
END
```

**Why after v0.6.0:** Typed concurrency benefits enormously from PROVE — imagine proving that a state machine's transitions never violate an invariant across all message types.

### v0.8.0 — BEAM Bytecode Compilation

**Goal:** Compile Axiom to native BEAM bytecode instead of interpreting.

Currently Axiom interprets token streams. The DAG store (ETS) and Erlang Abstract Format codegen path were designed into the architecture from day one but deferred.

**Deliverables:**
- DAG-to-Erlang-Abstract-Format compiler
- `:compile.forms/1` integration — produce `.beam` modules
- Compiled functions callable from Elixir/Erlang
- Performance benchmarks vs. interpreted mode

---

## Future / Research

These are high-ambition features from the original vision documents. They require significant research and may evolve as the language matures.

### Declarative Constraint Solving
- `WHERE`/`FORALL` constraint blocks as an alternative to imperative function bodies
- Program synthesis from contracts (bounded domains first)
- Heuristic algorithm selection (`PROVIDES`/`WHERE` dispatch)

### Tensor and Distribution Primitives
- First-class tensor types with shape checking
- Distribution type (`NORMAL`, `SAMPLE`)
- Cosine similarity operator (`~`)
- Probabilistic branching (`?>`)

### Multi-Agent Collaboration
- Content-addressed DAG enables structural merge/conflict resolution
- Multiple AI agents editing the same codebase via DAG operations
- Typed inter-agent message passing (builds on v0.7.0 concurrency)

### Advanced Verification
- Inductive proofs for recursive functions
- Session types for protocol verification
- Linear types for resource management
- Contract synthesis (infer PRE/POST from implementation)

---

## Architecture

```
 source.ax
    |
    v
 Lexer --> tokens --> Parser --> functions + types + expressions + verify/prove
                                       |
                                       v
                                 Static Type Checker
                                 (symbolic stack, type unification,
                                  exhaustiveness, wildcard MATCH)
                                       |
                                       v
                                 Evaluator (stack-based interpreter)
                                       |
                                 +-----+----------+
                                 |     |          |
                           Runtime     |    Solver
                           (operators) |    (symbolic exec -> SMT-LIB -> Z3
                                 |     |     IF/ELSE via ite, function inlining)
                           Contract  Verify
                           checker   (StreamData, sum type generation)
                           (PRE/POST)
                                 |
                              result
```

---

## Source Documents

The original brainstorming documents that informed this roadmap are preserved in `docs/brainstorming/`:

- `idea.md` — Original language vision (AI-native, content-addressed DAG, constraint-declarative core)
- `v001-plan.md` — v0.0.1 implementation plan (lexer, parser, DAG, runtime, contracts, REPL)
- `v010-solver-plan.md` — 5-stage solver plan (runtime contracts -> static analysis -> PBT -> synthesis -> heuristic dispatch)
- `milestone-project-ideas.md` — 9-milestone project plan (typed calculator through bulletproof web API)
- `dag_and_stack.md` — Technical analysis of DAG/SSA representation for stack languages, row polymorphism, refinement types
