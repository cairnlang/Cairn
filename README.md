# Axiom

An AI-native programming language targeting the BEAM.

Stack-based, postfix, contract-checked. Designed around the idea that an AI-first language should optimize for **reasoning correctness** over human readability — with declarative constraints, content-addressed structure, and the BEAM's actor model as the foundation for multi-agent collaboration.

**v0.7.0o**: Interpreted postfix core with **LET bindings**, a **static type checker**, **algebraic data types** (TYPE/MATCH with wildcard `_` catch-all), **contracts** (`PRE`/`POST`), **property-based verification** (`VERIFY`), and **compile-time proof** (`PROVE`) alongside practical file-backed workflows, typed-concurrency foundations on the BEAM (`pid[T]`, `SPAWN`, `SPAWN_LINK`, `SEND`, actor-local `RECEIVE`, `SELF`, `EXIT`, `MONITOR`/`AWAIT`, and bounded protocol-checked actors with helper-function conformance), reusable example libs, **maps**, closures, loops, string primitives, interactive I/O, `FMT`/`SAID`, recursive `IMPORT`, safe-by-default fallible operations via built-in `result`, and a modular auto-loaded prelude.

## Quick Start

```bash
# Run a file
mix axiom.run examples/collatz.ax

# CLI options + environment reference
mix axiom.run --help
mix axiom.run --examples

# Recursion (factorial + fibonacci)
mix axiom.run examples/recur.ax

# Algebraic data types + pattern matching
mix axiom.run examples/option.ax

# Verify contracts (randomized + solver-backed)
mix axiom.run examples/bank.ax

# Run the curated proof examples
mix axiom.run examples/prove/all_proven.ax

# Proof details, solver notes, and trace modes:
# see docs/prove.md

# JSON parser + encoder demo (modular IMPORT example)
mix axiom.run examples/json/demo.ax

# Minimal 2-file IMPORT demo
mix axiom.run examples/imports/main.ax

# Practical mini-app (imports + prelude + file I/O + VERIFY)
mix axiom.run examples/practical/all_practical.ax
mix axiom.run examples/practical/main.ax
mix axiom.run examples/practical/ledger.ax
mix axiom.run examples/practical/todo.ax
mix axiom.run examples/practical/ledger_cli.ax
mix axiom.run examples/practical/ledger_cli.ax examples/practical/data/ledger.csv
mix axiom.run examples/practical/expenses.ax
mix axiom.run examples/practical/expenses.ax examples/practical/data/expenses.csv
mix axiom.run examples/practical/cashflow.ax
mix axiom.run examples/practical/cashflow.ax examples/practical/data/ledger.csv examples/practical/data/expenses.csv
mix axiom.run examples/practical/cashflow_alerts.ax
mix axiom.run examples/practical/cashflow_alerts.ax examples/practical/data/ledger.csv examples/practical/data/expenses.csv

# Typed-concurrency examples (type-focused + minimal runtime)
mix axiom.run examples/concurrency/ping_pong_types.ax
mix axiom.run examples/concurrency/protocol_ping_pong.ax
mix axiom.run examples/concurrency/traffic_light_types.ax
mix axiom.run examples/concurrency/ping_once.ax
mix axiom.run examples/concurrency/self_boot.ax
mix axiom.run examples/concurrency/two_pings.ax
mix axiom.run examples/concurrency/counter.ax
mix axiom.run examples/concurrency/traffic_light.ax
mix axiom.run examples/concurrency/notifier.ax
mix axiom.run examples/concurrency/restart_once.ax
mix axiom.run examples/concurrency/supervisor_worker.ax

# Prelude helpers demo (safe result flow + string helpers)
mix axiom.run examples/prelude_demo.ax
mix axiom.run --show-prelude examples/prelude/result_flow.ax
mix axiom.run examples/prelude/csv_parse.ax
mix axiom.run examples/prelude/io_safe.ax

# Diagnostics examples (text + JSON)
mix axiom.run examples/diagnostics/static_type.ax
mix axiom.run examples/diagnostics/runtime_div_zero.ax
mix axiom.run examples/diagnostics/contract_fail.ax
mix axiom.run --json-errors examples/diagnostics/runtime_div_zero.ax

# Start the REPL
mix run -e "Axiom.REPL.start()"

# Interactive number guessing game
mix axiom.run examples/guess.ax

# Run tests (768 tests)
mix test

# Run practical-only pipeline tests
mix test.practical
```

