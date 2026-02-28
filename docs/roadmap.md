# Axiom Roadmap

Unified plan consolidating the original brainstorming documents (see `docs/brainstorming/`).

Axiom bridges two philosophies: the BEAM's **"Let It Crash"** resilience and formal verification's **"Prove It Won't Crash"** rigor. The language is stack-based, postfix, contract-checked, with a static type checker, algebraic data types, property-based testing (VERIFY), and compile-time proof (PROVE via Z3).

---

## Completed

### v0.0.1 — Interpreter Core
- Stack-based postfix interpreter on the BEAM
- PRE/POST runtime contracts, `Axiom.ContractError`
- Blocks as closures, FILTER/MAP/REDUCE, TIMES/REPEAT/WHILE
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

### v0.6.0x — Rewrite-Aware JSON Trace
- Added explicit `rewrite_applied` JSON trace events for PRE normalization rewrites (`rule`, local `before`, local `after`)
- Added PRE context snapshots to `match_decision` events (`pre_raw`, `pre_normalized`, `pre_rewrite_summary`)
- Added run-end rewrite aggregates (`rewrite_event_count`, `rewrite_summary`) and a focused trace example: `examples/prove/proven_shape_trace_rewrites.ax`

### v0.6.0y — Tag-Bound Assumption Support
- Extended PROVE tag assumptions to carry optional min/max bounds (inclusive/exclusive) alongside existing `eq`/`neq`
- MATCH candidate filtering now respects these bounds when assumptions are present, and trace assumption snapshots include bound fields
- Added coverage in solver tests plus `examples/prove/proven_shape_tag_bounds.ax`

### v0.6.0z — Helper-Comparison Tag Inference
- Added assumption extraction for helper-comparison shapes over tag booleans encoded as integer `ite` expressions
- This enables real MATCH pruning from patterns like `tag_helper(...) > 0` even when PRE does not contain direct tag comparisons
- JSON trace `match_decision` now includes `inference_source`, and assumption snapshots include source labels (e.g. `helper_cmp`)

### v0.6.0aa — Broader Helper-Comparison Extraction
- Extended helper-pattern extraction to support `eq/neq` comparisons in addition to inequality forms
- Added bounded affine support around tag-boolean `ite` encodings (`+ const`, `- const`, `const - expr`) before comparison checks
- Added `examples/prove/proven_shape_tag_bounds_eq.ax` and solver coverage for helper-encoded `EQ` narrowing

### v0.6.0ab — Multiplicative Helper Wrappers
- Extended bounded helper-pattern extraction to support multiplicative constant wrappers around tag-boolean encodings (`expr * const`, `const * expr`)
- This enables narrowing for generated helper forms like `code * 2 == 2` without requiring direct tag comparisons
- Added `examples/prove/proven_shape_tag_bounds_mul.ax` and solver coverage for helper-encoded `MUL+EQ` narrowing

### v0.6.0ac — PROVE Stabilization Gate
- Added PRE-normalizer idempotence coverage to prevent canonicalization drift under repeated normalization
- Added JSON trace stability coverage for contiguous `event_index` sequencing and run boundary events
- Added a relaxed runtime budget guard for `examples/prove/all_proven.ax` to catch severe performance regressions
- Documented rule-admission criteria and locked this slice to guardrails (no broad speculative inference expansion)

### v0.6.0ad — Tactical PRE Freeze
- Marked `Axiom.Solver.PreNormalize` as tactical-freeze target (feature expansion gated; bugfix/refactor by default)
- Added explicit rule-admission process doc: `docs/prove-rule-admission.md`
- Added rewrite-metadata catalog guardrails via `PreNormalize.rewrite_rule_catalog/0` and tests that keep emitted rule names within the frozen catalog

### v0.6.1a — Practical Language Usability (CLI/Diagnostics Pass 1)
- Added clearer `PROVE ... UNKNOWN` hints with actionable guidance (use VERIFY or simplify proof surface)
- Added contextual PROVE error hints for common setup/runtime failures (missing Z3, temp-file failures)
- Added `mix axiom.run` run-summary diagnostics on stderr (status, value count, elapsed ms)
- Added CLI/solver coverage for summary output and UNKNOWN hint behavior

