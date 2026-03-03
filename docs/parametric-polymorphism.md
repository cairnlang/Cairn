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

Steps 1 and 2 are now in place:

- `Cairn.Types.Function` carries a `type_params` field
- the parser accepts `DEF name[T U]`
- function definitions now record declared type parameters

What is still missing:

- broader generic coverage in real helpers

Step 3 is now in place:

- signatures can use declared type variables like `T`
- those type variables are represented explicitly in parsed types
- the checker validates that every type variable used in a signature is declared
  by the function

Step 4 is now in place:

- generic functions instantiate from the actual stack types at the call site
- simple generic examples like `id[T] : T -> T` now type-check and run

Step 5 has begun:

- the first real helper migration is in place
- `map_get_or` now has a real generic signature:
  - `DEF map_get_or[T] : T map[str T] str -> T`
- the public generics example now demonstrates that practical payoff directly
