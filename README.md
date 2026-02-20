# Axiom

An AI-native programming language targeting the BEAM.

Stack-based, postfix, contract-checked. Designed around the idea that an AI-first language should optimize for **reasoning correctness** over human readability — with declarative constraints, content-addressed structure, and the BEAM's actor model as the foundation for multi-agent collaboration.

This is v0.0.1: an interpreted postfix core with runtime contracts, closures, loops, and a REPL.

## Quick Start

```bash
# Run a file
mix axiom.run examples/collatz.ax

# Start the REPL
mix run -e "Axiom.REPL.start()"

# Run tests
mix test
```

## Language Reference

### Literals

```
42              # int
3.14            # float
T F             # bool
[ 1 2 3 ]       # list
{ DUP ADD }     # block (closure)
```

### Operators

```
# Arithmetic (binary: pop 2, push 1)
ADD SUB MUL DIV MOD

# Arithmetic (unary: pop 1, push 1)
SQ ABS NEG

# Comparison (pop 2, push bool)
EQ NEQ GT LT GTE LTE

# Logic
AND OR NOT

# Stack manipulation
DUP DROP SWAP OVER ROT

# List operations
SUM LEN HEAD TAIL CONS CONCAT

# Higher-order (take a block and a list)
FILTER MAP

# Iteration
TIMES WHILE
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

### Functions and Contracts

```
# Define a function with a type signature
DEF double : int -> int
  DUP ADD
END

5 double    # [10]

# POST contracts — checked at runtime on every call
DEF safe_div : int int -> int
  DIV
  POST DUP 0 GTE
END

# Violating a contract raises Axiom.ContractError
```

### Comments

```
# This is a comment
42 # inline comment
```

## Examples

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

## Architecture

```
 source.ax
    │
    ▼
 Lexer ──→ tokens ──→ Parser ──→ functions + expressions
                                        │
                                        ▼
                                  Evaluator (stack-based interpreter)
                                        │
                                  Axiom.Runtime (operator implementations)
                                        │
                                  Contract checker (POST assertions)
                                        │
                                     result
```

Runs on the BEAM via Elixir. The content-addressed DAG (ETS-backed) is in place for future use in multi-agent workflows and compilation to BEAM bytecode.

## Roadmap

- **v0.0.1** (current): Interpreter, contracts, REPL, TIMES/WHILE loops
- **v0.1.0**: Constraint solver / declarative mode
- **v0.2.0**: Tensor, embedding, and distribution primitives
- **v0.3.0**: Multi-agent collaboration via OTP
- **Future**: Compilation to BEAM bytecode via Erlang Abstract Format

## Requirements

- Elixir >= 1.12
- Erlang/OTP >= 24
