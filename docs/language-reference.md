# Language Reference

### Literals

```
42                          # int
3.14                        # float
TRUE FALSE                         # bool
"hello world"               # string
[ 1 2 3 ]                   # list
M[ "a" 1 "b" 2 ]           # map (key-value pairs)
M[]                         # empty map
{ DUP ADD }                 # block (closure)
```

### Types

Functions declare parameter and return types. The type checker enforces these statically before any code runs.

```
int float bool str template    # concrete types
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

### Explicit Generics

Cairn supports explicit parametric polymorphism for functions.

Use type parameters directly after the function name:

```crn
DEF id[T] : T -> T
  DUP DROP
END
```

Multiple type parameters are allowed:

```crn
DEF swap[T U] : T U -> U T
  SWAP
END
```

Type variables:
- must be declared in the function's type parameter list
- may appear in both parameter and return positions
- are instantiated from the actual stack types at the call site

This means the checker uses the concrete values you push to determine what `T`,
`U`, and the other declared variables mean for that particular call.

For example:

```crn
DEF map_get_or[T] : T map[str T] str -> T
  ...
END
```

can be used as:

```text
before: [key:str, source:map[str str], fallback:str]
after:  [value:str]
```

and also as:

```text
before: [key:str, source:map[str int], fallback:int]
after:  [value:int]
```

Current scope and limits:
- generic functions: supported
- type variables in signatures: supported
- call-site generic instantiation: supported
- user-defined generic `TYPE` declarations: not supported yet
- explicit type application syntax: not supported yet
- full global type inference: not supported

This is intentionally an explicit, bounded first version. The practical goal is
to remove avoidable `any` from reusable helpers without turning Cairn into a
full Hindley-Milner language.

### Reading Stack Effects

Cairn signatures are written from the top of the stack outward:

- the **leftmost parameter type** is the value on top of the stack before the call
- the **leftmost return type** is the value on top of the stack after the call

So this signature:

```crn
DEF map_get_or[T] : T map[str T] str -> T
```

means:

```text
before: [key:str, source:map[str T], fallback:T]
after:  [value:T]
```

You push the fallback first, then the map, then the key last.

When in doubt, read signatures as:

```text
top_of_stack ... deeper_values -> top_of_stack_after ...
```

### Common Gotchas

These are the mistakes users make most often when reading or writing Cairn:

1. **Reading signatures left-to-right like normal arguments**
   - Cairn signatures are not “first argument, second argument” in source-order.
   - The leftmost type is the value on top of the stack.
   - If a helper says `A B C -> D`, the value of type `C` is pushed first, then `B`, then `A` last.

2. **Forgetting that `LET` consumes the top value**
   - `LET name` pops the top of the stack and binds it.
   - If you write several `LET`s in a row, they bind from the top downward.
   - Example:

   ```text
   before: [top, below]
   LET first
   LET second
   ```

   leaves:

   ```text
   first = top
   second = below
   ```

3. **Reversing “container first” helpers**
   - Operators like `CONS`, `PUT`, and `GET` are easy to invert mentally.
   - Examples:
     - `CONS`: list first, then element
     - `PUT`: map first, then key, then value
     - `GET`: map first, then key
   - Use the before/after stack diagrams below instead of guessing.

4. **Forgetting that `FMT` takes the format string on top**
   - The format string is pushed last, so it sits on top of the stack.
   - The values that fill `{}` placeholders sit underneath it.

5. **Assuming callback blocks see the same stack shape as ordinary helpers**
   - `FILTER`, `MAP`, and `FIND` callback blocks start with only the current element.
   - `REDUCE` callback blocks start with:
     - element on top
     - accumulator underneath
   - `HTTP_SERVE` handler blocks start with:
     - `path` on top
     - then `method`
     - then `query`
     - then `form`
     - then `headers`
     - then `cookies`
     - then `session`

6. **Assuming convenience runtime forms are the canonical stack order**
   - Some operators accept alternate forms for convenience (`REDUCE`, `FILTER`, `MAP`).
   - The reference documents the canonical stack order first.
   - Write helpers and examples against the canonical order unless there is a strong reason not to.

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
                             # current whitelist: int_to_string, float_to_string, env_get
AUTH_CHECK                    # pop password + username, push built-in result (Ok user_map | Err message)

# Comparison (pop 2, push bool)
EQ NEQ GT LT GTE LTE

# Logic
AND OR NOT

# Stack manipulation
DUP DROP SWAP OVER ROT ROT4

# Tuple operations
FST SND TRD

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
PAIRS                          # pop map, push list of #(key value) pairs
NUM_STR                        # pop number (int or float), push string

Checker note:
When a map comes from a string-key literal (`M[ "k" v ... ]`), Cairn tracks that shape.
`GET` reports missing literal fields early, and `PUT` reports literal field type mismatches early.

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
ASSERT_EQ                      # pop expected, pop actual, fail if they differ
ASSERT_TRUE ASSERT_FALSE       # pop bool, fail if it is not the expected value

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
TPL_LOAD                       # pop template path, push result (Ok template | Err str)
TPL_RENDER                     # pop context map (string keys), pop template, push result (Ok str | Err str)
HTTP_SERVE                     # pop port + handler block (or bind addr + port + handler), serve requests until stopped
READ_LINE                      # read one line from stdin
RANDOM                         # pop N, push random integer in [1, N]

# Bounded local persistence (Mnesia-backed)
DB_PUT                         # pop key, pop value, persist a string record
DB_GET                         # pop key, push result (Ok str | Err str)
DB_DEL                         # pop key, delete record
DB_PAIRS                       # push list of #(key value) string pairs
```

