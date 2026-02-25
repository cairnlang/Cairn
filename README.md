# Axiom

An AI-native programming language targeting the BEAM.

Stack-based, postfix, contract-checked. Designed around the idea that an AI-first language should optimize for **reasoning correctness** over human readability — with declarative constraints, content-addressed structure, and the BEAM's actor model as the foundation for multi-agent collaboration.

**v0.3.0**: Interpreted postfix core with a **static type checker**, **algebraic data types** (TYPE/MATCH), **property-based verification** (VERIFY), **compile-time proof** (PROVE via Z3), runtime contracts (PRE/POST), **maps**, closures, loops, and a REPL.

## Quick Start

```bash
# Run a file
mix axiom.run examples/collatz.ax

# Algebraic data types + pattern matching
mix axiom.run examples/option.ax

# Verify contracts with random testing + compile-time proof
mix axiom.run examples/bank.ax

# Start the REPL
mix run -e "Axiom.REPL.start()"

# Run tests (464 tests)
mix test
```

## Language Reference

### Literals

```
42                          # int
3.14                        # float
T F                         # bool
"hello world"               # string
[ 1 2 3 ]                   # list
M[ "a" 1 "b" 2 ]           # map (key-value pairs)
M[]                         # empty map
{ DUP ADD }                 # block (closure)
```

### Types

Functions declare parameter and return types. The type checker enforces these statically before any code runs.

```
int float bool str    # concrete types
[int] [str]           # list types
map[str int]          # map types (key type, value type)
any                   # accepts any type
void                  # function returns nothing
option result         # user-defined algebraic types (see TYPE below)
```

Multi-return functions are supported:

```
DEF divmod : int int -> int int
  DUP ROT SWAP MOD SWAP ROT DIV SWAP
END
```

### Operators

```
# Arithmetic (binary: pop 2, push 1)
ADD SUB MUL DIV MOD MIN MAX

# Arithmetic (unary: pop 1, push 1)
SQ ABS NEG

# Comparison (pop 2, push bool)
EQ NEQ GT LT GTE LTE

# Logic
AND OR NOT

# Stack manipulation
DUP DROP SWAP OVER ROT

# List operations
SUM LEN HEAD TAIL CONS CONCAT SORT REVERSE RANGE

# Higher-order (take a block and a list)
FILTER MAP REDUCE

# Iteration
TIMES WHILE

# Blocks
APPLY                          # execute a block from the stack

# Map operations
GET                            # pop key, pop map, push value
PUT                            # pop value, pop key, pop map, push updated map
DEL                            # pop key, pop map, push map without key
HAS                            # pop key, pop map, push bool
KEYS                           # pop map, push list of keys
VALUES                         # pop map, push list of values
MLEN                           # pop map, push size
MERGE                          # pop map2, pop map1, push merged (map2 wins)

# String operations
CONCAT                         # concatenate two strings (or two lists)
WORDS                          # split string into words (on whitespace)
LINES                          # split string into lines
CONTAINS                       # check if string contains substring
LEN                            # also works on strings (character count)

# I/O
PRINT                          # non-destructive debug output (with label)
SAY                            # non-destructive clean output (IO.puts)
ARGV                           # push command-line args as a list of strings
READ_FILE                      # pop filename, push file contents
WRITE_FILE                     # pop contents and filename, write to file
READ_LINE                      # read one line from stdin
```

### Control Flow

```
# Conditional
T IF 42 END                     # pushes 42
F IF 1 ELSE 2 END              # pushes 2

# Repeat N times
1 10 { DUP ADD } TIMES         # 1 doubled 10 times = 1024

# Loop while condition is true
1 { DUP 100 LT } { DUP ADD } WHILE   # first power of 2 >= 100 = 128
```

### Algebraic Data Types

`TYPE` declares a sum type (tagged union) with named constructors and typed fields. Constructors start with an uppercase letter. Field types follow the constructor name.

```
TYPE option = None | Some int
TYPE result = Ok int | Err str
TYPE shape  = Circle float | Rect float float | Point
```

