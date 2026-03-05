# Chapter 03: Functions And Contracts

At noon the rune chamber closes for ten minutes. No casting, no hauling, no shouting through the brass pipes. The senior runepriest walks the line with a wax tablet and asks the same question at every station: what must always be true before this step begins, and what must always be true when it ends.

In Cairn, that question is not philosophy. It is syntax.

So far we have written linear scripts. They run, but they do not scale. As soon as a calculation appears twice, we need a named function. As soon as a bad input can leak into a critical path, we need a contract.

Start a new chapter file:

```text
book/code/runewarden/chapters/ch03_functions_and_contracts/main.crn
```

Put this in it:

```cairn
DEF clamp_risk : int -> int
  PRE { DUP 0 GTE }
  DUP 10 GT
  IF
    DROP 10
  END
  POST DUP 0 GTE SWAP 10 LTE AND
END

DEF classify_alert : int -> str
  PRE {
    DUP 0 GTE
    SWAP 10 LTE
    AND
  }
  DUP 7 GTE
  IF
    DROP "high"
  ELSE
    DUP 4 GTE
    IF
      DROP "elevated"
    ELSE
      DROP "low"
    END
  END
END

"Runewarden: contract drill." SAID

12 clamp_risk LET risk_a
risk_a "risk_a={}" FMT SAID
risk_a classify_alert "alert_a={}" FMT SAID

5 clamp_risk LET risk_b
risk_b "risk_b={}" FMT SAID
risk_b classify_alert "alert_b={}" FMT SAID
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch03_functions_and_contracts/main.crn
```

You should see `risk_a=10` and `alert_a=high`, then `risk_b=5` and `alert_b=elevated`.

The first function, `clamp_risk`, gives us our first useful boundary. It says: I only accept non-negative input. I always return a value between `0` and `10`.

The body enforces the upper bound. The contracts state the boundary in executable form. This is important: the contract is not a comment. It runs.

The second function, `classify_alert`, is stricter. Its `PRE` requires that the input is already clamped. That means `classify_alert` can stay focused on classification logic and skip defensive cleanup.

This split is a practical pattern. One function normalizes raw inputs. The next function assumes normalized inputs and does domain work.

To see contracts fail, create a small companion file:

```text
book/code/runewarden/chapters/ch03_functions_and_contracts/failure.crn
```

```cairn
DEF classify_alert : int -> str
  PRE {
    DUP 0 GTE
    SWAP 10 LTE
    AND
  }
  DUP 7 GTE
  IF
    DROP "high"
  ELSE
    DUP 4 GTE
    IF
      DROP "elevated"
    ELSE
      DROP "low"
    END
  END
END

12 classify_alert
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch03_functions_and_contracts/failure.crn
```

You should get a contract error, because `12` violates the function's precondition.

That failure is not noise. It is the language telling us exactly where the domain boundary was crossed.

Chapter 4 will turn these helpers into the first real `Runewarden` module layout so we can stop writing everything in one file.
