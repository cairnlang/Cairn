# PROVE Rule Admission (v0.6.0ad Freeze)

This document defines the admission checklist for any new PROVE inference or PRE-normalization rewrite rule after the tactical freeze.

## Scope

- Applies to `Cairn.Solver.PreNormalize` rewrite rules and helper-pattern extraction logic used by PROVE narrowing.
- During `v0.6.0ad+`, PRE normalization is **bugfix/refactor-only by default**.

## Admission Checklist

A new rule may be added only when all items below are satisfied:

1. Problem shape: Provide the concrete normalized constraint shape that currently fails or degrades proof quality.
2. Formal rule: State the rewrite/inference transformation explicitly (before -> after) and required preconditions.
3. Soundness note: Explain why the transformation preserves meaning for the supported subset.
4. Evidence breadth: Demonstrate value on at least **two** independent scenarios (tests/examples), not one synthetic case.
5. Regression coverage: Add/adjust tests for:
   - positive case
   - non-applicable/negative case
   - no behavioral regression in existing proof bundles
6. Performance impact: Report before/after runtime for `examples/prove/all_proven.crn`; reject changes that cause significant slowdown without clear value.
7. Trace compatibility: If metadata/events change, update trace schema tests and docs.

## Change Discipline

- Prefer improving diagnostics or assumption extraction over adding broad new canonicalization tactics.
- Keep rewrites bounded and local; avoid global expression growth.
- Update the frozen rewrite-rule catalog in `Cairn.Solver.PreNormalize.rewrite_rule_catalog/0` only with explicit roadmap/docs justification.
