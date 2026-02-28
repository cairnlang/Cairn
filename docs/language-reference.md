# Language Reference

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
option result         # `option` user-defined; `result` is built-in (Ok/Err)
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

# Explicit float math
PI E                          # push float constants
SIN COS FLOOR CEIL ROUND      # unary: pop 1 float, push 1 float
EXP LOG SQRT                  # unary: pop 1 float, push 1 float
POW                           # binary: pop exponent + base (floats), push float

# Narrow host interop (v1)
HOST_CALL helper              # expects a literal arg list immediately before it, e.g. [ 42 ] HOST_CALL int_to_string

# Comparison (pop 2, push bool)
EQ NEQ GT LT GTE LTE

# Logic
AND OR NOT

# Stack manipulation
DUP DROP SWAP OVER ROT ROT4

# List operations
SUM LEN HEAD TAIL CONS CONCAT SORT REVERSE RANGE ZIP ENUMERATE TAKE

# Higher-order (take a block and a list)
FILTER MAP FLAT_MAP FIND GROUP_BY REDUCE

# Iteration
TIMES REPEAT WHILE

# Blocks
APPLY                          # execute a block from the stack
WITH_STATE                     # pop initial state + block, run local state thread, push final state
STATE                          # push current WITH_STATE value inside a WITH_STATE block
SET_STATE                      # replace current WITH_STATE value inside a WITH_STATE block
STEP fn                        # inside WITH_STATE, apply a state -> state helper and store the result

# Map operations
GET                            # pop key, pop map, push value
PUT                            # pop value, pop key, pop map, push updated map
DEL                            # pop key, pop map, push map without key
HAS                            # pop key, pop map, push bool
KEYS                           # pop map, push list of keys
VALUES                         # pop map, push list of values
MLEN                           # pop map, push size
MERGE                          # pop map2, pop map1, push merged (map2 wins)
PAIRS                          # pop map, push list of [key, value] pairs
NUM_STR                        # pop number (int or float), push string

# String operations
CONCAT                         # concatenate two strings (or two lists)
WORDS                          # split string into words (on whitespace)
LINES                          # split string into lines
CONTAINS                       # check if string contains substring
LEN                            # also works on strings (character count)
CHARS                          # split string into list of single characters
SPLIT                          # pop delimiter, pop string, push split list
TRIM                           # remove leading/trailing whitespace
LOWER UPPER                    # case normalization helpers
STARTS_WITH                    # pop prefix, pop string, push bool
ENDS_WITH                      # pop suffix, pop string, push bool
REPLACE                        # pop replacement, pop pattern, pop string, push replaced string
REVERSE_STR                    # reverse a string
SLICE                          # pop len, pop start, pop string, push substring
TO_INT                         # parse string as integer -> result (Ok int | Err str)
TO_FLOAT                       # parse string as float -> result (Ok float | Err str)
TO_INT! TO_FLOAT!              # unsafe parse variants (raise on failure)
JOIN                           # pop separator, pop list of strings, push joined
FMT                            # pop format string, pop values for {} placeholders, push result

# I/O
PRINT                          # non-destructive debug output (with label)
SAY                            # non-destructive clean output (IO.puts)
SAID                           # destructive SAY — prints value then drops it
ASK                            # pop prompt, read line, push result (Ok str | Err str)
ASK!                           # unsafe ASK (raises on closed input)
ARGV                           # push command-line args as a list of strings
READ_FILE                      # pop filename, push result (Ok str | Err str)
WRITE_FILE                     # pop contents + filename, push result (Ok any | Err str)
READ_FILE! WRITE_FILE!         # unsafe file ops (raise on failure)
HTTP_SERVE                     # pop port + handler block (or bind addr + port + handler), serve requests until stopped
READ_LINE                      # read one line from stdin
RANDOM                         # pop N, push random integer in [1, N]
```

### LET Bindings

`LET` names a value for readability. It pops the top of the stack and binds it to a name. The binding is scoped to the enclosing function body (or top-level expression). Rebinding the same name shadows the previous value.

```
42 LET x                        # pops 42, binds x
x x ADD                         # pushes 42 twice, adds => 84

# Multiple bindings and intermediate results
10 LET base
base base MUL LET squared       # squared = 100
squared base ADD                # => 110

# Inside functions
DEF add_ten : int -> int
  10 LET n
  n ADD