### Common Before/After Stack Shapes

These are the operators and helper patterns that are easiest to misread.

```text
ADD
before: [right:int, left:int]
after:  [sum:int]

SUB
before: [right:int, left:int]
after:  [difference:int]
note: computes left - right

DIV
before: [right:int, left:int]
after:  [quotient:int]
note: computes left / right using integer division

PUT
before: [value:V, key:K, map:map[K V]]
after:  [updated_map:map[K V]]

GET
before: [key:K, map:map[K V]]
after:  [value:V]

HAS
before: [key:K, map:map[K V]]
after:  [present:bool]

FMT
before: [format:str, value_n, ..., value_1]
after:  [formatted:str]
note: the format string is on top; placeholder values sit underneath it
note: push placeholder values from right to left, then push the format string
note: for `"#{} [{}] {}"` push `third`, then `second`, then `first`, then the format string

ASSERT_EQ
before: [expected, actual]
after:  []

WITH_STATE
before: [block, initial_state]
after:  [final_state]

STATE
before: [...]
after:  [current_state, ...]

SET_STATE
before: [next_state, ...]
after:  [...]

STEP helper
before: [...]
after:  [...]
note: inside WITH_STATE, applies a helper of shape state -> state

HTTP_SERVE
before (default): [handler_block, port]
before (explicit bind): [handler_block, port, bind_addr]
before (with options): [handler_block, port, options]
after:  blocks forever serving requests (no normal stack result)

HTTP_SERVE handler block
before: [path:str, method:str, query:map[str str], form:map[str str], headers:map[str str], cookies:map[str str], session:map[str str]]
after (legacy):  [body:str, content_type:str, status:int]
after (headers): [body:str, headers:map[str str], status:int]
after (session): [body:str, headers:map[str str], session:map[str str], status:int]

AUTH_CHECK
before: [password:str, username:str]
after (success): [result:Ok(map[str str])]
after (failure): [result:Err(str)]
note: push the username first, then the password last

POW
before: [exponent:float, base:float]
after:  [result:float]
note: computes base ^ exponent
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
"postgres" "127.0.0.1" 8090 "backend={} host={} port={}" FMT  # => "backend=postgres host=127.0.0.1 port=8090"
"postgres" "/tmp/seed.txt" 8133 "127.0.0.1" "http://{}:{}/ source={} backend={}" FMT
# => "http://127.0.0.1:8133/ source=/tmp/seed.txt backend=postgres"
# stack reminder: push values right-to-left, then push format string last
```

Values are auto-converted: integers and floats become their string representation, booleans become `"TRUE"` / `"FALSE"`, and everything else uses `inspect`.

### Control Flow

