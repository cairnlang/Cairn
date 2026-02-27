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
- Complete JSON parser + encoder written in Axiom (`examples/json/core.ax` + `examples/json/demo.ax`, with `examples/json.ax` compatibility entrypoint)

### v0.4.1 — PROVE: Branches + Function Inlining
- PROVE handles IF/ELSE via `ite` (if-then-else) nodes in SMT-LIB
- ABS, MIN, MAX unlocked as syntactic sugar for conditionals
- Function call inlining during symbolic execution (depth limit 10)
- Compositional proofs: prove a helper, then prove functions that call it
- `examples/prove/proven.ax` — abs, distance, clamp, symmetry proofs
- 610 tests passing

### v0.5.0 — LET Bindings + Interactive I/O
- `42 LET x` — pops top value, binds to name, scoped to enclosing function/expression
- Rebinding shadows (e.g., `1 LET x 2 LET x x` → `[2]`)
- Type checker tracks LET binding types through the symbolic stack
- `ASK` — prompted input (`"Name? " ASK` prints prompt, reads line, pushes string)
- `RANDOM` — `100 RANDOM` pushes random int in [1, 100]
- `examples/guess.ax` — Tim Hartnell number guessing game using all three features
- 626 tests passing

### v0.5.1 — FMT + SAID
- `FMT` operator: pop format string, pop one value per `{}` placeholder, auto-convert, push result
- Auto-conversion: int/float→to_string, bool→"T"/"F", else→inspect
- Literal braces via `{{` and `}}`
- Type checker special-cases literal format strings (counts placeholders, pops that many values)
- `SAID` operator: destructive SAY — prints value then drops it (replaces ubiquitous `SAY DROP` pattern)
- All examples updated to use FMT and SAID
- 639 tests passing

### v0.5.2 — Minimal IMPORT / File Modules
- `IMPORT "path.ax"` top-level statement for multi-file programs
- Relative import resolution from the importing file's directory
- Recursive import loading (imports of imports)
- Import deduplication (each file loaded once per run)
- Import cycle detection with explicit error path
- `Axiom.eval_file/3` and `mix axiom.run` execute with import resolution

### v0.5.3 — Safe-By-Default Fallible Ops
- Built-in prelude sum type: `TYPE result = Ok any | Err str`
- Safe defaults return `result`: `READ_FILE`, `WRITE_FILE`, `TO_INT`, `TO_FLOAT`, `ASK`
- Explicit fail-fast variants: `READ_FILE!`, `WRITE_FILE!`, `TO_INT!`, `TO_FLOAT!`, `ASK!`
- Existing examples updated to use `!` where crash-on-error behavior is intended

### v0.5.4 — Prelude Bootstrap
- Added `lib/prelude.ax`, auto-loaded by `Axiom.eval_file/3` / `mix axiom.run`
- Initial helpers for result ergonomics: `result_is_ok`, `result_is_err`, `result_unwrap_or`
- Convenience wrappers: `to_int_or`, `to_float_or`, `read_file_or`, `ask_or`
- `AXIOM_NO_PRELUDE=1` opt-out for deterministic/debug runs
- `examples/option.ax` updated to use prelude result helpers

### v0.5.5 — Modular Prelude Split
- Split prelude implementation into modules: `lib/prelude/result.ax` and `lib/prelude/str.ax`
- Kept `lib/prelude.ax` as a stable auto-loaded facade
- Added reusable helpers: `result_is_ok`, `result_is_err`, `result_unwrap_or`, `lines_nonempty`, `csv_ints`
- Added tests for modular prelude helpers and user override/shadowing in file mode

### v0.6.0a — PROVE MATCH (Option Slice)
- PROVE now supports `MATCH` when the matched value is `option`
- Symbolic encoding introduces option tag/payload variables with tag domain constraints
- MATCH arm dispatch is encoded as `ite` over `option` tag
- Unsupported MATCH shapes still return `UNKNOWN` with clear messaging
- Added `examples/prove/proven_option.ax` and solver tests for option-MATCH proofs

### v0.6.0b — PROVE MATCH (Result Slice)
- PROVE now supports `MATCH` when the matched value is `result`
- Symbolic encoding introduces result tag/Ok-payload variables with tag domain constraints
- MATCH arm dispatch is encoded as `ite` over `result` tag
- Added `examples/prove/proven_result.ax` and solver tests for result-MATCH proofs
- Non-supported MATCH shapes still return `UNKNOWN` with explicit reason

