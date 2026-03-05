# Chapter 11: Assurance Workflow

On inspection days, Ironhold does not send one specialist. It sends three. One checks recent incidents against known cases. One stress-tests systems under varying conditions. One does formal sign-off on the parts that can be certified. They overlap on purpose, because each one catches a different class of error.

Chapter 11 turns that pattern into a repeatable Runewarden workflow.

We now have three assurance tools. The mistake is to treat them as rivals. They are a sequence.

Create:

```text
book/code/runewarden/chapters/ch11_assurance_workflow/
  test.crn
  verify.crn
  prove.crn
  run_assurance.sh
  lib/
    workflow.crn
```

Write `lib/workflow.crn`:

```cairn
DEF clamp_to_ten : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  DUP 10 GT
  IF
    DROP 10
  END
  POST DUP 0 GTE SWAP 10 LTE AND
END

DEF risk_band : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  clamp_to_ten
  DUP 7 GTE
  IF
    DROP 2
  ELSE
    DUP 4 GTE
    IF
      DROP 1
    ELSE
      DROP 0
    END
  END
  POST DUP 0 GTE SWAP 2 LTE AND
END

DEF risk_band_with_let : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  clamp_to_ten LET score
  score 7 GTE
  IF
    2
  ELSE
    score 4 GTE
    IF
      1
    ELSE
      0
    END
  END
  POST DUP 0 GTE SWAP 2 LTE AND
END

DEF risk_label : int -> str EFFECT pure
  PRE { DUP 0 GTE SWAP 2 LTE AND }
  DUP 2 EQ
  IF
    DROP "crimson"
  ELSE
    DUP 1 EQ
    IF
      DROP "amber"
    ELSE
      DROP "green"
    END
  END
END

DEF risk_label_for_score : int -> str EFFECT pure
  PRE { DUP 0 GTE }
  risk_band_with_let
  risk_label
END

DEF risk_label_known : int -> bool EFFECT pure
  PRE { DUP 0 GTE }
  clamp_to_ten
  risk_band
  risk_label
  DUP "green" EQ
  OVER "amber" EQ OR
  SWAP "crimson" EQ OR
  POST DUP
END

DEF risk_label_for_score_known : int -> bool EFFECT pure
  PRE { DUP 0 GTE }
  risk_label_known
  POST DUP
END

DEF clamp_idempotent_gap : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  DUP
  clamp_to_ten
  SWAP
  clamp_to_ten
  SUB
  POST DUP 0 EQ
END
```

Now `test.crn`:

```cairn
IMPORT "lib/workflow.crn"

TEST "score above ten still maps to crimson"
  12 risk_label_for_score
  "crimson" ASSERT_EQ
END

TEST "mid score maps to amber"
  5 risk_label_for_score
  "amber" ASSERT_EQ
END

TEST "small score maps to green"
  1 risk_label_for_score
  "green" ASSERT_EQ
END

TEST "clamping remains idempotent for concrete score"
  9 clamp_idempotent_gap
  0 ASSERT_EQ
END
```

`verify.crn`:

```cairn
IMPORT "lib/workflow.crn"

VERIFY clamp_to_ten 80
VERIFY risk_band 80
VERIFY risk_label_known 80
VERIFY risk_label_for_score_known 80
VERIFY clamp_idempotent_gap 80
```

`prove.crn`:

```cairn
IMPORT "lib/workflow.crn"

PROVE clamp_to_ten
PROVE risk_band
PROVE risk_band_with_let
PROVE clamp_idempotent_gap
```

And a helper script:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="book/code/runewarden/chapters/ch11_assurance_workflow"

echo "[1/3] native tests"
./cairn --test "$ROOT/test.crn"

echo "[2/3] property checks"
./cairn "$ROOT/verify.crn"

echo "[3/3] proofs"
./cairn "$ROOT/prove.crn"
```

Run the full sequence:

```bash
book/code/runewarden/chapters/ch11_assurance_workflow/run_assurance.sh
```

You should see tests pass, properties pass, and proofs return a mixed result: three `PROVEN` and one `UNKNOWN` for the `LET`-based function.

That mixed result is healthy. It tells us the workflow is doing what it should do. Concrete behavior is locked by tests. Invariants are stressed by property checks. Proof-friendly kernel functions are certified where the solver applies. The remainder is still covered by the first two layers.

This is the operating model we will carry forward into web, persistence, and concurrency chapters. Chapter 12 will start the architectural side of that model by separating pure core logic from effectful boundaries.