```
# Conditional
TRUE IF 42 END                     # pushes 42
FALSE IF 1 ELSE 2 END              # pushes 2

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

### Type Aliases

`TYPEALIAS` names a type expression so signatures stay readable.

```
TYPEALIAS headers = map[str str]
TYPEALIAS http_response = tuple[str headers int]
TYPEALIAS route_result = result[http_response str]
```

Aliases can be generic:

```
TYPEALIAS pair[T U] = tuple[T U]
TYPEALIAS maybe[T] = result[T str]
```

Aliases are compile-time only. They do not create constructors and are fully expanded by the checker.

**Stack convention**: `param_types[0]` is the TOP of stack. To call a function that takes `option int`, push the `int` default first, then the `option` last:

```
0 42 Some unwrap_or    # stack before call: [Some(42), 0] (option on top)
```

Some high-value helper examples:

```text
result_unwrap_or
signature: result[T E] T -> T
before: [result:T|E, fallback:T]
after:  [value_or_fallback]

result_map
signature: block result[T E] -> result[U E]
before: [mapper:block, input:result[T E]]
after:  [mapped:result[U E]]

result_map_err
signature: block result[T E] -> result[T F]
before: [mapper:block, input:result[T E]]
after:  [mapped:result[T F]]

result_and_then
signature: block result[T E] -> result[U E]
before: [next:block, input:result[T E]]
after:  [output:result[U E]]

result_tap_err
signature: block result[T E] -> result[T E]
before: [on_err:block, input:result[T E]]
after:  [output:result[T E]]

map_get_or[T]
signature: T map[str T] str -> T
before: [key:str, source:map[str T], fallback:T]
after:  [value_or_fallback:T]
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
For production-style runs that should ignore inline assurance directives in loaded code, set `CAIRN_SKIP_ASSURANCE=1` to skip both `VERIFY` and `PROVE` during evaluation.

## Function Effects

Functions may optionally declare an effect:

```crn
DEF score : int int -> int EFFECT pure
  SUB
END
```

Built-in effect kinds:
- `pure`
- `io`
- `db`
- `http`

If omitted, functions currently default to `io`.

Current v1 rule:
- `pure` functions may only call other `pure` functions
- `pure` functions may not use effectful built-ins such as file I/O, database operators, HTTP serving, prompting, printing, host calls, or `RANDOM`

In other words:
- every function has an effect
- explicit `EFFECT ...` annotations make that effect visible
- only `pure` has a hard restriction in v1
- `io`, `db`, and `http` are currently descriptive labels that document intent and prepare the codebase for future stricter effect relationships

The intended architecture pattern is:
- keep business rules and data transforms in `EFFECT pure` functions
- keep shells, adapters, persistence, and serving code in `EFFECT io|db|http` functions

This is the current "pure kernel + effectful shell" split used by the stronger examples:
- `examples/web/lib/afford_rules.crn`: pure decision logic
- `examples/web/lib/afford_web.crn`: still pure, because it only parses form data and renders responses
- `examples/web/afford_app.crn`: effectful top-level script, because it calls `HTTP_SERVE`
- `examples/web/lib/todo_web.crn`: mixed helper layer, with pure rendering helpers and `db` persistence helpers

`PROVE` respects this boundary:
- proving a non-`pure` function returns `UNKNOWN` with the reason `function is not pure`

Example:

```crn
DEF reserve_threshold : int -> int EFFECT pure
  3 MUL
END

DEF render_dashboard : str -> str str int EFFECT pure
  "<p>{}</p>" FMT
  http_html_ok
END
```

The first helper is pure rule logic. The second is also pure because it only transforms values and uses pure response helpers. The effectful boundary is the code that actually serves requests, reads files, writes to the DB, or talks to the outside world.

For the full proof surface, trace modes, and solver details, see [`prove.md`](prove.md).

### Native Tests

Use `TEST ... END` to declare concrete Cairn-native test cases:

```
TEST "safe one-time purchase remains safe"
  "one_time" 5000 3000 1000 500 affordability_score
  0 ASSERT_EQ
END
```

Run a test file with:

```
./cairn --test examples/web/afford_test.crn
```

`TEST` blocks are ignored during normal file evaluation and only execute in explicit `--test` mode.

### Native Test Stack Shapes

`TEST` bodies start from a clean stack. Assertions consume the values they check:

```text
ASSERT_EQ
before: [expected, actual]
after:  []
note: push the expected value first, then the actual value last

ASSERT_TRUE
before: [value:bool]
after:  []

ASSERT_FALSE
before: [value:bool]
after:  []
```