### v0.6.0c — PROVE MATCH (Generic Non-Recursive ADT Slice)
- PROVE now supports `MATCH` for user-defined ADTs with non-recursive `int` fields
- Generic symbolic encoding introduces constructor tag/payload vars from type definitions
- Constructor branch dispatch is encoded as nested `ite` over symbolic constructor tags
- Added `examples/prove/proven_shape.ax` and solver coverage for generic ADT MATCH proving
- `PROVE` now passes full type environment into symbolic parameter generation

### v0.6.0d — ADT Counterexample Decoding
- PROVE now decodes ADT model variables into constructor-shaped counterexamples
- Counterexample formatting now handles `option`, `result`, and generic user ADTs
- Added `examples/prove/proven_shape_buggy.ax` to demonstrate decoded ADT failure output
- Added solver coverage for ADT counterexample formatting and failing generic MATCH proofs

### v0.6.0e — PRE-Driven MATCH Branch Pruning
- PROVE now carries simple constructor-tag assumptions inferred from PRE into symbolic body execution
- Symbolic MATCH execution can prune unreachable arms for `option`, `result`, and generic ADTs
- Added `examples/prove/proven_shape_pruned.ax` showing an unreachable unsupported arm no longer blocks proof
- Added solver coverage for pruning behavior and PRE-narrowed generic ADT proofs

### v0.6.0f — Broader PRE Inference + PROVE Example Organization
- PRE inference now handles richer boolean forms (`AND`, `OR`, `NOT`, and related `ite_bool` shapes)
- MATCH pruning can use both positive (`eq`) and exclusion (`neq`) tag assumptions conservatively
- Added solver coverage for OR/NOT-driven narrowing and exclusion-based pruning
- Moved proof examples into `examples/prove/` and added `examples/prove/all_proven.ax`

### v0.6.0g — PROVE MATCH Trace Diagnostics
- Added optional trace diagnostics for PROVE MATCH branch decisions (trace env flag)
- Trace output reports explored branches, pruned branches, and pruning reason (`eq`, `neq`, `unknown`)
- Added `examples/prove/proven_shape_trace.ax` and solver coverage for trace output

### v0.6.0h — Trace Control Polish
- PROVE trace now supports levels: `summary` and `verbose`
- Trace can be enabled via `AXIOM_PROVE_TRACE=summary|verbose` or API env `__prove_trace__`
- Trace output now routes to stderr so normal PROVE output on stdout stays clean
- Added solver coverage for level behavior and stdout/stderr separation

### v0.6.0i — Structured Trace Output
- Added JSON trace mode: `AXIOM_PROVE_TRACE=json` (or API `__prove_trace__ => :json`)
- JSON mode emits one stderr JSON object per MATCH decision for tooling/CI consumption
- Preserved human-readable summary/verbose trace formatting as default diagnostics
- Added solver coverage for JSON trace shape and stderr routing behavior

### v0.6.0j — Richer JSON Trace Metadata
- JSON trace now emits `prove_run_start` and `prove_run_end` events
- Added stable `event_index` sequencing across JSON trace events
- Added deterministic `match_site_id` (`function:phase:token_pos`) and `phase` metadata on MATCH decisions
- Added inferred assumption snapshots (`eq` / `neq`) to MATCH decision events
- Added solver coverage for schema stability of run metadata and match context fields

### v0.6.0k — JSON Proof Lifecycle Events
- JSON trace now emits lifecycle events: `pre_executed`, `body_executed`, `post_executed`, `z3_query`
- `prove_run_end` now includes `unknown_reason` / `error_reason` and compact run stats (`body_stack_depth`, counts, elapsed time)
- Added solver coverage for lifecycle event presence and UNKNOWN-run metadata behavior

### v0.6.0l — Helper-Boolean Refinement Inference
- Broadened PRE inference by normalizing boolean-equivalence forms used by helper predicates (e.g. `helper_bool T EQ`)
- This allows MATCH pruning from helper-derived booleans beyond direct tag comparisons
- Added `examples/prove/proven_shape_refine.ax` and coverage for helper-equality narrowing proofs

### v0.6.0m — Composed-Helper Boolean Normalization
- Broadened PRE normalization with boolean identities useful for composed helpers:
  idempotence (`a AND a`, `a OR a`), complements (`a AND !a`, `a OR !a`), and absorption (`a AND (a OR b)`, `a OR (a AND b)`)
- This preserves constructor-tag narrowing when helper guards include logically dead composed branches
- Added `examples/prove/proven_shape_composed.ax` and solver coverage for composed-helper narrowing plus a tautology-limit case

### v0.6.0n — Split-Guard Alias Reduction
- Broadened PRE normalization for split aliases of boolean guards:
  `(a AND b) OR (a AND !b) => a` (plus symmetric variants)
