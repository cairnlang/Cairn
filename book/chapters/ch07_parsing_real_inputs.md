# Chapter 07: Parsing Real Inputs

The night shift does not hand over clean data. It hands over a stained sheet tied with twine, half written in haste, full of abbreviations everyone swears are obvious. By dawn, that sheet has to become something the day crew can trust.

Chapter 7 is where Runewarden stops hardcoding incidents and starts reading them from a real file.

Create:

```text
book/code/runewarden/chapters/ch07_parsing_real_inputs/
  main.crn
  data/
    shift_day_001.txt
  lib/
    domain.crn
    shift.crn
    ingest.crn
```

`lib/domain.crn` and `lib/shift.crn` are the same modules from Chapter 6.

Use this input file:

```text
cave_in,9
gas_leak,3
rune_flare,2
gas_leak,1
```

Now add `lib/ingest.crn`:

```cairn
IMPORT "domain.crn"

DEF parse_incident_line : str -> incident
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

DEF parse_incident_lines : str -> [incident]
  LINES
  { TRIM } MAP
  { LEN 0 GT } FILTER
  { parse_incident_line } MAP
END

DEF load_incidents_or_empty : str -> [incident] EFFECT io
  "" SWAP read_file_or
  parse_incident_lines
END
```

And `main.crn`:

```cairn
IMPORT "lib/ingest.crn"
IMPORT "lib/shift.crn"

ARGV LEN 0 GT
IF
  ARGV HEAD
ELSE
  "book/code/runewarden/chapters/ch07_parsing_real_inputs/data/shift_day_001.txt"
END
LET source_path

source_path "Runewarden v0.3: reading shift file {}" FMT SAID

source_path load_incidents_or_empty LET incidents

incidents LEN "incident_count={}" FMT SAID
incidents shift_total_score "total_score={}" FMT SAID
incidents shift_max_score "max_score={}" FMT SAID
incidents shift_crimson_count "crimson_count={}" FMT SAID
incidents shift_alert_count_pairs "grouped_by_alert={}" FMT SAID
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch07_parsing_real_inputs/main.crn
```

The parser path is intentionally small and direct. A line is split at the comma. The left side becomes a kind tag. The right side is trimmed and parsed to integer with `to_int_or`, which falls back to `0` if parsing fails.

That fallback is a deliberate compromise for this chapter. We are wiring the ingestion path first. We are not doing full validation policy yet. Chapter 8 will introduce tests around this parser so we can tighten behavior without guesswork.

The two helper layers are now visible. `ingest.crn` turns text into typed incidents. `shift.crn` turns typed incidents into summaries. Keeping those layers separate is what lets us improve one without breaking the other.
