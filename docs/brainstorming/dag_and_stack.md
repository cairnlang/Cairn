This is a fascinating language design problem. Because stack languages are concatenative (functions compose by juxtaposition), they look linear, but data flow is implicit.

To answer your immediate questions:
1.  **Is a DAG needed?** Practically, **yes**. You need a Data Flow Graph (DFG) to perform robust type inference and constraint solving.
2.  **Can you even have a DAG?** **Yes.** In fact, under the hood, a stack program *is* a DAG. The stack is just a serialization format for that graph.

Here is the architectural breakdown of what you need to add Type Inference and Constraint Solving to a stack language.

---

### 1. The Mathematical Foundation: Row Polymorphism
Standard Hindley-Milner type inference (used in Haskell/OCaml) assumes you are inferring types for named variables. In a stack language, you must infer the state of the *entire stack*.

To do this, you need **Row Polymorphism**. You cannot just describe the top of the stack; you must describe the "rest" of the stack.

*   **Standard Type:** `Int -> Int`
*   **Stack Type:** `( S -- S' )`
*   **Inference Type:** `( ρ, Int -- ρ, Int )`

Here, `ρ` (rho) is a **Row Variable** representing "whatever was on the stack before."
*   `push 5` has the effect: `∀ρ. ( ρ -- ρ, Int )`
*   `add` has the effect: `∀ρ. ( ρ, Int, Int -- ρ, Int )`

**The "DAG" Connection:**
When you compose functions, you unify the output row of function A with the input row of function B. This chain of unifications creates the edges of your inference graph.

---

### 2. The Intermediate Representation: Stack-to-SSA (The DAG)
To support native constraint solving (e.g., "x must be prime"), you need to give names to values so the solver can track them. A raw stack is too transient for this.

You must compile the stack operations into a **Data Flow Graph** (which is a DAG for straight-line code) using **Static Single Assignment (SSA)** form.

**Example Source:**
```forth
dup * 10 >
```

**Step 1: Simulation (Symbolic Execution)**
You run a simulator at compile time. The simulator has a compile-time stack containing symbolic variables (Nodes in your DAG).

1.  *Start:* Stack = `[ρ0, v0]`
2.  `dup`: Consumes `v0`. Pushes `v0`, `v0`.
    *   *DAG Node:* `n1 = dup(v0)` (conceptually just a fork)
    *   Stack = `[ρ0, v0, v0]`
3.  `*`: Consumes `v0`, `v0`. Produces `v1`.
    *   *DAG Node:* `v1 = mul(v0, v0)`
    *   Stack = `[ρ0, v1]`
4.  `10`: Pushes literal.
    *   *DAG Node:* `v2 = const(10)`
    *   Stack = `[ρ0, v1, v2]`
5.  `>`: Consumes `v1`, `v2`. Produces `v3`.
    *   *DAG Node:* `v3 = gt(v1, v2)`
    *   Stack = `[ρ0, v3]`

**The Resulting DAG:**
```text
v0 ──┬──> [MUL] ──> v1 ──┬──> [GT] ──> v3
     └──> [MUL]          │
          [10] ──────────┘
```
**Why this is necessary:** Constraint solvers (like Z3 or a custom solver) work on logical formulas. They need to know that the input to `>` is the result of `*`. The DAG makes this relationship explicit.

---

### 3. Handling Control Flow (Phi Nodes)
If your language has branches (`if/else`), it is no longer a simple DAG; it is a Control Flow Graph (CFG) of DAGs.

When branches merge, you must reconcile the stacks.
*   **True branch:** Stack ends with `[ρ, A]`
*   **False branch:** Stack ends with `[ρ, B]`
*   **Merge point:** Stack is `[ρ, C]` where `C = φ(A, B)`.

For type inference, you unify `Type(A)` and `Type(B)`.
For constraint solving, you assert `(Condition => C=A) && (!Condition => C=B)`.

---

### 4. The Constraint Solver (Refinement Types)
You mentioned "enforceable contracts." This usually implies **Refinement Types** (types with predicates).
*   Type: `Int`
*   Contract: `{v : Int | v > 0}`

To implement this "native constraint solving":

1.  **Collection:** Traverse your DAG. For every edge and node, collect constraints.
    *   From `dup *`: `v1 = v0 * v0`
    *   From user contract on input: `v0 > 5`
2.  **Translation:** Convert these DAG relationships into logical assertions (SMT-LIB format if using Z3, or internal logic).
3.  **Verification:**
    *   If the user has a post-condition `ensure top > 20`, you ask the solver:
        *   Given `v0 > 5` AND `v1 = v0 * v0`, is `v1 > 20` always true?
        *   (In this case, yes, because $6^2 = 36$).

---

### 5. Bi-directional Type Checking
To make inference ergonomic (so users don't have to annotate everything), you should use **Bi-directional Type Checking**.

1.  **Synthesize (Infers out):** Start with the leaves (literals, known functions) and bubble types up the DAG to infer the type of the resulting expression.
2.  **Check (Pushes in):** If a function defines a contract `( Int -- Bool )`, push that expectation *down* into the implementation.

**Example Scenario:**
Function `foo` expects an Odd number.
```forth
: foo ( x:Odd -- ) ... ;
: main 2 1 + foo ;
```
1.  Inference sees `2` (Int), `1` (Int).
2.  `+` produces `Int`.
3.  `foo` expects `Odd`.
4.  The Constraint Solver receives: `v1=2, v2=1, v3=v1+v2`. It must prove `IsOdd(v3)`.
5.  Solver proves `3` is Odd. Type check passes.

---

### Summary of Requirements

To add these features to your stack language, you need to build:

1.  **The Symbolic Stack:** A compiler structure that mimics the runtime stack but holds *Type Variables* and *AST Nodes* instead of values.
2.  **The Unification Engine:** To resolve Row Variables (ensuring stack depths match) and Type Variables (ensuring `Int` flows into `Int`).
3.  **The DAG Builder:** Converts linear tokens into an explicit graph of operations.
4.  **The SMT/Constraint Interface:** To take the graph + contracts and verify validity.

**Can you do it without a DAG?**
Technically, you could try to do it via complex term rewriting on the linear list, but it will be incredibly slow and difficult to reason about. Converting the linear stack operations into a Graph/DAG is the industry standard way (used in Java Bytecode verification, WebAssembly validation, and optimizing Forth compilers) to solve this problem.