Constructors are called like stack words — they pop their fields and push a tagged value:

```
42 Some        # pushes Some(42) — pops 42, constructs variant
None           # pushes None — no fields
"oops" Err     # pushes Err("oops")
```

**Stack convention**: `param_types[0]` is the TOP of stack. To call a function that takes `option int`, push the `int` default first, then the `option` last:

```
0 42 Some unwrap_or    # stack before call: [Some(42), 0] (option on top)
```

### MATCH — Pattern Dispatch

`MATCH` pops a variant from the top of the stack and dispatches to the matching arm. Each arm starts with the constructor name followed by a block `{ }`. Fields are pushed onto the stack before the arm body runs.

```
42 Some
MATCH
  None { 0 }           # None: no fields, leave 0 on stack
  Some { 1 ADD }       # Some(x): x is on top, compute x + 1
END
# => [43]
```

The static checker verifies exhaustiveness — every constructor must have a matching arm:

```
42 Some
MATCH
  Some { }             # STATIC ERROR: MATCH is not exhaustive: missing None
END
```

Using algebraic types in function signatures:

```
TYPE option = None | Some int

DEF unwrap_or : option int -> int
  # option is top of stack, int (default) is below
  MATCH
    None { }           # leave default on stack
    Some { SWAP DROP } # field is on top, swap and drop default
  END
END

0 42 Some unwrap_or    # => 42
99 None   unwrap_or    # => 99
```

### Functions and Contracts

```
# Define a function with a type signature
DEF double : int -> int
  DUP ADD
END

5 double    # [10]

# PRE contracts — checked before the body runs
# POST contracts — checked after the body runs
DEF factorial : int -> int
  PRE { DUP 0 GTE }
  RANGE 1 { MUL } REDUCE
  POST DUP 0 GT
END

# Violating a contract raises Axiom.ContractError
# Type mismatches are caught statically before execution
"hello" double    # => STATIC ERROR: expected int, got str
```

### VERIFY — Property-Based Testing

`VERIFY` auto-generates random inputs, filters by PRE conditions, runs the function, and checks POST holds. Powered by StreamData.

```
DEF withdraw : int int -> int
  PRE { OVER OVER GTE SWAP 0 GT AND }
  SUB
  POST DUP 0 GTE
END

VERIFY withdraw 500
# => VERIFY withdraw: OK — 500 tests passed (1702 skipped by PRE)
```

When VERIFY finds a counterexample, it reports exactly which inputs broke the contract:

```
DEF withdraw_buggy : int int -> int
  PRE { DUP 0 GT }           # Bug: doesn't check balance >= amount
  SUB
  POST DUP 0 GTE
END

VERIFY withdraw_buggy 100
# => VERIFY withdraw_buggy: FAILED after 2 tests
#      counterexample: 601 (int), 598 (int)
#      error: CONTRACT: POST condition failed for withdraw_buggy
```

### PROVE — Compile-Time Verification via Z3

`PROVE` mathematically proves that a function's POST condition holds for **all** inputs satisfying PRE. Unlike VERIFY (probabilistic), PROVE gives certainty by symbolically executing the function and querying the Z3 SMT solver. Requires `z3` on PATH.

```
DEF deposit : int int -> int
  PRE { OVER 0 GTE SWAP 0 GT AND }
  ADD
  POST DUP 0 GTE
END

PROVE deposit
# => PROVE deposit: PROVEN — POST holds for all inputs satisfying PRE
```

When PROVE finds that a contract can be violated, it reports a counterexample:

```
DEF withdraw_buggy : int int -> int
  PRE { DUP 0 GT }           # Bug: doesn't check balance >= amount
  SUB
  POST DUP 0 GTE
END

PROVE withdraw_buggy
# => PROVE withdraw_buggy: DISPROVEN
#      counterexample: p0 = 1, p1 = 0
```

PROVE supports integer arithmetic (ADD, SUB, MUL, DIV, MOD, NEG, SQ), all comparisons, logic ops, and stack manipulation. For functions using lists, maps, loops, or IF/ELSE, PROVE returns UNKNOWN and suggests using VERIFY instead.