### First 15 Minutes

```bash
# 1) Run a tiny program
mix axiom.run examples/hello_world.ax

# 2) See what to run next
mix axiom.run --examples

# 3) Trigger and read a static failure
mix axiom.run examples/diagnostics/static_type.ax

# 4) Inspect the same failure in JSON for tools/CI
mix axiom.run --json-errors examples/diagnostics/runtime_div_zero.ax

# 5) Run property-based and solver-backed checks
mix axiom.run examples/bank.ax
```

See [`docs/cli.md`](docs/cli.md) for CLI flags, env vars, and output format conventions.
See [`docs/prove.md`](docs/prove.md) for PROVE-specific details, solver behavior, and trace modes.
See [`docs/practical-pipeline.md`](docs/practical-pipeline.md) for the staged practical flow (`main -> ledger/todo -> expenses -> cashflow -> cashflow_alerts`).
`examples/collections.ax` is the focused collection-helper showcase for `ZIP`, `ENUMERATE`, `TAKE`, `FIND`, `FLAT_MAP`, and `GROUP_BY`.
`examples/math.ax` is the focused explicit-float math showcase for `PI`, `E`, `SIN`, `COS`, `FLOOR`, `CEIL`, `ROUND`, `EXP`, `POW`, `LOG`, and `SQRT`.
`examples/interop.ax` is the focused typed-whitelist host interop showcase for narrow `HOST_CALL` helpers such as `str_upcase`, `str_replace`, and `float_to_string`.
Concurrency examples live under `examples/concurrency/`; `ping_pong_types.ax`, `protocol_ping_pong.ax`, and `traffic_light_types.ax` stay type-focused, while `ping_once.ax`, `self_boot.ax`, `two_pings.ax`, `counter.ax`, `traffic_light.ax`, `notifier.ax`, `restart_once.ax`, `supervisor_worker.ax`, and `guess_binary.ax` exercise the current runtime actor path (`protocol_ping_pong.ax` is the first bounded protocol-conformance example and now demonstrates helper-function conformance inside protocol-bound actors, `counter.ax`, `traffic_light.ax`, and `guess_binary.ax` now use `WITH_STATE` plus `STEP`-driven bounded `REPEAT` loops to express actor-local state steps without manual unrolled `RECEIVE` chains, `notifier.ax` is the first more practical actor-shaped workflow, `restart_once.ax` is the first minimal supervision/restart workflow, and `supervisor_worker.ax` is the first explicit supervisor/worker split). Shared actor/state/supervision helpers now live under `examples/concurrency/lib/` (`lib/actor.ax`, `lib/state.ax`, `lib/supervision.ax`), and the supervision layer now exposes `watch_exit`, `await_exit`, and a reusable `restart_once` helper built on `block[T]` + `MONITOR`/`AWAIT`. Lifecycle-only examples like `examples/concurrency/linked_failure.ax` and `protocol_mismatch.ax` intentionally fail and are kept out of the normal runnable examples list.

### Practical Mini-Apps

`examples/practical/main.ax`, `examples/practical/ledger.ax`, `examples/practical/todo.ax`, `examples/practical/ledger_cli.ax`, `examples/practical/expenses.ax`, `examples/practical/cashflow.ax`, and `examples/practical/cashflow_alerts.ax` demonstrate practical, non-PROVE-centric workflows:
- imports reusable functions from `examples/practical/lib/stats.ax`
- reads CSV from disk with safe fallback (`read_file_or`)
- parses and computes totals/averages via prelude helpers
- runs `VERIFY score_total 40` as a lightweight regression check
- uses additional reusable libs (`examples/practical/lib/ledger.ax`, `examples/practical/lib/todo.ax`) for report/stat pipelines
- writes report outputs to `/tmp/axiom_*.txt` via `WRITE_FILE!` in ledger/todo flows
- includes report round-trip checks (write, read back, assert expected metrics)
- includes argv-driven file input (`ledger_cli.ax`) with default-path fallback
- includes a larger module-split app (`expenses.ax`) with parser/aggregator/report modules
- includes a composed cross-file app (`cashflow.ax`) combining ledger + expenses pipelines and shared report helpers
- includes a multi-step composed stage (`cashflow_alerts.ax`) that classifies risk bands and actions from composed metrics

