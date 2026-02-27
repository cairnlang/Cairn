# PROVE

`PROVE` is Axiom's compile-time contract proof feature. It symbolically executes a function's `PRE`, body, and `POST`, generates SMT constraints, and asks Z3 whether the contract can be violated.

This document intentionally carries the solver-specific detail so the main README can stay focused on the language as a whole.

## What It Does

`PROVE function_name` checks whether `POST` holds for all inputs satisfying `PRE`.

- If Z3 returns `unsat`, the contract is proven.
- If Z3 returns `sat`, Axiom reports a counterexample.
- If the proof surface uses unsupported features (for example reachable lists, maps, or loops), Axiom returns `UNKNOWN` with a targeted hint.

Unlike `VERIFY`, which is probabilistic, `PROVE` is exhaustive over the supported proof surface.

## Example

```ax
DEF deposit : int int -> int
  PRE { OVER 0 GTE SWAP 0 GT AND }
  ADD
  POST DUP 0 GTE
END

PROVE deposit
# => PROVE deposit: PROVEN — POST holds for all inputs satisfying PRE
```

When a contract is false, Axiom reports a counterexample:

```ax
DEF withdraw_buggy : int int -> int
  PRE { DUP 0 GT }           # Bug: doesn't check balance >= amount
  SUB
  POST DUP 0 GTE
END

PROVE withdraw_buggy
# => PROVE withdraw_buggy: DISPROVEN
#      counterexample: p0 = 1, p1 = 0
```

For ADT parameters, counterexamples are decoded in constructor form (for example `Circle(-1)` instead of raw internal fields).

## Supported Surface

Today `PROVE` supports:

- integer arithmetic: `ADD`, `SUB`, `MUL`, `DIV`, `MOD`, `NEG`, `SQ`, `ABS`, `MIN`, `MAX`
- comparisons and boolean logic
- stack manipulation
- `IF/ELSE`
- function calls, inlined during symbolic execution (up to depth 10)
- `MATCH` on `option`, `result`, and generic non-recursive int-field user ADTs

The `MATCH` support includes PRE-driven branch pruning, constructor-shaped counterexamples, and a large amount of normalization and inference work to keep equivalent constraints stable across noisy input shapes.

## Trace Diagnostics

Set `AXIOM_PROVE_TRACE` to inspect proof behavior:

- `summary`
- `verbose`
- `json`

Examples:

```bash
AXIOM_PROVE_TRACE=summary mix axiom.run examples/prove/proven_shape_trace.ax
AXIOM_PROVE_TRACE=verbose mix axiom.run examples/prove/proven_shape_trace.ax
AXIOM_PROVE_TRACE=json mix axiom.run examples/prove/proven_shape_trace.ax
AXIOM_PROVE_TRACE=json mix axiom.run examples/prove/proven_shape_trace_rewrites.ax
```

`json` mode emits structured stderr events including:

- `prove_run_start` / `prove_run_end`
- `pre_executed` / `body_executed` / `post_executed` / `z3_query`
- `match_decision`
- `rewrite_applied`

## Solver Model

At a high level:

1. Symbolically execute `PRE`, body, and `POST`
2. Build SMT constraints for `PRE ∧ NOT(POST)`
3. Emit SMT-LIB v2
4. Query Z3
5. Decode either proof success, a model-backed counterexample, or a bounded `UNKNOWN`

`IF/ELSE` branches are encoded as SMT `ite` nodes. Function calls are inlined during symbolic execution so helper-based proofs remain compositional within the supported depth limit.

## Examples

Curated proof examples live under `examples/prove/`.

Start with:

- `examples/prove/all_proven.ax`
- `examples/prove/proven_option.ax`
- `examples/prove/proven_shape_trace.ax`

The more specialized PRE-normalization and trace examples are also kept there, but they are intentionally secondary to the main language docs.
