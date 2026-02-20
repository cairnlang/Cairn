# Axiom v0.0.1 — Minimal BEAM Implementation Plan

## Goal

A working end-to-end pipeline: **parse Axiom source -> build DAG -> compile to BEAM bytecode -> execute**. Plus a REPL to interact with it. Nothing more.

---

## What's IN v0.0.1

1. **Postfix imperative subset only** — no constraint solver, no declarative mode. Those are the hard, interesting parts, but they depend on having a working runtime first.
2. **Basic types:** `int`, `float`, `bool`, `list` (homogeneous).
3. **Content-addressed DAG as the IR** — every AST node gets a hash. Stored in ETS.
4. **Compilation to BEAM** — transpile the DAG into Erlang Abstract Format, then use `:compile.forms/1` to produce `.beam` modules.
5. **Simple contracts** — `POST` conditions only, checked at runtime (no synthesis, just assertion).
6. **A REPL** — IEx-based, evaluate Axiom expressions interactively.

## What's NOT in v0.0.1

- Constraint solver / declarative mode (v0.1.0)
- Tensor/embedding/distribution types (v0.2.0)
- Multi-agent workflows (v0.3.0 — the BEAM is ready, but the tooling isn't)
- Probabilistic branching
- Custom tokenizer alignment
- Any kind of package system

---

## Architecture

```
 axiom source text
       │
       ▼
 ┌─────────────┐
 │   Lexer      │   Elixir module, simple token stream
 └──────┬───────┘
        │ tokens
        ▼
 ┌─────────────┐
 │   Parser     │   Postfix grammar, outputs DAG nodes
 └──────┬───────┘
        │ DAG nodes
        ▼
 ┌─────────────────────┐
 │   DAG Store (ETS)    │   Content-addressed, structural sharing
 └──────┬──────────────┘
        │ DAG root hash
        ▼
 ┌─────────────────────┐
 │   Contract Checker   │   Attaches POST conditions to function nodes
 └──────┬──────────────┘
        │ annotated DAG
        ▼
 ┌─────────────────────┐
 │   Codegen            │   DAG -> Erlang Abstract Format
 └──────┬──────────────┘
        │ Erlang AST
        ▼
 ┌─────────────────────┐
 │   :compile.forms/1   │   Standard BEAM compiler
 └──────┬──────────────┘
        │ .beam bytecode
        ▼
      execution
```

---

## Project Structure

```
axiom/
├── mix.exs
├── lib/
│   ├── axiom.ex                  # Public API: Axiom.compile/1, Axiom.eval/1
│   ├── axiom/
│   │   ├── lexer.ex              # Source text -> token list
│   │   ├── parser.ex             # Token list -> DAG nodes
│   │   ├── dag.ex                # DAG storage, hashing, ETS interface
│   │   ├── types.ex              # Type definitions and checking
│   │   ├── contract.ex           # POST condition parsing and runtime checks
│   │   ├── codegen.ex            # DAG -> Erlang Abstract Format
│   │   └── repl.ex               # Interactive shell
├── test/
│   ├── lexer_test.exs
│   ├── parser_test.exs
│   ├── dag_test.exs
│   ├── codegen_test.exs
│   ├── contract_test.exs
│   └── integration_test.exs      # End-to-end: source -> execution -> result
```

---

## Module Details

### Lexer (`lib/axiom/lexer.ex`)

Turns source text into a flat list of tokens. Axiom's postfix syntax makes this straightforward — no nesting to track.

**Token types:**
```elixir
:int_lit       # 42, -7
:float_lit     # 3.14
:bool_lit      # T, F
:list_open     # [
:list_close    # ]
:op            # ADD, SUB, MUL, DIV, MOD, EQ, NEQ, GT, LT, GTE, LTE
               # AND, OR, NOT
               # DUP, DROP, SWAP, OVER, ROT
               # FILTER, MAP, SUM, LEN, HEAD, TAIL, CONS, CONCAT
               # SQ, ABS, NEG
:ident         # short semantic tags: uid, ptot, etc.
:fn_def        # DEF
:fn_end        # END
:post          # POST
:colon         # : (used in type annotations)
:type          # int, float, bool, list
:arrow         # ->
```

**Example:**
```
"DEF double : int -> int DUP ADD END"
 =>
[{:fn_def, "DEF"}, {:ident, "double"}, {:colon, ":"}, {:type, "int"},
 {:arrow, "->"}, {:type, "int"}, {:op, "DUP"}, {:op, "ADD"}, {:fn_end, "END"}]
```

No whitespace sensitivity. Tokens are space-delimited. That's it.

---

### Parser (`lib/axiom/parser.ex`)

Consumes the token list and builds DAG nodes. Axiom has two constructs at the top level:

1. **Expressions** — a sequence of literals, identifiers, and operators (postfix).
2. **Function definitions** — `DEF name : type -> type [POST condition] body END`.

The parser doesn't need to handle operator precedence (postfix has none) or nesting (no parens). It walks the token list linearly and emits DAG nodes.

**DAG node structure:**
```elixir
%Axiom.DAG.Node{
  hash: "a1b",          # content-derived, 3-char base62
  op: :add,             # or :lit, :ident, :filter, :map, etc.
  inputs: ["f2c", "d8a"], # hashes of input nodes
  type: :int,           # inferred or annotated
  meta: %{}              # line number, source span, etc.
}
```

---

### DAG (`lib/axiom/dag.ex`)

An ETS-backed store of DAG nodes.

```elixir
Axiom.DAG.init()                    # creates the ETS table
Axiom.DAG.put(node)                 # stores a node, returns its hash
Axiom.DAG.get(hash)                 # retrieves a node
Axiom.DAG.roots()                   # returns all root nodes (entry points)
Axiom.DAG.subgraph(hash)            # returns all nodes reachable from hash
```

**Hashing:** `hash = :crypto.hash(:sha256, :erlang.term_to_binary({op, inputs})) |> Base.encode64() |> binary_part(0, 6)`

Six characters is plenty for a v0.0.1 — collision-free for any reasonable program size.

---

### Codegen (`lib/axiom/codegen.ex`)

The core compilation step. Walks the DAG from a root node and emits **Erlang Abstract Format** — the AST representation that `:compile.forms/1` accepts.

**Strategy:** Each Axiom function compiles to an Erlang function that operates on an explicit stack (a list).

```elixir
# Axiom: DEF double : int -> int DUP ADD END
# Compiles conceptually to:
def double(stack) do
  stack
  |> dup()
  |> add()
end
```

In practice, this means generating the Erlang Abstract Format for the above. The stack is a list, each operator is a function that pattern-matches the top elements, operates, and returns the new stack.

**Built-in operator implementations** live in a runtime module (`Axiom.Runtime`) that the generated code calls into:

```elixir
defmodule Axiom.Runtime do
  def add([a, b | rest]), do: [a + b | rest]
  def dup([a | rest]), do: [a, a | rest]
  def swap([a, b | rest]), do: [b, a | rest]
  def filter(pred, [list | rest]), do: [Enum.filter(list, pred) | rest]
  # ... etc
end
```

For v0.0.1, this is fine. Later versions can inline operations and do proper stack allocation.

---

### Contracts (`lib/axiom/contract.ex`)

Minimal implementation: a `POST` condition is parsed as an Axiom expression that must evaluate to `T` (true) given the function's output on the stack.

```
DEF abs_val : int -> int
  POST DUP 0 GTE
  DUP 0 LT IF NEG END
END
```

At compile time, the codegen wraps the function body to check the postcondition on the output stack before returning. If it fails, it raises `Axiom.ContractError`.

No synthesis, no solver — just runtime assertion. This gets the contract *syntax* into the language early so the habit forms, and lays the groundwork for the solver in v0.1.0.

---

### REPL (`lib/axiom/repl.ex`)

An IEx helper that provides an `ax>` prompt:

```
ax> 3 4 ADD
[7]

ax> [1 2 3 4 5] 2 MOD 1 EQ FILTER
[[1, 3, 5]]

ax> DEF sq : int -> int DUP MUL END
:ok

ax> 7 sq
[49]
```

Implemented as a simple loop: read line -> lex -> parse -> compile to anonymous BEAM module -> execute -> print stack.

---

## Milestone Breakdown

### M1: Lexer + Parser + DAG (foundation)
- [ ] `mix new axiom` project setup
- [ ] Lexer handles all token types
- [ ] Parser builds DAG nodes from expressions
- [ ] Parser handles function definitions
- [ ] DAG store with ETS, content hashing, put/get
- [ ] Tests for all of the above

### M2: Codegen + Runtime (it runs)
- [ ] `Axiom.Runtime` module with all v0.0.1 operators
- [ ] Codegen emits Erlang Abstract Format for expressions
- [ ] Codegen emits Erlang Abstract Format for function definitions
- [ ] `:compile.forms/1` integration — produce loadable BEAM modules
- [ ] `Axiom.eval("3 4 ADD")` returns `[7]`
- [ ] Tests: arithmetic, stack ops, list ops

### M3: Contracts (it checks itself)
- [ ] `POST` condition parsing
- [ ] Contract wrapping in codegen
- [ ] `Axiom.ContractError` on violation
- [ ] Tests: passing contracts, failing contracts

### M4: REPL (you can touch it)
- [ ] `Axiom.REPL.start/0`
- [ ] Expression evaluation loop
- [ ] Function definition persistence within session
- [ ] Error display (stack underflow, type mismatch, contract violation)

### M5: Integration + polish
- [ ] End-to-end test: multi-function program with contracts
- [ ] Error messages with source locations
- [ ] `mix axiom.run` task for running `.ax` files
- [ ] Minimal README with examples

---

## Syntax Reference (v0.0.1)

```
# Literals
42              # int
3.14            # float
T F             # bool
[1 2 3]         # list

# Arithmetic
ADD SUB MUL DIV MOD     # binary, pop 2, push 1
SQ ABS NEG              # unary, pop 1, push 1

# Comparison
EQ NEQ GT LT GTE LTE    # pop 2, push bool

# Logic
AND OR NOT

# Stack manipulation
DUP DROP SWAP OVER ROT

# List operations
FILTER MAP SUM LEN HEAD TAIL CONS CONCAT

# Control flow
IF ... END               # pops bool, executes body if T
IF ... ELSE ... END       # pops bool, branches

# Function definition
DEF name : type -> type
  [POST condition]
  body
END

# Type annotations
int float bool [int] [float]    # list types in brackets
```

---

## Design Decisions and Rationale

**Why transpile to Erlang Abstract Format instead of generating Elixir AST?**
Erlang Abstract Format is stable, well-documented, and closer to the BEAM. Elixir's AST is a moving target tied to compiler internals. Going straight to Erlang AF means we depend on OTP, not on Elixir's compiler version.

**Why ETS for the DAG?**
It's concurrent-read by default, available in any BEAM process, and fast. When we add multi-agent support later, multiple processes can read the DAG simultaneously without coordination. Writes go through a single process (the DAG server) to maintain consistency.

**Why an explicit stack instead of compiling to native Erlang variables?**
Simpler codegen. The stack model maps 1:1 to Axiom's postfix semantics. Optimizing to direct variable bindings is a v0.1.0 concern — get it correct first, then get it fast.

**Why not Gleam/LFE instead of Elixir?**
Elixir has the richest tooling (Mix, IEx, ExUnit, Hex), the largest BEAM ecosystem, and metaprogramming capabilities we'll want for the REPL and future macro system. If the project matures, core runtime components could be rewritten in Erlang for fewer dependencies.