END
```

**Note**: LET bindings inside blocks (`{ }`) are scoped to that block execution. In WHILE loops, prefer using the stack to carry state between iterations.

### String Formatting (FMT)

`FMT` pops a format string and one value per `{}` placeholder, auto-converts each value to a string, and pushes the result. Use `{{` and `}}` for literal braces.

```
42 "Score: {}!" FMT                           # => "Score: 42!"
42 "Alice" "Name: {}, Age: {}" FMT            # => "Name: Alice, Age: 42"
"use {{}} for placeholders" FMT               # => "use {} for placeholders"
```

Values are auto-converted: integers and floats become their string representation, booleans become `"T"` / `"F"`, and everything else uses `inspect`.

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

### Recursion

A function can call itself by name. The base case is handled with `IF/ELSE`:

```
DEF fact : int -> int
  DUP 0 EQ
  IF DROP 1
  ELSE DUP 1 SUB fact MUL
  END
END

5 fact    # => 120
```

All previously defined functions are in scope inside a function body, including the function itself.

### Algebraic Data Types

`TYPE` declares a sum type (tagged union) with named constructors and typed fields. Constructors start with an uppercase letter. Field types follow the constructor name.

```
TYPE option = None | Some int
TYPE shape  = Circle float | Rect float float | Point
```

Constructors are called like stack words — they pop their fields and push a tagged value:

```
42 Some        # pushes Some(42) — pops 42, constructs variant
None           # pushes None — no fields
"oops" Err     # pushes Err("oops")
```

`result` is built in as `TYPE result = Ok any | Err str`.

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

Use `_` as a **wildcard catch-all** to match any remaining constructors. The wildcard discards all fields — the body starts with a clean stack:

```
TYPE json = JNull | JBool bool | JNum float | JStr str | JArr [json] | JObj map[str json]

DEF jstr_val : json -> str
  MATCH
    JStr { }           # JStr field (the string) is on the stack
    _    { "" }        # all other variants: discard fields, push ""
  END
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

# Violating a contract raises Cairn.ContractError
# Type mismatches are caught statically before execution
"hello" double    # => STATIC ERROR: expected int, got str
```

### VERIFY — Property-Based Testing

`VERIFY` auto-generates random inputs, filters by PRE conditions, runs the function, and checks POST holds. Powered by StreamData. Supports practical scalar and collection shapes (`int`, `float`, `bool`, `str`, `[T]`, `map[K V]`) plus user-defined sum types — recursive types use depth-limited generation to avoid infinite expansion. String/list generation is intentionally bounded so helper-style text functions stay practical to fuzz.

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

`PROVE` mathematically proves that a function's POST condition holds for **all** inputs satisfying PRE. Unlike VERIFY (probabilistic), PROVE gives certainty by symbolically executing the function and querying Z3. Requires `z3` on PATH.

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

For ADT params, counterexamples are now decoded in constructor form (see `examples/prove/proven_shape_buggy.crn`), e.g. `p0 = Circle(-1)`.
To print MATCH pruning diagnostics, run with `CAIRN_PROVE_TRACE=summary`, `CAIRN_PROVE_TRACE=verbose`, or `CAIRN_PROVE_TRACE=json` (trace goes to stderr; see `examples/prove/proven_shape_trace.crn`).

For the full proof surface, trace modes, and solver details, see [`prove.md`](prove.md).

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
ARGV HEAD SAID             # print the first argument

# cat — print a file's contents
ARGV HEAD READ_FILE! SAID
# Usage: mix cairn.run examples/cat.crn somefile.txt

# Write to a file
"hello" "out.txt" WRITE_FILE!

# Read a line from stdin
READ_LINE SAID

# Serve two static pages on localhost until stopped
"examples/web/lib/hello_static.crn" IMPORT
"127.0.0.1" 8089 {
  handle_static_request
} HTTP_SERVE

# The route helpers can also be used directly (with the path on top):
"/about"
DUP "/" "<p>Home</p>" route_text_ok
SWAP "/about" "<p>About</p>" route_text_ok
route_or
route_finish

# HTTP_SERVE handlers now receive method and path (path on top):
LET path
LET method
method "GET" EQ
```

## Examples

### Option and Result Types

Safe value handling without runtime exceptions (`examples/option.crn`):

```
TYPE option = None | Some int

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

### Recursive Functions

A minimal example of mutual self-recursion (`examples/recur.crn`):

```
DEF fact : int -> int
  DUP 0 EQ
  IF DROP 1
  ELSE DUP 1 SUB fact MUL
  END
END

DEF fib : int -> int
  DUP 1 LTE
  IF
  ELSE DUP 1 SUB fib SWAP 2 SUB fib ADD
  END
END

