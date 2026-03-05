# Chapter 09: Property Checks With Verify

Some failures never appear in the same way twice. A tunnel support bends only when heat, load, and timing align. The old foremen knew this long before software existed. They did not trust one example. They trusted repeated stress under varying conditions.

Chapter 9 brings that habit into Runewarden with `VERIFY`.

`TEST` gave us concrete examples. `VERIFY` checks a function's contract over many generated inputs. It is still bounded, but it searches much wider space than hand-written cases.

Create:

```text
book/code/runewarden/chapters/ch09_property_checks_with_verify/
  verify.crn
  lib/
    risk_props.crn
```

Write `lib/risk_props.crn`:

```cairn
DEF clamp_risk : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  DUP 10 GT
  IF
    DROP 10
  END
  POST DUP 0 GTE SWAP 10 LTE AND
END

DEF risk_band : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  clamp_risk
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

DEF risk_band_known : int -> bool EFFECT pure
  PRE { DUP 0 GTE }
  risk_band
  DUP 0 GTE SWAP 2 LTE AND
  POST DUP
END

DEF clamp_idempotent_gap : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  DUP
  clamp_risk
  SWAP
  clamp_risk
  SUB
  POST DUP 0 EQ
END
```

Now `verify.crn`:

```cairn
IMPORT "lib/risk_props.crn"

VERIFY clamp_risk 80
VERIFY risk_band 80
VERIFY risk_band_known 80
VERIFY clamp_idempotent_gap 80
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch09_property_checks_with_verify/verify.crn
```

You should see each property reported as `OK`, with pass counts and skip counts.

Skip counts come from preconditions. `VERIFY` generates candidate inputs, but only keeps cases that satisfy `PRE`. In this chapter all four properties require non-negative input, so negative candidates are skipped.

The four properties cover different failure shapes. `clamp_risk` checks range. `risk_band` checks classification output bounds. `risk_band_known` checks that classification always lands in the known band set. `clamp_idempotent_gap` checks an algebraic law: clamping twice is the same as clamping once.

That last pattern is worth keeping. Algebraic laws are often more durable than hand-picked examples. They survive refactors because they speak about behavior shape, not implementation details.

Chapter 10 will shift from randomized checking to symbolic proof attempts with `PROVE`, and we will be explicit about where that proof surface ends.