### Imports

Use `IMPORT "path.ax"` at top level to load another file before evaluation:

```
# main.ax
IMPORT "lib/math.ax"
5 double
```

Imports are resolved relative to the importing file, loaded recursively, deduplicated, and cycles are reported as runtime errors.

See [`examples/imports/main.ax`](examples/imports/main.ax) and [`examples/imports/lib.ax`](examples/imports/lib.ax) for a minimal two-file example.

### Prelude

`mix axiom.run` / `Axiom.eval_file/3` auto-load `lib/prelude.ax` (disable with `AXIOM_NO_PRELUDE=1`).
Use `mix axiom.run --show-prelude your_file.ax` (or `--verbose`) to print loaded prelude modules/functions.
Prelude modules currently loaded by the facade:

- `result_is_ok`, `result_is_err`
- `result_unwrap_or`
- `lines_nonempty`, `csv_ints`
- `to_int_or`, `to_float_or`, `read_file_or`, `ask_or`

### Diagnostics

`mix axiom.run` now emits consistent failure diagnostics on stderr:
- `ERROR kind=<static|runtime|contract>`
- `message`, optional `location` + source `snippet`, and `hint`
- Run summary remains on stderr (`RUN SUMMARY: ...`)

Use `--json-errors` for machine-readable diagnostics:

```bash
mix axiom.run --json-errors examples/diagnostics/runtime_div_zero.ax
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
HOST_CALL helper              # expects a literal arg list immediately before it, e.g. [ "hi" ] HOST_CALL str_upcase

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
STARTS_WITH                    # pop prefix, pop string, push bool
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

# Violating a contract raises Axiom.ContractError
# Type mismatches are caught statically before execution
"hello" double    # => STATIC ERROR: expected int, got str
```

### VERIFY — Property-Based Testing

`VERIFY` auto-generates random inputs, filters by PRE conditions, runs the function, and checks POST holds. Powered by StreamData. Supports all types including user-defined sum types — recursive types use depth-limited generation to avoid infinite expansion.

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

For ADT params, counterexamples are now decoded in constructor form (see `examples/prove/proven_shape_buggy.ax`), e.g. `p0 = Circle(-1)`.
To print MATCH pruning diagnostics, run with `AXIOM_PROVE_TRACE=summary`, `AXIOM_PROVE_TRACE=verbose`, or `AXIOM_PROVE_TRACE=json` (trace goes to stderr; see `examples/prove/proven_shape_trace.ax`).

For the full proof surface, trace modes, and solver details, see [`docs/prove.md`](docs/prove.md).

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
# Usage: mix axiom.run examples/cat.ax somefile.txt

# Write to a file
"hello" "out.txt" WRITE_FILE!

# Read a line from stdin
READ_LINE SAID
```

## Examples

### Option and Result Types

Safe value handling without runtime exceptions (`examples/option.ax`):

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

A minimal example of mutual self-recursion (`examples/recur.ax`):

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
mix axiom.run examples/freq.ax somefile.txt
# => %{"apple" => 2, "banana" => 1, "grape" => 1, ...}
```

### JSON Parser and Encoder

A complete JSON parser and encoder written entirely in Axiom (`examples/json/core.ax` + `examples/json/demo.ax`), demonstrating recursive sum types, character-level string processing, and the wildcard MATCH pattern:

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
mix axiom.run examples/json/demo.ax
# Parses and prints JSON values, extracts names, round-trips through encode