5 fact SAID    # => 120
10 fib SAID    # => 55
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
DUP mean SAID               # => 5
DUP sum_of_squares SAID     # => 385
median SAID                 # => 6
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

ARGV HEAD READ_FILE! WORDS
M[] { inc_word } REDUCE
SAID
```

```bash
mix cairn.run examples/freq.crn somefile.txt
# => %{"apple" => 2, "banana" => 1, "grape" => 1, ...}
```

### JSON Parser and Encoder

A complete JSON parser and encoder written entirely in Cairn (`examples/json/core.crn` + `examples/json/demo.crn`), demonstrating recursive sum types, character-level string processing, and the wildcard MATCH pattern:

```
TYPE json = JNull | JBool bool | JNum float | JStr str | JArr [json] | JObj map[str json]

# Parse any JSON value from a character list
DEF parse_value : [str] -> [str] json
  skip_ws DUP HEAD
  DUP "n" EQ IF DROP parse_null
  ELSE DUP "t" EQ IF DROP parse_bool
  ELSE DUP "f" EQ IF DROP parse_bool
  ELSE DUP "\"" EQ IF DROP parse_string
  ELSE DUP "[" EQ IF DROP parse_array
  ELSE DUP "{" EQ IF DROP parse_object
  ELSE DROP parse_number
  END END END END END END
END

# Encode any JSON value back to a string
DEF encode : json -> str
  MATCH
  JNull { "null" }
  JBool { IF "true" ELSE "false" END }
  JNum  { NUM_STR }
  JStr  { encode_str }
  JArr  { { encode } MAP "," JOIN "[" SWAP CONCAT "]" CONCAT }
  JObj  { PAIRS { encode_pair } MAP "," JOIN "{" SWAP CONCAT "}" CONCAT }
  END
END

# Practical: extract full names from a JSON array of person objects
DEF full_name : json -> str
  MATCH
  JObj { DUP "last" GET jstr_val SWAP "first" GET jstr_val " " CONCAT SWAP CONCAT }
  _    { "" }
  END
END
```

```bash
mix cairn.run examples/json/demo.crn
# Parses and prints JSON values, extracts names, round-trips through encode

# Compatibility entrypoint (same output)
mix cairn.run examples/json.crn
```

### Number Guessing Game

An interactive game using LET, ASK!, and RANDOM (`examples/guess.crn`):

```
100 RANDOM LET secret
"I'm thinking of a number between 1 and 100." SAID

# Stack carries: tries_count
0

{
  "Your guess? " ASK! TO_INT! LET guess
  1 ADD
  guess secret EQ IF
    DUP "Got it in {} tries!" FMT SAID
    F
  ELSE
    guess secret LT IF
      "Too low!" SAID
    ELSE
      "Too high!" SAID
    END
    T
  END
} { } WHILE
DROP
```

```bash
mix cairn.run examples/guess.crn
# I'm thinking of a number between 1 and 100.
# Your guess? 50
# Too high!
# Your guess? 25
# Too low!
# ...
# Got it in 7 tries!
```

### Cat / Word Count / Grep

```bash
mix cairn.run examples/cat.crn somefile.txt
mix cairn.run examples/wc.crn somefile.txt
mix cairn.run examples/grep.crn somefile.txt
mix cairn.run examples/freq.crn somefile.txt
```

## Architecture

```
 source.crn
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
                            Cairn.Runtime  │    Cairn.Solver
                            (operators)    │    (symbolic exec → SMT-LIB → Z3
                                  │        │     compile-time PROVE)
                            Contract    Cairn.Verify
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
- Non-exhaustive MATCH arms (missing constructors, unless `_` wildcard is present)
- MATCH on non-variant values

Errors are reported with position information and the checker continues after errors to report multiple issues in one pass.

### VERIFY Engine

`VERIFY function_name N` generates N random inputs using StreamData, filters by PRE condition, executes the function, and checks POST holds. When a counterexample is found, it reports the exact inputs that broke the contract. User-defined sum types are supported with depth-limited recursive generation (via `StreamData.tree`). Practical text/list helpers are now a first-class target too: string generation is bounded to small ASCII-ish values, and `[str]` generation is bounded to short lists so utility-style helpers (for example `mini_grep` parsing logic) can be fuzzed without blowing up test cost.

### PROVE Solver

The detailed solver pipeline, supported proof surface, and trace event formats are documented in [`prove.md`](prove.md).

The content-addressed DAG (ETS-backed) is in place for future use in multi-agent workflows and compilation to BEAM bytecode.