That means this pattern is correct:

```crn
2 3 ADD
5 ASSERT_EQ
```

because the stack just before `ASSERT_EQ` is:

```text
[expected:5, actual:5]
```

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

### Higher-Order and Collection Stack Shapes

These operators are compact, but their operand order is easy to misread. Read them as exact stack transforms:

```text
FST
before: [pair:tuple[T U]]
after:  [first:T]

SND
before: [pair:tuple[T U]]
after:  [second:U]

TRD
before: [triple:tuple[T U V]]
after:  [third:V]
```

```text
CONS
before: [list:[T], elem:T]
after:  [new_list:[T]]
note: push the element first, then the list last

ZIP
before: [right:[B], left:[A]]
after:  [zipped:[tuple[A B]]]
note: each pair is encoded as a tuple #(left right)

ENUMERATE
before: [list:[T]]
after:  [indexed:[tuple[int T]]]
note: indices start at 1, and each pair is #(index element)

FILTER
before: [list:[T], block:block[bool]]
after:  [filtered:[T]]
block input stack: [element:T]
block output stack: [keep?:bool]

MAP
before: [list:[T], block:block[U]]
after:  [mapped:[U]]
block input stack: [element:T]
block output stack: [mapped_value:U]

FLAT_MAP
before: [list:[T], block:block[[U]]]
after:  [flattened:[U]]
block input stack: [element:T]
block output stack: [mapped_list:[U]]

FIND
before: [list:[T], block:block[bool]]
after:  [result]
block input stack: [element:T]
block output stack: [match?:bool]
note: returns Ok element or Err \"not found\"

GROUP_BY
before: [list:[T], block:block[K]]
after:  [grouped:map[K [T]]]
block input stack: [element:T]
block output stack: [group_key:K]

REDUCE
canonical before: [list:[T], initial:U, block:block[U]]
canonical after:  [result:U]
block input stack: [element:T, accumulator:U]
block output stack: [next_accumulator:U]
note: the runtime also accepts the convenience form [block, initial, list] by reordering internally

APPLY
before: [value_1, ..., value_n, block]
after:  [result_1, ..., result_m]
note: APPLY executes the block on the current visible stack; it does not create a fresh stack the way FILTER/MAP/REDUCE callbacks do

TIMES
canonical before: [count:int, block]
canonical after:  [updated_stack...]
note: runs the block exactly count times
note: the runtime also accepts the convenience form [block, count]

REPEAT
canonical before: [count:int, block]
canonical after:  [updated_stack...]
note: same stack semantics as TIMES; it exists as the readability-oriented sibling used in newer state-machine style code

WHILE
before: [body:block, condition:block]
after:  [updated_stack...]
condition block input stack: [current_stack...]
condition block output stack: [continue?:bool, current_stack...]
body block input stack: [current_stack...]
body block output stack: [next_stack...]
note: write it in source as { condition } { body } WHILE, which leaves the body block on top when WHILE runs

RANGE
before: [n:int]
after:  [values:[int]]

DB_PAIRS
before: []
after:  [pairs:[tuple[str str]]]
note: each entry is a tuple #(key value)

READ_FILE
before: [path:str]
after:  [result[str str]]
note: use `MATCH` to handle `Ok` file contents vs `Err` message

READ_FILE!
before: [path:str]
after:  [contents:str]
note: unsafe variant that raises on failure

WRITE_FILE
before: [contents:str, path:str]
after:  [result[bool str]]
note: push contents first, then path; returns `Ok TRUE` or `Err message`

WRITE_FILE!
before: [contents:str, path:str]
after:  []
note: unsafe variant that raises on failure

TPL_LOAD
before: [path:str]
after:  [result[template str]]
note: loads and parses a `.ctpl` file into a compiled template value

TPL_RENDER
before: [context:map[str any], tmpl:template]
after:  [result[str str]]
note: `{{...}}` escapes HTML by default; `{{{...}}}` is raw and must be trusted input
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

# Serve two static pages plus a tiny query-driven echo on localhost until stopped
"examples/web/lib/hello_static.crn" IMPORT
"127.0.0.1" 8089 {
  handle_static_request
} HTTP_SERVE

# Optional bounded transport overrides:
M[
  "request_line_max" 4096
  "read_timeout_ms" 5000
  "body_max" 8192
]
"127.0.0.1" 8089 {
  handle_static_request
} HTTP_SERVE

# The route helpers can also be used directly:
"/about" LET path
"GET" LET method
path method "/" "<p>Home</p>" route_get_text
path method "/about" "<p>About</p>" route_get_text
route_or
method route_finish_get

# HTTP_SERVE handlers now receive path, method, query, form, headers, cookies, and session (path on top):
LET path
LET method
LET query
LET form
LET headers
LET cookies
LET session
"name" query "friend" map_get_or
"theme" cookies "none" map_get_or
"name" session "" map_get_or

# Escape untrusted text before embedding it into HTML:
"<script>alert('hola')</script>" html_escape

# Current HTTP_SERVE defaults:
# - request_line_max = 4096   (oversized first line -> 414 URI Too Long)
# - read_timeout_ms  = 5000   (idle client -> quiet close)
# - body_max         = 8192   (oversized form body -> 413 Payload Too Large)

# Minimal local persistence (stored under .cairn_mnesia by default)
"open|buy milk" "todo:1" DB_PUT
"todo:1" DB_GET
DB_PAIRS
# Set CAIRN_DB_DIR to use a different on-disk Mnesia directory
```