### Higher-Order Operations

```
# FILTER — keep elements where block returns true
[ 1 2 3 4 5 ] { 2 MOD 1 EQ } FILTER     # [1, 3, 5]

# MAP — apply block to each element
[ 1 2 3 ] { SQ } MAP                      # [1, 4, 9]

# REDUCE — fold a list with an accumulator
[ 1 2 3 4 5 ] 0 { ADD } REDUCE            # 15
[ 1 2 3 4 5 ] 1 { MUL } REDUCE            # 120 (factorial)

# APPLY — execute a block from the stack
5 { DUP ADD } APPLY                        # 10

# RANGE — generate [1..N]
5 RANGE                                    # [1, 2, 3, 4, 5]
```

### Comments

```
# This is a comment
42 # inline comment
"hello # world"    # hash inside strings is preserved
```

### File I/O and Arguments

```
# Read command-line arguments
ARGV HEAD SAY DROP             # print the first argument

# cat — print a file's contents
ARGV HEAD READ_FILE SAY DROP
# Usage: mix axiom.run examples/cat.ax somefile.txt

# Write to a file
"hello" "out.txt" WRITE_FILE

# Read a line from stdin
READ_LINE SAY DROP
```

## Examples

### Option and Result Types

Safe value handling without runtime exceptions (`examples/option.ax`):

```
TYPE option = None | Some int
TYPE result = Ok int | Err str

DEF unwrap_or : option int -> int
  MATCH
    None { }
    Some { SWAP DROP }
  END
END

DEF safe_div : int int -> result
  DUP 0 EQ
  IF
    DROP DROP "division by zero" Err
  ELSE
    DIV Ok
  END
END

0 42 Some unwrap_or    # => 42  (Some unwrapped)
99 None   unwrap_or    # => 99  (default returned)

10 2 safe_div          # => Ok(5)
10 0 safe_div          # => Err("division by zero")
```

### The Safe Bank

Property-tested financial operations (Milestone 2 from the roadmap):

```
DEF deposit : int int -> int
  PRE { OVER 0 GTE SWAP 0 GT AND }
  ADD
  POST DUP 0 GTE
END

DEF withdraw : int int -> int
  PRE { OVER OVER GTE SWAP 0 GT AND }
  SUB
  POST DUP 0 GTE
END

VERIFY deposit 500
VERIFY withdraw 500

PROVE deposit       # mathematically proven for ALL inputs
PROVE withdraw

1000 200 deposit    # => 1200
1000 300 withdraw   # => 700
```

### Collatz Sequence

```
DEF step : int -> int
  DUP 2 MOD 0 EQ
  IF 2 DIV
  ELSE 3 MUL 1 ADD
  END
  POST DUP 0 GT
END

27 { DUP 1 GT } { step } WHILE    # => 1
```

### Factorial

```
DEF factorial : int -> int
  PRE { DUP 0 GTE }
  RANGE 1 { MUL } REDUCE
  POST DUP 0 GT
END

10 factorial    # => 3628800
```

### Fibonacci

```
0 1 20 { SWAP OVER ADD } TIMES SWAP DROP    # => 10946
```

### GCD (Euclidean Algorithm)

```
DEF gcd : int int -> int
  { DUP 0 NEQ }
  { SWAP OVER MOD }
  WHILE
  DROP
END

48 18 gcd    # => 6
```

### Sum of Squared Odds

```
DEF sum_sq_odds : [int] -> int
  { 2 MOD 1 EQ } FILTER
  { SQ } MAP
  SUM
  POST DUP 0 GTE
END

[ 1 2 3 4 5 ] sum_sq_odds    # => 35
```

### Statistics

```
DEF mean : [int] -> int
  DUP SUM SWAP LEN DIV
END

DEF sum_of_squares : [int] -> int
  0 { SQ ADD } REDUCE
  POST DUP 0 GTE
END

DEF median : [int] -> int
  SORT DUP LEN 2 DIV
  { TAIL } TIMES
  HEAD
END

[ 10 4 7 2 9 1 8 3 6 5 ]
DUP mean SAY DROP               # => 5
DUP sum_of_squares SAY DROP     # => 385
median SAY DROP                 # => 6
```

