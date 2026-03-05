# Chapter 10: Proofs With Prove And Limits

At the deepest level of Ironhold, there is a wall no one decorates. It is plain stone, carved only with checks. Each line marks a machine that was inspected and judged safe to run under known limits. Not "probably safe." Not "safe in yesterday's cases." Safe under the stated conditions.

Chapter 10 is the language version of that wall. We move from randomized confidence to symbolic proof attempts with `PROVE`.

`VERIFY` asks, "does this hold for many generated samples?" `PROVE` asks a stricter question: "can the solver show this contract holds for all values that satisfy `PRE`, within the supported proof surface?"

Create:

```text
book/code/runewarden/chapters/ch10_proofs_with_prove_and_limits/
  prove.crn
  lib/
    proofs.crn
```

Write `lib/proofs.crn`:

```cairn
DEF clamp_to_ten : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  DUP 10 GT
  IF
    DROP 10
  END
  POST DUP 0 GTE SWAP 10 LTE AND
END

DEF score_band : int -> int EFFECT pure
  PRE { DUP 0 GTE SWAP 10 LTE AND }
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

DEF score_band_with_let : int -> int EFFECT pure
  PRE { DUP 0 GTE SWAP 10 LTE AND }
  LET score
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
```

Now `prove.crn`:

```cairn
IMPORT "lib/proofs.crn"

PROVE clamp_to_ten
PROVE score_band
PROVE score_band_with_let
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch10_proofs_with_prove_and_limits/prove.crn
```

You should see two `PROVEN` lines and one `UNKNOWN` line.

This chapter is about reading that outcome correctly. `UNKNOWN` is not a failed proof. It means the current prover pipeline does not support some construct in the function body. In this example, the blocking construct is `LET`.

That distinction matters in engineering practice. `PROVEN` gives you a strong guarantee on the supported fragment. `UNKNOWN` tells you to fall back to `VERIFY` and `TEST` for that function, or to refactor the function into a proof-friendly shape.

Runewarden now has all three assurance instruments in view: example tests, property checks, and symbolic proofs. Chapter 11 will turn this into a working assurance workflow so we use each instrument at the right time instead of treating them as interchangeable.
