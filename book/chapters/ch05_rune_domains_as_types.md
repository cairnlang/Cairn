# Chapter 05: Rune Domains As Types

In the west archive, older ledgers are written in a cramped hand that trusts no one. Every line encodes its own meaning with tiny marks in the margin: a split-rune for flare events, a broken pick for cave-ins, a circle for gas warnings. The scribes did this because plain numbers drift. Symbols hold shape.

Runewarden is at that same turning point. We can keep passing raw integers and strings, or we can make the domain explicit.

Chapter 5 introduces algebraic data types. We will model incidents as real variants, then use `MATCH` to process them.

Create:

```text
book/code/runewarden/chapters/ch05_rune_domains_as_types/
  main.crn
  lib/
    domain.crn
```

Put this in `lib/domain.crn`:

```cairn
TYPE incident = CaveIn int | GasLeak int | RuneFlare int
TYPE alert = Green | Amber | Crimson

DEF incident_name : incident -> str
  MATCH
    CaveIn { DROP "cave_in" }
    GasLeak { DROP "gas_leak" }
    RuneFlare { DROP "rune_flare" }
  END
END

DEF incident_score : incident -> int
  MATCH
    CaveIn { 3 MUL }
    GasLeak { 2 MUL }
    RuneFlare { 4 MUL }
  END
END

DEF incident_alert : incident -> alert
  incident_score
  DUP 7 GTE
  IF
    DROP Crimson
  ELSE
    DUP 4 GTE
    IF
      DROP Amber
    ELSE
      DROP Green
    END
  END
END

DEF alert_text : alert -> str
  MATCH
    Green { "green" }
    Amber { "amber" }
    Crimson { "crimson" }
  END
END

DEF describe_incident : incident -> str
  DUP incident_name LET name
  DUP incident_score LET score
  incident_alert alert_text LET level
  level score name "incident={} score={} alert={}" FMT
END
```

Now `main.crn`:

```cairn
IMPORT "lib/domain.crn"

"Runewarden v0.1: typed incident ledger online." SAID

9 CaveIn describe_incident SAID
3 GasLeak describe_incident SAID
2 RuneFlare describe_incident SAID
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch05_rune_domains_as_types/main.crn
```

You should get three lines with names, scores, and alert levels.

This chapter's gain is not syntax novelty. It is shape. An `incident` is now one of three explicit forms, not a loose code hidden in comments. The checker can now enforce that `MATCH` arms cover the whole domain.

There is one stack detail worth keeping in your head. In a `MATCH` arm like `CaveIn { ... }`, the constructor field is pushed before the arm body runs. That is why `incident_score` can multiply immediately, and why `incident_name` drops the numeric payload before returning a string label.

From this point on, Runewarden code can talk in domain nouns instead of raw flags. Chapter 6 will put these typed values through collection pipelines so we can summarize whole shifts, not just single incidents.