### Word Frequency Counter

Uses maps to count word occurrences in a file:

```
DEF inc_word : str map[str int] -> map[str int]
  OVER OVER HAS
  IF
    OVER OVER GET 1 ADD PUT
  ELSE
    1 PUT
  END
END

ARGV HEAD READ_FILE WORDS
M[] { inc_word } REDUCE
SAY DROP
```

```bash
mix axiom.run examples/freq.ax somefile.txt
# => %{"apple" => 2, "banana" => 1, "grape" => 1, ...}
```

### Cat / Word Count / Grep

```bash
mix axiom.run examples/cat.ax somefile.txt
mix axiom.run examples/wc.ax somefile.txt
mix axiom.run examples/grep.ax somefile.txt
mix axiom.run examples/freq.ax somefile.txt
```

## Architecture

```
 source.ax
    │
    ▼
 Lexer ──→ tokens ──→ Parser ──→ functions + expressions + verify/prove items
                                        │
                                        ▼
                                  Static Type Checker
                                  (symbolic stack, type unification)
                                        │
                                        ▼
                                  Evaluator (stack-based interpreter)
                                        │
                                  ┌─────┼──────────┐
                                  │     │          │
                            Axiom.Runtime  │    Axiom.Solver
                            (operators)    │    (symbolic exec → SMT-LIB → Z3
                                  │        │     compile-time PROVE)
                            Contract    Axiom.Verify
                            checker     (property-based testing
                            (PRE/POST)   via StreamData)
                                  │
                               result
```

### Static Type Checker

The checker runs **before evaluation**, walking token streams with a symbolic stack (types instead of values). It catches:

- Type mismatches (`"hello" 3 ADD` blocked at check time)
- Stack underflow (`ADD` on empty stack)
- IF/ELSE branch shape mismatches (different depths or types)
- Non-bool IF conditions
- Function argument type mismatches at call sites
- Return type/arity mismatches in function bodies
- Undefined function calls
- Unknown constructors
- Non-exhaustive MATCH arms (missing constructors)
- MATCH on non-variant values

Errors are reported with position information and the checker continues after errors to report multiple issues in one pass.

### VERIFY Engine

`VERIFY function_name N` generates N random inputs using StreamData, filters by PRE condition, executes the function, and checks POST holds. When a counterexample is found, it reports the exact inputs that broke the contract.

### PROVE Solver

`PROVE function_name` symbolically executes the function's PRE, body, and POST to build constraint formulas, generates an SMT-LIB v2 script asserting `PRE ∧ ¬POST`, and queries Z3. If Z3 returns `unsat`, the contract is mathematically proven. If `sat`, the model is parsed into a counterexample. Functions with unsupported operations (lists, maps, loops, IF/ELSE) gracefully return UNKNOWN.

The content-addressed DAG (ETS-backed) is in place for future use in multi-agent workflows and compilation to BEAM bytecode.

## Roadmap

- **v0.0.1** (complete): Interpreter, PRE/POST contracts, REPL, TIMES/WHILE, FILTER/MAP/REDUCE, strings, I/O
- **v0.1.0** (complete): Static type checker, VERIFY (property-based contract testing), maps, Safe Bank milestone
- **v0.2.0** (complete): PROVE — compile-time contract verification via Z3 SMT solver
- **v0.3.0** (current): Algebraic data types (TYPE/MATCH) — Option, Result, and user-defined sum types with exhaustiveness checking
- **Next**: Typed BEAM concurrency (typed message passing, stateful actors), JSON parser built on sum types
- **Future**: Tensor/distribution primitives, multi-agent collaboration, BEAM bytecode compilation

## Requirements

- Elixir >= 1.12
- Erlang/OTP >= 24
- Z3 SMT solver (optional, required for `PROVE` — [install](https://github.com/Z3Prover/z3))