- This preserves constructor narrowing when helper guards are expressed via split branches
- Added `examples/prove/proven_shape_split.ax` and solver coverage for split-guard narrowing

### v0.6.0o — Implication+Antecedent Reduction
- Broadened PRE normalization for implication forms combined with their antecedent:
  `(NOT c OR tag_guard) AND c => tag_guard` (plus symmetric variants)
- This preserves constructor narrowing when guard constraints are written as implications
- Added `examples/prove/proven_shape_implication.ax` and solver coverage for implication narrowing and implication-only limit behavior

### v0.6.0p — Canonical Boolean PRE Normalization
- Canonicalized n-ary boolean PRE constraints via flattening, deduplication, stable ordering, complement checks, and absorption cleanup
- Kept split/equivalence reductions active as pairwise rewrites on canonicalized OR terms
- This reduces inference brittleness for noisy/generated guard structures that are logically equivalent
- Added `examples/prove/proven_shape_canonical.ax` and solver coverage for noisy duplicated/reordered guard narrowing

### v0.6.0q — PRE Normalizer Extraction
- Extracted PRE canonicalization logic from `Axiom.Solver.Prove` into `Axiom.Solver.PreNormalize`
- Kept PROVE behavior unchanged while reducing solver-module complexity and isolating rewrite logic
- Added focused unit coverage for canonicalization/rewrite rules in `test/axiom/solver/pre_normalize_test.exs`

### v0.6.0r — DeMorgan + Comparison Negation Pushdown
- Added bounded `NOT` pushdown in PRE normalization:
  `NOT (a AND b) => (NOT a OR NOT b)` and `NOT (a OR b) => (NOT a AND NOT b)`
- Added comparison-negation flips (`NOT EQ => NEQ`, `NOT GT => LTE`, etc.) and complement-aware rewrites so prior inference remains stable
- Added `examples/prove/proven_shape_demorgan.ax` and coverage in both `pre_normalize_test.exs` and solver integration tests

### v0.6.0s — Local Comparison Pair Pruning
- Added local contradiction/tautology detection for pairwise comparisons over the same expression with integer constants
- Supports non-complement constant cases (e.g. `x > 5 AND x <= 3` => false, `x > 5 OR x <= 7` => true)
- Added `examples/prove/proven_shape_pair_prune.ax` and coverage in both `pre_normalize_test.exs` and solver integration tests

### v0.6.0t — Interval-Merge Bound Tightening
- Added conjunction-time interval merging for same-expression integer bounds (`>`, `>=`, `<`, `<=`) in PRE normalization
- Collapses closed singletons to equality (e.g. `x >= 5 AND x <= 5` => `x == 5`) and detects empty merged intervals early
- Added `examples/prove/proven_shape_interval_merge.ax` and coverage in both `pre_normalize_test.exs` and solver integration tests

### v0.6.0u — Shared-Conjunct Factoring
- Added bounded pairwise factoring for disjunctive conjunctions in PRE normalization:
  `(A AND B) OR (A AND C) => A AND (B OR C)`
- This exposes shared narrowing atoms that can then combine with existing tautology/implication reductions
- Added `examples/prove/proven_shape_factored.ax` and coverage in both `pre_normalize_test.exs` and solver integration tests

### v0.6.0v — Guarded One-Step Distribution
- Added bounded guarded distribution in PRE normalization:
  `A OR (B AND C) => (A OR B) AND (A OR C)` when `A` looks like a narrowing atom
- This exposes implication-friendly clauses that combine with existing complement/implication rewrites
- Added `examples/prove/proven_shape_distribute.ax` and coverage in both `pre_normalize_test.exs` and solver integration tests

### v0.6.0w — Consensus Reduction
- Added bounded pairwise consensus reduction in conjunctions of disjunctions:
  `(A OR B) AND (A OR NOT B) => A`
- Reused existing complement detection so reduction also works for comparison-negation complements
- Added `examples/prove/proven_shape_consensus.ax` and coverage in both `pre_normalize_test.exs` and solver integration tests

---

## Next Up

### v0.6.x — PROVE MATCH Refinement

**Goal:** Improve precision and ergonomics on top of generic ADT MATCH support.

**Deliverables:**

- **Broader constructor inference** — recognize additional refinement-like PRE patterns around MATCH helpers
- **Richer structured diagnostics** — expand proof context fields beyond current lifecycle/match metadata
- **Provable examples** — add MATCH-heavy examples showing refinement-like reasoning over ADT contracts

**Why now:** consensus reduction is now covered; next gains are deeper inference coverage and broader proof context.

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