### v0.6.1b — Practical Language Usability (CLI/Prelude Discoverability)
- Added `mix axiom.run --help` with options and environment guidance (`AXIOM_NO_PRELUDE`, `AXIOM_PROVE_TRACE`)
- Added `mix axiom.run --show-prelude` (and `--verbose`) to print loaded prelude modules/functions before execution
- Added CLI coverage for help output and prelude discoverability banner behavior
- Added organized prelude-focused examples under `examples/prelude/` for result flow, CSV parsing, and safe I/O fallback

### v0.6.1c — Practical Language Usability (Diagnostics Consistency Pass)
- Added unified CLI failure diagnostics (`ERROR kind=...`) for static/runtime/contract failures with message, hint, and optional location/snippet
- Added `--json-errors` option to emit structured machine-readable diagnostics on stderr
- Added diagnostic formatting module and focused tests for text/JSON diagnostic shapes
- Added `examples/diagnostics/` programs covering static, runtime, and contract failure modes
- Standardized PROVE unknown/error output into explicit `reason` + `hint` lines

### v0.6.1d — Practical Language Usability (Onboarding/CLI Reference Pass)
- Added `mix axiom.run --examples` to print categorized runnable example paths (basics/prelude/diagnostics/prove)
- Added a focused `docs/cli.md` quick reference for options, env vars, output conventions, and failure modes
- Added a README "First 15 Minutes" workflow to cover run/browse/fail/debug/verify/prove progression
- Added CLI test coverage for examples-index output and help text option surface

### v0.6.1e — Practical Language Usability (Examples/Docs Quality Pass)
- Added a practical mini-app under `examples/practical/` combining IMPORTs, prelude helpers, file I/O fallback, and VERIFY
- Added curated examples smoke coverage (`test/axiom/examples_smoke_test.exs`) to detect docs/examples drift early
- Expanded CLI examples index with a `practical` category and refreshed docs to point to practical workflows
- Updated README and `docs/cli.md` to keep quick-start/onboarding aligned with current capabilities

### v0.6.2a — Practical Programs Milestone (Pass 1)
- Added larger practical workflows: `examples/practical/ledger.ax` and `examples/practical/todo.ax`
- Added shared practical libs: `examples/practical/lib/ledger.ax` and `examples/practical/lib/todo.ax`
- Added supporting practical datasets under `examples/practical/data/`
- Expanded examples index and smoke coverage to include new practical workflows
- Kept practical examples centered on IMPORT + prelude + safe file I/O + VERIFY (PROVE optional)

### v0.6.2b — Practical Programs Milestone (Pass 2)
- Added app-level practical assertions via reusable helpers in `examples/practical/lib/ledger.ax` and `examples/practical/lib/todo.ax`
- Added report round-trip checks in ledger/todo flows (write report, read back, assert metric markers)
- Added argv-driven practical workflow: `examples/practical/ledger_cli.ax` (with default-path fallback)
- Expanded examples index and smoke checks to include deterministic output markers for practical programs

### v0.6.2c — Practical Programs Milestone (Pass 3)
- Added larger practical workflow `examples/practical/expenses.ax` with module split:
  `lib/expenses_parser.ax`, `lib/expenses_agg.ax`, `lib/expenses_report.ax`
- Added dataset `examples/practical/data/expenses.csv` and optional argv path override in `expenses.ax`
- Added report round-trip assertion and practical VERIFY guard (`abs_total_nonneg`) for the expenses flow
- Expanded examples index and smoke-marker assertions to include deterministic expenses outputs

### v0.6.2d — Practical Programs Milestone (Pass 4)
- Added shared practical helper module `examples/practical/lib/report_common.ax` to centralize assertions/report contains checks
- Refactored ledger/todo/expenses report helpers to use shared report/assert helpers
- Added composed cross-file workflow `examples/practical/cashflow.ax` (ledger + expenses inputs, combined cashflow metrics, report round-trip assertion)
- Added composed helper module `examples/practical/lib/cashflow.ax` with contract-checked scoring function and report marker checks
- Expanded examples index and smoke-marker assertions for deterministic cashflow output markers