### Tuples

Tuples are fixed-size, heterogeneous values. They are distinct from lists.

Tuple value syntax:

```crn
#( 1 "red" )
#("body" "text/html; charset=utf-8" 200)
```

Tuple type syntax:

```crn
tuple[int str]
tuple[str map[str str] int]
tuple[T U]
```

Use tuples when the shape is:
- fixed-size
- positional
- potentially heterogeneous

Use lists when the shape is:
- variable-length
- homogeneous

### Web Helper Stack Shapes

The web prelude is deliberately small, but the route helpers are easiest to use when you read them as exact stack transforms:

```text
http_html_ok
before: [body:str]
after:  [body:str, headers:map[str str], status:int]

http_text_ok
before: [body:str]
after:  [body:str, headers:map[str str], status:int]

http_text_not_found
before: [body:str]
after:  [body:str, headers:map[str str], status:int]

http_text_method_not_allowed
before: [body:str]
after:  [body:str, headers:map[str str], status:int]

http_text_unauthorized
before: [body:str]
after:  [body:str, headers:map[str str], status:int]

http_text_forbidden
before: [body:str]
after:  [body:str, headers:map[str str], status:int]

http_html_file_ok
before: [path:str]
after:  [body:str, headers:map[str str], status:int]

html_escape
before: [raw:str]
after:  [escaped:str]

http_pack_response
before: [body:str, headers:map[str str], status:int]
after:  [packed:tuple[str map[str str] int]]
note: this packs the HTTP_SERVE response triple into one value for route chaining

http_unpack_response
before: [packed:tuple[str map[str str] int]]
after:  [body:str, headers:map[str str], status:int]

request_pack
before: [path:str, method:str, query:map[str str], form:map[str str], headers:map[str str], cookies:map[str str], session:map[str str]]
after:  [ctx:tuple[str str tuple[map[str str] map[str str] tuple[map[str str] map[str str] map[str str]]]]]

request_unpack
before: [ctx:tuple[str str tuple[map[str str] map[str str] tuple[map[str str] map[str str] map[str str]]]]]
after:  [path:str, method:str, query:map[str str], form:map[str str], headers:map[str str], cookies:map[str str], session:map[str str]]

request_ctx_path
before: [ctx:tuple[str str tuple[map[str str] map[str str] tuple[map[str str] map[str str] map[str str]]]]]
after:  [path:str]

request_ctx_method
before: [ctx:tuple[str str tuple[map[str str] map[str str] tuple[map[str str] map[str str] map[str str]]]]]
after:  [method:str]

request_ctx_query
before: [ctx:tuple[str str tuple[map[str str] map[str str] tuple[map[str str] map[str str] map[str str]]]]]
after:  [query:map[str str]]

request_ctx_form
before: [ctx:tuple[str str tuple[map[str str] map[str str] tuple[map[str str] map[str str] map[str str]]]]]
after:  [form:map[str str]]

request_ctx_headers
before: [ctx:tuple[str str tuple[map[str str] map[str str] tuple[map[str str] map[str str] map[str str]]]]]
after:  [headers:map[str str]]

request_ctx_cookies
before: [ctx:tuple[str str tuple[map[str str] map[str str] tuple[map[str str] map[str str] map[str str]]]]]
after:  [cookies:map[str str]]

request_ctx_session
before: [ctx:tuple[str str tuple[map[str str] map[str str] tuple[map[str str] map[str str] map[str str]]]]]
after:  [session:map[str str]]

response_pack_ctx
before: [body:str, headers:map[str str], status:int]
after:  [response_ctx:tuple[str map[str str] int]]

response_unpack_ctx
before: [response_ctx:tuple[str map[str str] int]]
after:  [body:str, headers:map[str str], status:int]

session_response_pack_ctx
before: [body:str, headers:map[str str], session:map[str str], status:int]
after:  [session_response_ctx:tuple[str map[str str] tuple[map[str str] int]]]

session_response_unpack_ctx
before: [session_response_ctx:tuple[str map[str str] tuple[map[str str] int]]]
after:  [body:str, headers:map[str str], session:map[str str], status:int]

response_with_session_ctx
before: [session:map[str str], response_ctx:tuple[str map[str str] int]]
after:  [session_response_ctx:tuple[str map[str str] tuple[map[str str] int]]]

session_response_return
before: [session_response_ctx:tuple[str map[str str] tuple[map[str str] int]]]
after:  [body:str, headers:map[str str], session:map[str str], status:int]

session_response_clear_ctx
before: [session_response_ctx:tuple[str map[str str] tuple[map[str str] int]]]
after:  [session_response_ctx:tuple[str map[str str] tuple[map[str str] int]]]

respond_with_ctx_session
before: [ctx:request_ctx, body:str, headers:map[str str], status:int]
after:  [body:str, headers:map[str str], session:map[str str], status:int]

respond_with_ctx_cleared_session
before: [ctx:request_ctx, body:str, headers:map[str str], status:int]
after:  [body:str, headers:map[str str], session:map[str str], status:int]

guard_login_response
before: [ctx:request_ctx, body:str, headers:map[str str], status:int]
after:  [body:str, headers:map[str str], session:map[str str], status:int]
note: passes through response when logged in, otherwise returns 401 with current session context

guard_role_response
before: [required_role:str, ctx:request_ctx, body:str, headers:map[str str], status:int]
after:  [body:str, headers:map[str str], session:map[str str], status:int]
note: passes when role matches; returns 401 if not logged in, 403 when logged in but role mismatches

http_add_header
before: [value:str, key:str, body:str, headers:map[str str], status:int]
after:  [body:str, headers:map[str str], status:int]
note: used to add Set-Cookie, Location, or other response headers from Cairn

session_put
before: [value:str, key:str, body:str, headers:map[str str], session:map[str str], status:int]
after:  [body:str, headers:map[str str], session:map[str str], status:int]
note: updates the outgoing session map; the runtime persists it and issues the session cookie

session_clear
before: [body:str, headers:map[str str], session:map[str str], status:int]
after:  [body:str, headers:map[str str], session:map[str str], status:int]
note: returns an empty outgoing session map; the runtime clears the stored session and expires the cookie

session_has_user
before: [session:map[str str]]
after:  [present:bool]

session_has_role
before: [required_role:str, session:map[str str]]
after:  [allowed:bool]

guard_require_login
before: [session:map[str str]]
after:  [allowed:bool]
note: this is a boolean guard predicate; it does not build an HTTP response by itself

guard_require_role
before: [required_role:str, session:map[str str]]
after:  [allowed:bool]
note: this is a boolean guard predicate; pair it with `http_text_unauthorized` or `http_text_forbidden`

AUTH_CHECK is the first auth-facing built-in. It checks credentials through the
runtime-side user-store boundary and returns the built-in `result` type. The
current default user-store implementation is Mnesia-backed, but Cairn app code
does not talk to raw `DB_*` operations for login.

route_get_html_file
before: [file:str, route:str, method:str, path:str]
after:  [candidate:result]

route_get_text
before: [body:str, route:str, method:str, path:str]
after:  [candidate:result]

route_is_method_path
before: [route:str, expected_method:str, method:str, path:str]
after:  [match:bool]

route_is_get
before: [route:str, method:str, path:str]
after:  [match:bool]

route_is_post
before: [route:str, method:str, path:str]
after:  [match:bool]

route_method_allowed
before: [allowed:[str], method:str]
after:  [allowed?:bool]

route_or
before: [fallback:result, preferred:result]
after:  [chosen:result]

route_finish_get
before: [method:str, candidate:result]
after:  [body:str, headers:map[str str], status:int]

route_finish_allowed
before: [allowed:[str], method:str, candidate:result]
after:  [body:str, headers:map[str str], status:int]

route_session_from_ctx
before: [ctx:request_ctx, body:str, headers:map[str str], status:int]
after:  [candidate:result[session_response_ctx str]]

route_session_from_ctx_cleared
before: [ctx:request_ctx, body:str, headers:map[str str], status:int]
after:  [candidate:result[session_response_ctx str]]

route_or_session
before: [fallback:result[session_response_ctx str], preferred:result[session_response_ctx str]]
after:  [chosen:result[session_response_ctx str]]

route_get_session
before: [ctx:request_ctx, route:str, handler:block[result[session_response_ctx str]]]
after:  [candidate:result[session_response_ctx str]]
note: executes handler only when ctx.method/path matches GET route; handler usually captures `ctx` lexically

route_post_session
before: [ctx:request_ctx, route:str, handler:block[result[session_response_ctx str]]]
after:  [candidate:result[session_response_ctx str]]
note: executes handler only when ctx.method/path matches POST route; handler usually captures `ctx` lexically

route_guard_login_candidate
before: [candidate:result[session_response_ctx str]]
after:  [candidate:result[session_response_ctx str]]
note: when candidate is Ok, enforces login guard and rewrites to 401 response when missing user session

route_guard_role_candidate
before: [required_role:str, candidate:result[session_response_ctx str]]
after:  [candidate:result[session_response_ctx str]]
note: when candidate is Ok, enforces role guard and rewrites to 401/403 response as needed

route_with_login
before: [candidate:result[session_response_ctx str]]
after:  [candidate:result[session_response_ctx str]]
note: middleware-friendly alias for `route_guard_login_candidate`

route_with_role
before: [required_role:str, candidate:result[session_response_ctx str]]
after:  [candidate:result[session_response_ctx str]]
note: middleware-friendly alias for `route_guard_role_candidate`

route_chain_session2
before: [second:result[session_response_ctx str], first:result[session_response_ctx str]]
after:  [candidate:result[session_response_ctx str]]
note: returns the first successful candidate (first-match semantics)

route_chain_session6
before: [sixth:result[session_response_ctx str], fifth:result[session_response_ctx str], fourth:result[session_response_ctx str], third:result[session_response_ctx str], second:result[session_response_ctx str], first:result[session_response_ctx str]]
after:  [candidate:result[session_response_ctx str]]
note: bounded chain helper for six candidates with first-match semantics

route_finish_session
before: [ctx:request_ctx, candidate:result[session_response_ctx str]]
after:  [body:str, headers:map[str str], session:map[str str], status:int]

route_finish_session_allowed
before: [allowed:[str], ctx:request_ctx, candidate:result[session_response_ctx str]]
after:  [body:str, headers:map[str str], session:map[str str], status:int]
```

`HTTP_SERVE` accepts either response shape:

```text
classic response:
before final return: [body:str, headers:map[str str], status:int]

session-aware response:
before final return: [body:str, headers:map[str str], session:map[str str], status:int]
```

If a session map is returned, the runtime treats it as the desired next session state:
- non-empty session -> persist and issue/reuse `cairn_session`
- empty session -> clear the stored session and expire the cookie

So a typical GET route chain reads like this:

```crn
path method "/" "<p>Home</p>" route_get_text
path method "/about" "<p>About</p>" route_get_text
route_or
method route_finish_get
```

with the stack evolving as:

```text
after first route:  [candidate_for_/]
after second route: [candidate_for_/about, candidate_for_/]
after route_or:     [best_candidate]
after route_finish_get: [body, headers, status]
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
    FALSE
  ELSE
    guess secret LT IF
      "Too low!" SAID
    ELSE
      "Too high!" SAID
    END
    TRUE
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
