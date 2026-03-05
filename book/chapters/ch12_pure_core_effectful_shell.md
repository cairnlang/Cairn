# Chapter 12: Pure Core Effectful Shell

In the old foundry, every machine has two spaces around it. The inner ring is clean and measured: gears, tolerances, repeatable motion. The outer ring is soot, heat, and workers carrying ore in from the world. The craft is not pretending those two spaces are the same. The craft is designing the seam between them.

Chapter 12 does exactly that for Runewarden.

We have enough code now that effect boundaries matter. Parsing and scoring logic should stay pure and testable. File reads and terminal output should stay at the edge.

Create:

```text
book/code/runewarden/chapters/ch12_pure_core_effectful_shell/
  main.crn
  data/
    shift_day_002.txt
  lib/
    core.crn
    shell.crn
```

Use this input file:

```text
cave_in,8
gas_leak,4
rune_flare,1
```

Put pure domain logic in `lib/core.crn`:

```cairn
TYPE incident = CaveIn int | GasLeak int | RuneFlare int
TYPE alert = Green | Amber | Crimson

DEF incident_name : incident -> str EFFECT pure
  MATCH
    CaveIn { DROP "cave_in" }
    GasLeak { DROP "gas_leak" }
    RuneFlare { DROP "rune_flare" }
  END
END

DEF incident_score : incident -> int EFFECT pure
  MATCH
    CaveIn { 3 MUL }
    GasLeak { 2 MUL }
    RuneFlare { 4 MUL }
  END
END

DEF incident_alert : incident -> alert EFFECT pure
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

DEF alert_text : alert -> str EFFECT pure
  MATCH
    Green { "green" }
    Amber { "amber" }
    Crimson { "crimson" }
  END
END

DEF parse_incident_line : str -> incident EFFECT pure
  "," SPLIT LET parts
  parts HEAD TRIM LOWER LET kind
  parts TAIL "," JOIN TRIM 0 SWAP to_int_or LET magnitude
  kind "cave_in" EQ
  IF
    magnitude CaveIn
  ELSE
    kind "gas_leak" EQ
    IF
      magnitude GasLeak
    ELSE
      magnitude RuneFlare
    END
  END
END

DEF parse_incident_lines : str -> [incident] EFFECT pure
  LINES
  { TRIM } MAP
  { LEN 0 GT } FILTER
  { parse_incident_line } MAP
END

DEF shift_total_score : [incident] -> int EFFECT pure
  { incident_score } MAP
  SUM
END

DEF shift_max_score : [incident] -> int EFFECT pure
  0 { incident_score MAX } REDUCE
END

DEF shift_crimson_count : [incident] -> int EFFECT pure
  { incident_alert Crimson EQ } FILTER
  LEN
END

DEF shift_incidents_by_alert : [incident] -> [tuple[str [incident]]] EFFECT pure
  { incident_alert alert_text } GROUP_BY
  PAIRS
END

DEF alert_group_pair_count : tuple[str [incident]] -> tuple[str int] EFFECT pure
  DUP FST LET level
  SND LEN LET count
  #( level count )
END

DEF shift_alert_count_pairs : [incident] -> [tuple[str int]] EFFECT pure
  shift_incidents_by_alert
  { alert_group_pair_count } MAP
END
```

Now the effectful edge in `lib/shell.crn`:

```cairn
IMPORT "core.crn"

DEF load_incidents_from_path : str -> [incident] EFFECT io
  "" SWAP read_file_or
  parse_incident_lines
END

DEF emit_shift_summary : [incident] str -> void EFFECT io
  LET incidents
  LET source_path

  source_path "Runewarden v0.4: source={}" FMT SAID
  incidents LEN "incident_count={}" FMT SAID
  incidents shift_total_score "total_score={}" FMT SAID
  incidents shift_max_score "max_score={}" FMT SAID
  incidents shift_crimson_count "crimson_count={}" FMT SAID
  incidents shift_alert_count_pairs "grouped_by_alert={}" FMT SAID
END
```

And the thin entrypoint in `main.crn`:

```cairn
IMPORT "lib/shell.crn"

ARGV LEN 0 GT
IF
  ARGV HEAD
ELSE
  "book/code/runewarden/chapters/ch12_pure_core_effectful_shell/data/shift_day_002.txt"
END
LET source_path

source_path load_incidents_from_path LET incidents
source_path incidents emit_shift_summary
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch12_pure_core_effectful_shell/main.crn
```

The architectural point is sharper than the output. `core.crn` has no I/O and can be tested, verified, or proved without transport concerns. `shell.crn` owns I/O and presentation sequencing. `main.crn` wires the boundary and exits.

This boundary buys two things immediately: confidence and replaceability. Confidence comes from being able to exercise pure logic in isolation. Replaceability comes from being able to swap the shell later, for web handlers or actor messages, without rewriting the core.

Chapter 13 will improve error flow at that boundary by using result combinators so effectful code stays linear instead of collapsing into nested branching.