# Compatibility entrypoint (same output)
mix axiom.run examples/json.ax
```

### Number Guessing Game

An interactive game using LET, ASK!, and RANDOM (`examples/guess.ax`):

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
mix axiom.run examples/guess.ax
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
- Non-exhaustive MATCH arms (missing constructors, unless `_` wildcard is present)
- MATCH on non-variant values

Errors are reported with position information and the checker continues after errors to report multiple issues in one pass.

### VERIFY Engine

`VERIFY function_name N` generates N random inputs using StreamData, filters by PRE condition, executes the function, and checks POST holds. When a counterexample is found, it reports the exact inputs that broke the contract. User-defined sum types are supported with depth-limited recursive generation (via `StreamData.tree`).

### PROVE Solver

The detailed solver pipeline, supported proof surface, and trace event formats are documented in [`docs/prove.md`](docs/prove.md).

The content-addressed DAG (ETS-backed) is in place for future use in multi-agent workflows and compilation to BEAM bytecode.

## Roadmap

- **v0.0.1** (complete): Interpreter, PRE/POST contracts, REPL, TIMES/WHILE, FILTER/MAP/REDUCE, strings, I/O
- **v0.1.0** (complete): Static type checker, VERIFY (property-based contract testing), maps, Safe Bank milestone
- **v0.2.0** (complete): PROVE — compile-time contract verification via Z3 SMT solver
- **v0.3.0** (complete): Algebraic data types (TYPE/MATCH) — Option, Result, and user-defined sum types with exhaustiveness checking
- **v0.4.0** (complete): JSON parser/encoder milestone — wildcard MATCH, string primitives, ROT4, PAIRS, NUM_STR, VERIFY for sum types
- **v0.4.1**: PROVE for IF/ELSE branches (via SMT-LIB `ite`), ABS/MIN/MAX, function call inlining
- **v0.5.0**: LET bindings, ASK (prompted input), RANDOM, number guessing game example
- **v0.5.1**: FMT string formatting and SAID destructive print
- **v0.5.2**: IMPORT "file.ax" multi-file loading with recursive resolution, dedup, and cycle errors
- **v0.5.3**: Safe-by-default fallible ops (`READ_FILE`, `WRITE_FILE`, `TO_INT`, `TO_FLOAT`, `ASK`) returning built-in `result`; explicit `!` unsafe variants
- **v0.5.4**: Auto-loaded file prelude (`lib/prelude.ax`) with initial `result` utility helpers
- **v0.5.5**: Modular prelude split (`lib/prelude/result.ax`, `lib/prelude/str.ax`) with reusable result/string helpers
- **v0.6.0a**: PROVE supports `MATCH` for `option` values (narrow slice) with `examples/prove/proven_option.ax`
- **v0.6.0b** (complete): PROVE supports `MATCH` for `result` values (narrow slice) with `examples/prove/proven_result.ax`
- **v0.6.0c** (complete): PROVE supports `MATCH` for generic non-recursive int-field user ADTs with `examples/prove/proven_shape.ax`
- **v0.6.0d** (complete): PROVE decodes ADT counterexamples to constructor-shaped values (see `examples/prove/proven_shape_buggy.ax`)
- **v0.6.0e** (complete): PROVE prunes unreachable ADT MATCH branches when PRE constrains constructor tags (see `examples/prove/proven_shape_pruned.ax`)
- **v0.6.0f** (complete): PROVE broadens PRE inference across `AND`/`OR`/`NOT` forms and organizes proof examples under `examples/prove/`
- **v0.6.0g** (complete): PROVE adds optional MATCH pruning trace diagnostics
- **v0.6.0h** (complete): PROVE adds leveled trace controls (`summary`/`verbose`) and routes trace to stderr
- **v0.6.0i** (complete): PROVE adds structured JSON trace output (`AXIOM_PROVE_TRACE=json`)
- **v0.6.0j** (complete): JSON trace adds run start/end metadata, event indices, match site ids, and assumption snapshots
- **v0.6.0k** (complete): JSON trace adds proof lifecycle events and UNKNOWN/ERROR reason fields in run-end metadata
- **v0.6.0l** (complete): PROVE broadens refinement inference to helper-boolean equality forms (`... T EQ`) for MATCH pruning
- **v0.6.0m** (complete): PROVE normalizes composed helper booleans (idempotence/complement/absorption) to preserve MATCH narrowing
- **v0.6.0n** (complete): PROVE reduces split-guard aliases like `(a AND b) OR (a AND NOT b)` to preserve constructor narrowing
- **v0.6.0o** (complete): PROVE reduces implication+antecedent PRE forms like `(NOT c OR tag_guard) AND c` to preserve constructor narrowing
- **v0.6.0p** (complete): PROVE canonicalizes n-ary boolean PRE constraints (flatten/dedup/order/absorption) to reduce inference brittleness on noisy generated guards
- **v0.6.0q** (complete): PRE normalization is extracted to `Axiom.Solver.PreNormalize` with focused unit tests, keeping PROVE behavior stable while reducing solver-module complexity
- **v0.6.0r** (complete): PRE normalization adds bounded DeMorgan and comparison-negation pushdown to recover narrowing from `NOT`-wrapped generated guards
- **v0.6.0s** (complete): PRE normalization prunes local contradiction/tautology comparison pairs (same expression, integer constants) to reduce noisy guard branches
- **v0.6.0t** (complete): PRE normalization merges conjunction bounds into tighter intervals/equalities to unlock implication collapses and stronger narrowing
- **v0.6.0u** (complete): PRE normalization adds bounded shared-conjunct factoring in disjunctive guard shapes to expose narrowing opportunities
- **v0.6.0v** (complete): PRE normalization adds guarded one-step distribution (`A OR (B AND C)`) to expose implication collapses in generated guard shapes
- **v0.6.0w** (complete): PRE normalization adds bounded consensus reduction (`(A OR B) AND (A OR NOT B) => A`) for noisy generated conjunctions
- **v0.6.0x** (complete): JSON trace adds `rewrite_applied` events, rewrite summary metadata, and PRE raw/normalized snapshots on MATCH decisions
- **v0.6.0y** (complete): MATCH pruning internals add tag-bound assumptions (`min/max` from comparison constraints) alongside existing eq/neq assumptions
- **v0.6.0z** (complete): PROVE extracts tag constraints from helper-comparison encodings (`ite` boolean tags) and emits `inference_source` in JSON trace
- **v0.6.0aa** (complete): PROVE broadens helper-pattern extraction to `eq/neq` and simple affine wrappers around tag-boolean `ite` encodings
- **v0.6.0ab** (complete): PROVE extends helper-pattern extraction with bounded multiplicative wrappers (`* const`) around tag-boolean encodings
- **v0.6.0ac** (complete): PROVE adds stabilization guardrails (PRE idempotence tests, trace ordering/schema checks, and relaxed `all_proven` performance budget)
- **v0.6.0ad** (complete): Tactical PRE freeze (feature expansion gated for `Axiom.Solver.PreNormalize`) with rule-admission governance (`docs/prove-rule-admission.md`)
- **v0.6.1a** (complete): Practical language usability pass 1 (clearer PROVE UNKNOWN/ERROR hints and CLI run-summary diagnostics)
- **v0.6.1b** (complete): Practical language usability pass 2 (`mix axiom.run --help`, `--show-prelude`, and refreshed prelude examples)
- **v0.6.1c** (complete): Practical language usability pass 3 (diagnostics consistency, `--json-errors`, and diagnostics examples)
- **v0.6.1d** (complete): Practical language usability pass 4 (`--examples`, first-15-min docs, and CLI reference)
- **v0.6.1e** (complete): Practical language usability pass 5 (practical mini-app example + curated examples smoke test)
- **v0.6.2a** (complete): Practical programs pass 1 (ledger/todo end-to-end examples with imports/prelude/file I/O/VERIFY)
- **v0.6.2b** (complete): Practical programs pass 2 (stronger app-level assertions, report round-trip checks, argv-driven file-backed flow)
- **v0.6.2c** (complete): Practical programs pass 3 (larger module-split expenses workflow with smoke markers)
- **v0.6.2d** (complete): Practical programs pass 4 (cross-file cashflow composition + shared report/assert helpers)
- **v0.6.2e** (complete): Practical programs pass 5 (cashflow-alerts pipeline stage with risk classification)
- **v0.7.0o** (current): Bounded protocol helpers on top of the current protocol-checked actor model
- **v0.7.0** (next): Typed BEAM concurrency runtime completion (broader supervision ergonomics, richer actor patterns)
- **v0.8.0**: BEAM bytecode compilation
- **Future**: Declarative constraint solving, tensor/distribution primitives, multi-agent collaboration

## Requirements

- Elixir >= 1.12
- Erlang/OTP >= 24
- Z3 SMT solver (optional, required for `PROVE` — [install](https://github.com/Z3Prover/z3))
