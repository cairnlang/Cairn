# Chapter 04: Project Skeleton Runewarden V0

By late afternoon, Ironhold's record hall changes character. The noise does not drop, but it becomes organized. Clay tablets move from one shelf to another. Copper tags are sorted by district. A clerk with black ink on both hands mutters the same warning to new apprentices: if you keep everything in one pile, the pile becomes the system.

Chapter 4 is where we stop writing piles.

In the first three chapters, one file was enough. Now we have enough behavior to justify structure. We will split `Runewarden` into small modules and keep `main.crn` as a thin entrypoint.

Create this directory tree:

```text
book/code/runewarden/chapters/ch04_project_skeleton_runewarden_v0/
  main.crn
  lib/
    risk.crn
    report.crn
```

Start with `lib/risk.crn`:

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
```

Now `lib/report.crn`:

```cairn
IMPORT "risk.crn"

DEF shift_summary_line : str int -> str
  LET mine_name
  clamp_risk LET bounded_risk
  bounded_risk classify_alert LET alert_level
  alert_level bounded_risk mine_name "mine={} risk={} alert={}" FMT
END

DEF print_shift_summary : str int -> void
  shift_summary_line SAID
END
```

And `main.crn`:

```cairn
IMPORT "lib/report.crn"

"Runewarden v0: module skeleton online." SAID

12 "north-deep" print_shift_summary
5 "river-gate" print_shift_summary
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch04_project_skeleton_runewarden_v0/main.crn
```

You should see two summary lines, both produced by imported helpers.

The shape matters more than the output. `main.crn` now reads like an entrypoint instead of a workshop bench. Domain logic lives in `risk.crn`. Presentation logic lives in `report.crn`. This is still a tiny project, but it has begun to separate concerns in a way that can survive growth.

Notice one import detail: `report.crn` imports `"risk.crn"` without a folder prefix. That works because both files are in the same `lib/` directory. `main.crn` imports `"lib/report.crn"` because it sits one level above.

This is enough structure for chapter four. We are not inventing architecture yet. We are only making sure new behavior has a place to go.

Chapter 5 will use this skeleton to introduce richer domain types so `Runewarden` can carry more meaning than raw integers and strings.
