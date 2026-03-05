# Chapter 08: Native Tests First

Before the night crew is dismissed, the chief recorder reads yesterday's corrections out loud. Not to shame anyone. To remind everyone that memory is a poor control system. A city survives by writing down what must remain true.

Chapter 8 puts that habit into Runewarden with native Cairn tests.

Create:

```text
book/code/runewarden/chapters/ch08_native_tests_first/
  test.crn
  lib/
    domain.crn
    shift.crn
    ingest.crn
```

Copy `domain.crn`, `shift.crn`, and `ingest.crn` from Chapter 7 into this chapter's `lib/` directory.

Now write `test.crn`:

```cairn
IMPORT "lib/ingest.crn"
IMPORT "lib/shift.crn"

TEST "parse cave_in line keeps kind and magnitude semantics"
  "cave_in,9" parse_incident_line
  DUP incident_name
  "cave_in" ASSERT_EQ
  incident_score
  27 ASSERT_EQ
END

TEST "parse_incident_lines skips blanks and trims spacing"
  "cave_in,9\n\n gas_leak,3 \n" parse_incident_lines
  LEN
  2 ASSERT_EQ
END

TEST "missing input file falls back to empty incident list"
  "book/code/runewarden/chapters/ch08_native_tests_first/data/does_not_exist.txt" load_incidents_or_empty
  LEN
  0 ASSERT_EQ
END

TEST "parsed shift keeps summary invariants"
  "cave_in,9\ngas_leak,3\nrune_flare,2\ngas_leak,1" parse_incident_lines LET incidents
  incidents shift_total_score
  43 ASSERT_EQ
  incidents shift_max_score
  27 ASSERT_EQ
  incidents shift_crimson_count
  2 ASSERT_EQ
END

TEST "alert grouping counts cover all parsed incidents"
  "cave_in,9\ngas_leak,3\nrune_flare,2\ngas_leak,1" parse_incident_lines LET incidents
  incidents shift_alert_count_pairs LET grouped
  grouped LEN
  3 ASSERT_EQ
END
```

Run tests with:

```bash
./cairn --test book/code/runewarden/chapters/ch08_native_tests_first/test.crn
```

You should get five passes and a summary.

`TEST` blocks run only in explicit test mode. During normal file execution they are ignored. That lets us keep tests close to the chapter code without changing runtime behavior for non-test runs.

There are two stack details worth noticing in these tests. First, `ASSERT_EQ` expects the computed value to be pushed first and the expected value second. Second, when we need two checks from one parsed incident, we use `DUP` before consuming the value in the first assertion.

These tests are small, but they lock real behavior: parsing shape, whitespace handling, fallback behavior, and summary math. The immediate benefit is confidence. The longer-term benefit is freedom to refactor Chapter 7 code without fear.

Chapter 9 will broaden this from concrete examples to property checks with `VERIFY`, where we test invariants across many generated cases instead of a fixed handful of inputs.
