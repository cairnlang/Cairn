# Chapter 13: Error Flows With Result Helpers

In the dispatch room, bad news travels faster than good news. A broken intake pipe, a missing shift sheet, a cart that never arrived. The question is never whether failure exists. The question is whether the reporting path stays readable when failure appears.

Chapter 13 tightens that path in Runewarden.

In Chapter 12, the shell used fallback wrappers directly. It worked, but it hid error context. Here we keep the same behavior and make the error flow explicit with result combinators.

Create:

```text
book/code/runewarden/chapters/ch13_error_flows_with_result_helpers/
  main.crn
  data/
    shift_day_003.txt
  lib/
    core.crn
    shell.crn
```

`lib/core.crn` is the same pure module from Chapter 12.

Use this input file:

```text
cave_in,6
gas_leak,2
rune_flare,3
```

Now `lib/shell.crn`:

```cairn
IMPORT "core.crn"

DEF parse_file_text : str -> result[[incident] str] EFFECT io
  READ_FILE
  { parse_incident_lines Ok } result_and_then
  { "cannot load incidents: {}" FMT } result_map_err
END

DEF emit_load_warning_if_any : result[[incident] str] -> void EFFECT io
  MATCH
    Ok { DROP }
    Err { "warn={}" FMT SAID }
  END
END

DEF load_incidents_with_fallback : str -> [incident] EFFECT io
  parse_file_text LET loaded
  loaded emit_load_warning_if_any
  [] loaded result_unwrap_or
END

DEF emit_shift_summary : [incident] str -> void EFFECT io
  LET incidents
  LET source_path

  source_path "Runewarden v0.5: source={}" FMT SAID
  incidents LEN "incident_count={}" FMT SAID
  incidents shift_total_score "total_score={}" FMT SAID
  incidents shift_max_score "max_score={}" FMT SAID
  incidents shift_crimson_count "crimson_count={}" FMT SAID
  incidents shift_alert_count_pairs "grouped_by_alert={}" FMT SAID
END
```

And `main.crn`:

```cairn
IMPORT "lib/shell.crn"

ARGV LEN 0 GT
IF
  ARGV HEAD
ELSE
  "book/code/runewarden/chapters/ch13_error_flows_with_result_helpers/data/shift_day_003.txt"
END
LET source_path

source_path load_incidents_with_fallback LET incidents
source_path incidents emit_shift_summary
```

Run the normal path:

```bash
./cairn book/code/runewarden/chapters/ch13_error_flows_with_result_helpers/main.crn
```

Run a missing-file path:

```bash
./cairn book/code/runewarden/chapters/ch13_error_flows_with_result_helpers/main.crn \
  book/code/runewarden/chapters/ch13_error_flows_with_result_helpers/data/missing.txt
```

You should see a warning line and then a safe empty summary instead of a crash.

The important improvement is shape. `parse_file_text` keeps parsing and error rewriting in one linear result pipeline. `emit_load_warning_if_any` is the single side-effect point for errors. `load_incidents_with_fallback` chooses the fallback list in one expression.

This stays readable under failure because each step has one job. Transform success values. Rewrite error values. Emit optional warning. Unwrap with fallback.

Chapter 14 will start extracting these recurring patterns into shared prelude-style helpers so future modules do not keep rewriting the same glue.