### v0.6.2e — Practical Programs Milestone (Pass 5)
- Added multi-step composed workflow `examples/practical/cashflow_alerts.ax` extending cashflow metrics into risk classification/action outputs
- Added `examples/practical/lib/cashflow_alerts.ax` with contract-checked `risk_level` partitioning and label/action helpers
- Expanded practical examples index and smoke-marker assertions for deterministic alerts-stage outputs
- Updated docs to present the composed pipeline progression: ledger/expenses -> cashflow -> cashflow_alerts

### v0.6.3 — Practical Programs Milestone (Consolidation)
- Added `examples/practical/all_practical.ax` to run the consolidated practical chain in one command
- Added dedicated practical test target `mix test.practical` (alias for `test/practical/pipeline_test.exs`)
- Added `docs/practical-pipeline.md` documenting staged practical flow, expected outputs, and invariants
- Polished practical examples for consistent usage headers and source/output marker conventions
- Expanded practical smoke coverage to include `all_practical.ax` and deterministic marker checks across the full chain

### v0.7.0a — Typed Concurrency Foundations
- Added `pid[T]` to the type grammar, including nested use inside user-defined sum types
- Added parser/type-checker support for `SPAWN MessageType { ... }`, `SEND`, and `RECEIVE ... END`
- Kept concurrency runtime explicitly deferred with clear runtime errors for process ops
- Added static-only example programs under `examples/concurrency/`
- Expanded tests and examples index coverage for the typed-concurrency groundwork

### v0.7.0b — Minimal Typed Concurrency Runtime
- Implemented runtime `SPAWN`, `SEND`, and one-shot `RECEIVE` over BEAM processes/mailboxes
- Defined spawned-block semantics: the actor block starts with its own typed pid on the stack and must consume it
- Added runnable example `examples/concurrency/ping_once.ax` alongside the type-focused concurrency examples
- Added direct runtime tests covering spawn/send/receive flow and the spawned self-pid contract

### v0.7.0c — Actor Self Handle
- Added `SELF` as a runtime operator returning the current actor's typed pid
- Restricted `SELF` statically to `SPAWN` block checking contexts
- Added `examples/concurrency/self_boot.ax` to demonstrate self-messaging bootstrap
- Expanded concurrency runtime tests and examples index coverage for `SELF`

### v0.7.0d — Actor Context Through Helper Calls
- Added checker-side actor-context propagation for functions that use `SELF`
- Functions that directly or indirectly depend on `SELF` now type-check inside actors and fail clearly outside actor context
- Updated `examples/concurrency/self_boot.ax` to exercise `SELF` via a helper function instead of inline only
- Expanded concurrency type tests to cover actor-required helper calls

### v0.7.0e — Actor-Local RECEIVE
- Added actor-local `RECEIVE` inside concrete actor contexts so handlers no longer need to juggle the self pid across sequential receives
- Preserved explicit-pid `RECEIVE` as a fallback outside the actor-local path
- Added `examples/concurrency/two_pings.ax` to demonstrate handling two messages in sequence
- Expanded concurrency type/runtime tests and examples index coverage for repeated actor-local receives

### v0.7.0f — Stateful Actor Pattern
- Added `examples/concurrency/counter.ax` as the first stateful actor example built on repeated actor-local `RECEIVE`
- Demonstrated stack-carried actor state across multiple message-handling steps without new syntax
- Expanded concurrency runtime coverage for multi-step state transitions
- Expanded examples index and docs to present the stateful actor pattern explicitly

