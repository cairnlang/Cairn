# Explicit Parametric Polymorphism Plan

This is the working plan for adding explicit parametric polymorphism to Cairn.

## Goal

Add explicit generic functions so reusable helpers can preserve real types instead
of degrading to `any`.

The first version should improve:

- collections
- prelude helpers
- reusable libraries
- larger app support code

without trying to become full Hindley-Milner.

## Scope For v0.9.2a

The first slice should support:

1. explicit function type parameters
2. type variables in function signatures
3. call-site instantiation from actual stack types

It should explicitly defer:

- generic `TYPE` declarations
- global type inference
- typeclasses
- higher-kinded types
- explicit type application syntax

## Proposed Syntax

```crn
DEF id[T] : T -> T
  DUP DROP
END
```

and:

```crn
DEF swap[T U] : T U -> U T
  ...
END
```

## Implementation Order

1. Add `type_params` to `Cairn.Types.Function`
2. Extend the parser so `DEF name[T U]` is accepted
3. Add a type form for variables, e.g. `{:type_var, "T"}`
4. Validate that signature type variables are declared by the function
5. Extend unification so generic calls instantiate type variables from the
   actual stack types
6. Add focused parser/checker tests
7. Add one small generic example
8. Then improve one or two real helpers that currently fall back to `any`

## Expected Payoff

The biggest immediate wins should be:

- stronger collection helper typing
- fewer `any` holes in reusable helpers
- cleaner prelude APIs
- a better foundation for future refinement or bounded liquid-type work

## Current Status

Step 1 is now started:

- `Cairn.Types.Function` carries a `type_params` field
- the parser currently initializes it as an empty list until generic syntax is
  added
