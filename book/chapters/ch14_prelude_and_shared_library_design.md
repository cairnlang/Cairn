# Chapter 14: Prelude And Shared Library Design

When the first guild of stonecutters took apprentices, they taught an odd rule. If you repeat the same chisel movement three times in one panel, stop and carve a guide line instead. The guide line is not ornament. It is how the wall begins to look intentional.

Chapter 14 is that guide line for Runewarden.

You noticed it already in Chapter 13: the code started to look less like a stack puzzle and more like application prose. Here we make that transition explicit by extracting shared helpers and letting `main.crn` read like a sentence.

Create:

```text
book/code/runewarden/chapters/ch14_prelude_and_shared_library_design/
  main.crn
  data/
    shift_day_004.txt
  lib/
    core.crn
    shell.crn
    shared.crn
```

`lib/core.crn` stays the same pure module from Chapter 13.

Use this input file:

```text
gas_leak,5
rune_flare,2
cave_in,4
```

Add `lib/shared.crn`:

```cairn
# Chapter-local shared helpers. This is the first step toward a project prelude.

DEF argv_head_or : str -> str EFFECT io
  LET fallback
  ARGV LEN 0 GT
  IF
    ARGV HEAD
  ELSE
    fallback
  END
END
```

Refine `lib/shell.crn` by keeping Chapter 13 error flow and adding one composed helper:

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

  source_path "Runewarden v0.6: source={}" FMT SAID
  incidents LEN "incident_count={}" FMT SAID
  incidents shift_total_score "total_score={}" FMT SAID
  incidents shift_max_score "max_score={}" FMT SAID
  incidents shift_crimson_count "crimson_count={}" FMT SAID
  incidents shift_alert_count_pairs "grouped_by_alert={}" FMT SAID
END

DEF run_shift_report : str -> void EFFECT io
  DUP load_incidents_with_fallback
  emit_shift_summary
END
```

Now look at `main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/shell.crn"

"book/code/runewarden/chapters/ch14_prelude_and_shared_library_design/data/shift_day_004.txt"
argv_head_or
run_shift_report
```

Run the default path:

```bash
./cairn book/code/runewarden/chapters/ch14_prelude_and_shared_library_design/main.crn
```

Run with a missing file:

```bash
./cairn book/code/runewarden/chapters/ch14_prelude_and_shared_library_design/main.crn \
  book/code/runewarden/chapters/ch14_prelude_and_shared_library_design/data/missing.txt
```

You will get the same safe behavior as Chapter 13, but the entrypoint now reads cleanly. Default path, maybe override from argv, run the report. That is the aesthetic gain you pointed out, now made deliberate.

This is the beginning of project-level prelude design. Not a global framework, just a small shared vocabulary that removes repeated ceremony from app code while keeping boundaries explicit.

Chapter 15 will use this cleaned shape as we cross into the first web endpoint and start serving the same reporting flow over HTTP.