### v0.7.0g — Named Stateful Actor Transitions
- Added `examples/concurrency/traffic_light.ax` as a richer stateful actor example with named transition helpers
- Demonstrated a clearer application-level actor pattern (phase emission + phase transition) without new runtime features
- Expanded concurrency runtime coverage for multi-step named state transitions
- Expanded examples index and docs to present the traffic-light actor pattern explicitly
- Started a shared actor helper area under `examples/concurrency/lib/` with `lib/actor.ax`

### v0.7.0h — Shared Actor Helper Refactor
- Extracted common self-send behavior into `examples/concurrency/lib/actor.ax` (`send_self`)
- Refactored runtime actor examples to use the shared actor helper
- Fixed actor-context propagation so imported actor helpers participate in the same checker model as local helpers

### v0.7.0i — Shared State Helpers And Practical Actor Example
- Added `examples/concurrency/lib/state.ax` with a reusable state-preserving emit helper (`emit_keep`)
- Refactored examples to use shared actor/state helper modules where that improved clarity without fighting the checker
- Added `examples/concurrency/notifier.ax` as a more practical notifier-style actor workflow
- Expanded concurrency runtime coverage and docs for the shared helper layer plus practical actor example

### v0.7.0j — Linked Actor Lifecycle Basics
- Added `SPAWN_LINK` for linked actor startup
- Added actor-only `EXIT` for explicit actor termination with a reason
- Added `examples/concurrency/linked_failure.ax` as an intentionally failing lifecycle example
- Expanded runtime tests to contrast unlinked actor failure vs linked failure propagation

### v0.7.0k — Minimal Supervision Visibility And Restart Workflow
- Added `MONITOR` as a bounded lifecycle primitive that waits for a pid to exit and returns a normalized string reason
- Added `examples/concurrency/lib/supervision.ax` with a small reusable `await_exit` helper
- Added `examples/concurrency/restart_once.ax` as the first runnable restart workflow
- Expanded runtime/type coverage plus the runnable examples index for supervision-oriented flows

### v0.7.0l — Non-Blocking Monitor Handles And Reusable Restart Helpers
- Changed `MONITOR` into a non-blocking monitor-handle primitive that returns `monitor[T]`
- Added `AWAIT` to block on a monitor handle and yield the normalized exit reason
- Added `block[T]` return-shape typing so helper functions can safely `APPLY` pid-producing blocks
- Upgraded `examples/concurrency/lib/supervision.ax` to provide `watch_exit`, `await_exit`, and a reusable `restart_once` helper

### v0.7.0m — Explicit Supervisor/Worker Example
- Added `examples/concurrency/supervisor_worker.ax` as the first example that clearly separates supervisor flow from worker behavior
- Kept the slice example-first: no new runtime semantics, just stronger coverage of the current lifecycle model
- Expanded runnable example discovery plus type/runtime tests around the explicit supervisor/worker pattern

### v0.7.0n — Bounded Protocol-Checked Actors
- Added a checker-only protocol layer for finite two-party flows over the existing `TYPE msg = ...` message vocabulary and `pid[msg]` transport
- Kept the first slice deliberately bounded: no recursion, no multiparty protocols, no protocol inference, and no `PROVE` integration
- Added protocol-bound `SPAWN ... USING protocol_name { ... }` checking for local send/receive-sequence conformance
- Added one successful protocol example (`examples/concurrency/protocol_ping_pong.ax`) plus one failing mismatch example (`examples/concurrency/protocol_mismatch.ax`)

### v0.7.0o — Protocol Helper Ergonomics
- Added checker-side protocol effect summaries for simple local actor helpers
- Protocol-bound actor blocks can now call small helper functions that perform bounded `SEND`/single-arm-`RECEIVE` sequences without losing local conformance checking
- Expanded protocol coverage so helper-call mismatches fail at the call site with protocol-aware diagnostics
- Updated `examples/concurrency/protocol_ping_pong.ax` to exercise helper-based protocol conformance rather than only inline steps

### v0.7.1a — Explicit State Threading Foundations
- Added `WITH_STATE`, `STATE`, and `SET_STATE` as a bounded, explicit local-state model for block-scoped state evolution
- Kept the feature deliberately local: no shared mutation, no outer-scope rebinding, and no changes to ordinary block semantics
- Enforced same-type state updates plus stack-clean `WITH_STATE` bodies in both the checker and runtime
- Rewrote `examples/concurrency/counter.ax` around `WITH_STATE`, making the first actor-state example use explicit local state threading instead of raw stack-carried state

### v0.7.1b — Composite Actor State Follow-Through
- Added direct runtime/checker coverage for `WITH_STATE` carrying ADT-wrapped composite state, proving the feature works beyond a single scalar value
- Rewrote `examples/concurrency/guess_binary.ax` so both actors now keep their working state inside typed `WITH_STATE` values rather than split stack/`LET` juggling
- Used user-defined sum types (`ref_state`, `search_state`) to carry pids plus bounds/flags, establishing the intended near-term pattern for richer actor workflows without introducing mutation

### v0.7.1c — Typed Variant State Machines In Actor Loops
- Rewrote `examples/concurrency/traffic_light.ax` around `WITH_STATE` plus a dedicated `light_state` sum type, removing the older stack-carried string state
- Added direct runtime/checker coverage for `WITH_STATE` driving a small variant-based state machine, not just scalar or multi-field wrapper updates
- This confirms an immediate concurrency ergonomics gain: actor-local state machines become clearer when state lives in a user ADT and transitions are expressed with ordinary `MATCH`

### v0.7.1d — Bounded Repetition For Actor Steps
- Added `REPEAT` as a readability-oriented bounded repetition operator with the same stack behavior as `TIMES`
- Rewrote `examples/concurrency/counter.ax`, `examples/concurrency/traffic_light.ax`, and `examples/concurrency/guess_binary.ax` around helper-driven `REPEAT` loops, removing the manual unrolled `RECEIVE` chains
- This is the first direct reduction of concurrency-example boilerplate after the `WITH_STATE` work: repeated actor steps now compress into one visible state transition block instead of duplicated receive bodies

### v0.7.1e — STEP Combinator For Stateful Actor Loops
- Added `STEP fn` as a bounded `WITH_STATE`-only combinator for applying a `state -> state` helper and storing the result back into the hidden local state
- Rewrote the `REPEAT`-based actor examples (`counter.ax`, `traffic_light.ax`, `guess_binary.ax`) from `STATE ... SET_STATE` plumbing to `STEP helper`, making the intended state-transition unit explicit
- This is a small but real readability lift: the common actor loop shape is now “repeat this state step” instead of “load hidden state, call helper, write hidden state back”

---

## Next Up

### Transition Plan (v0.6.x -> v0.7)

The current PROVE MATCH refinement line has delivered substantial gains, but PRE normalization and helper-pattern extraction are now deep enough that incremental tactics should be bounded. The transition plan below keeps PROVE practical while shifting primary momentum back to language usability.

### v0.7.0 — Typed BEAM Concurrency Runtime Completion
**Goal:** Type-safe message passing on the BEAM — the feature no other language has.

Axiom already has algebraic types and contracts. Combining them with BEAM processes creates typed actors with provable state transition invariants.

**Deliverables:**
- Broader actor ergonomics beyond the current `SELF`/actor-local-`RECEIVE` plus stack-state model
- Richer `RECEIVE` forms (loop-friendly patterns, multi-message actor workflows)
- `pid[MessageType]` — typed process identifiers with stronger runtime ergonomics
- `RECEIVE` with MATCH-style pattern dispatch on message type across larger actor state machines
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

**Why after v0.6.x transition:** Typed concurrency benefits enormously from PROVE — imagine proving that a state machine's transitions never violate an invariant across all message types while the core language ergonomics are already stable.

**Bounded protocol slice now landed inside v0.7.0:** the minimal protocol-checking layer (session-type-inspired, but practical) now covers finite two-party message order statically; the next work in this track is broader ergonomics on top of that foundation.

### Practical Language Side Path (bounded, non-concurrency)
These are worthwhile practicality slices that can be interleaved with the v0.7.0 concurrency track when we want fast, low-risk progress outside actor semantics. The ordering below is intentional.

#### 1. Collection Helpers First
**Goal:** Improve day-to-day scripting and data wrangling without adding major semantic weight.

**First candidates:**
- `ZIP`
- `ENUMERATE`
- `FLAT_MAP`
- Possibly follow-up helpers like `FIND`, `TAKE`, or `DROP` if examples immediately justify them

**Scope note:** without full parametric polymorphism, some of these will necessarily degrade to `any` in their result shape. That tradeoff is acceptable for a first practical slice if documented explicitly.

**Why first:** highest value-per-effort, no deep architectural commitment, and directly useful for practical examples.

**Bounded slices now landed:** the first collection-helper pass added `ZIP`, `ENUMERATE`, and `FLAT_MAP`; the follow-up pass added `TAKE`, `FIND`, and `GROUP_BY`. The shape-heavy cases still use a pragmatic type story, and `examples/collections.ax` now serves as the focused showcase for the whole mini-stack.

**Current concurrency examples also now include a bounded binary-search game slice:** `examples/concurrency/guess_binary.ax` now doubles as the first composite-`WITH_STATE` actor workflow, proving the current actor runtime plus explicit state threading can carry a small stateful search workflow without adding new concurrency primitives.

#### 2. Float Math As Explicit Float Ops
**Goal:** Add practical numeric capability without forcing a broader numeric-type redesign yet.

**First candidates:**
- `SIN`
- `COS`
- `EXP`
- `LOG`
- `SQRT`

**Bounded scope:**
- Treat these as `float -> float` operations in the checker
- Require explicit conversion (`TO_FLOAT`) rather than introducing a global `num` supertype first
- Make `PROVE` degrade cleanly to `UNKNOWN` for functions that use unsupported transcendental operations

**Why second:** runtime support is cheap and the semantics are clear, but the checker and `PROVE` behavior still need a disciplined slice.

**Bounded slice now landed (`v0.7.2a`):**
- Added `SIN`, `COS`, `EXP`, `LOG`, and `SQRT` as explicit `float -> float` runtime operators backed by Elixir `:math`
- Kept the type story intentionally narrow: these operators require `float` inputs, with no new global numeric supertype or implicit coercion
- Added clear runtime domain checks for `LOG` (`> 0.0`) and `SQRT` (`>= 0.0`)
- Made `PROVE` degrade cleanly to `UNKNOWN` when these transcendental operators appear, preserving solver correctness instead of crashing or pretending support
- Added `examples/math.ax` as the focused showcase for the explicit-float slice

**Small follow-up now landed (`v0.7.2b`):**
- Added `PI` and `E` as explicit float constants plus `POW` as a binary `float -> float` operator
- Kept the same bounded type discipline: no implicit coercion and no numeric-lattice redesign
- Extended the math showcase and tests so the explicit-float slice now covers constants, unary transcendental ops, and one binary power primitive
- Kept `PROVE` conservative: `PI`, `E`, and `POW` also degrade cleanly to `UNKNOWN`

#### 3. Narrow Elixir Interop As Escape Hatch
**Goal:** Unlock selected practical integrations without turning Axiom into a thin syntax layer over Elixir.

**Bounded scope:**
- Keep the first version intentionally narrow and explicitly under-typed
- Prefer small, explicit bridges or whitelisted calls over a fully generic open-ended FFI
- Treat it as an escape hatch, not the default path for core language capability

**Why third:** huge practical upside, but easy to overdo in ways that weaken the pressure to improve Axiom itself.

#### 4. Defer Mutable State
**Goal:** Avoid semantic and architectural churn until the concurrency direction is more settled.

**Current stance:**
- Do not prioritize implicit rebinding (`SETLET`-style outer-scope mutation)
- Do not prioritize shared `REF` cells ahead of the typed-concurrency design
- If state-threading ergonomics become necessary later, prefer explicit structured state-passing relief over true shared mutation

**Why last:** highest semantic risk, most likely to conflict with the actor-first model, and easiest to regret if introduced too early.

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
