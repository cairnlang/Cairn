# Runewarden

_Generated on 2026-03-05 16:50:29 UTC_


---

# Chapter 01: Welcome to Ironhold

By sunrise, the slate board outside Shaft Three is already full. A foreman has chalked the night yield. A novice runepriest has marked two seals as unstable. Someone else has written, in larger letters than necessary, "do not light the west lattice until inspected." Ironhold calls this an ordinary morning.

Ordinary mornings need systems more than heroes. That is where `Runewarden` begins: a ledger that grows, chapter by chapter, into the nervous system of a dwarven city that would prefer not to explode.

For now, none of that matters. A first chapter needs one thing: a program that runs.

Make a file:

```text
book/code/runewarden/chapters/ch01_welcome_to_ironhold/main.crn
```

Put this in it:

```cairn
"Runewarden: shift ledger opening." SAID
"mine=North Deep" SAID
"status=green" SAID
```

Run it:

```bash
mix cairn.run book/code/runewarden/chapters/ch01_welcome_to_ironhold/main.crn
```

You should see three lines. That is enough to establish the basic loop: edit, run, observe. We will not leave that loop for the rest of the book.

The second thing to learn is that Cairn is postfix and stack-based. The value comes first. The operator comes after it. You can feel this in one line:

```cairn
2 3 ADD
```

The interpreter reads left to right. It pushes `2`, then `3`, then `ADD` pops both, adds them, and pushes the result back. When the program ends, remaining values on the stack are printed.

We can fold this into our chapter file:

```cairn
"Runewarden: shift ledger opening." SAID
"mine=North Deep" SAID
"status=green" SAID

2 3 ADD "sample_load={}" FMT SAID
```

Now we are doing two kinds of work. We emit lines to humans with `SAID`. We compute values on the stack and format them with `FMT`. This pair shows up everywhere in practical Cairn code.

To make the output react to input, we can read command-line arguments through `ARGV`. If the caller gives one argument, we will treat it as the shift scribe. Otherwise we default to `apprentice`.

```cairn
ARGV LEN 0 GT
IF
  ARGV HEAD
ELSE
  "apprentice"
END
LET scribe

scribe "scribe={}" FMT SAID
```

This is our first conditional that matters. A chapter one program is still allowed to branch as long as the branch stays obvious. If arguments exist, pick the first one. If not, use a stable fallback. No magic.

If you are new to stack languages, read this block once as stack motion, not as "syntax." Assume the command was run with no extra arguments.

`ARGV` pushes the argument list. With no extras, that list is `[]`.

`LEN` pops that list and pushes its length, so the stack now holds `0`.

`0 GT` compares the two numbers on top of the stack. In this case it asks whether `0 > 0`, which is `FALSE`.

`IF ... ELSE ... END` now consumes that boolean and runs the `ELSE` branch, pushing `"apprentice"`.

`LET scribe` pops `"apprentice"` and binds it to the name `scribe`.

The stack is empty again, but the environment now contains `scribe = "apprentice"`.

Run the same logic with `dorin` as one argument and only two moments change. `ARGV` starts as `["dorin"]`, so `LEN` produces `1`, and `1 0 GT` is `TRUE`. The `IF` branch runs, `ARGV HEAD` pushes `"dorin"`, and `LET scribe` binds that value instead.

This is the core habit for reading Cairn: watch what each word removes, what it leaves behind, and when a value moves from stack to name.

Put everything together:

```cairn
"Runewarden: shift ledger opening." SAID
"mine=North Deep" SAID
"status=green" SAID

2 3 ADD "sample_load={}" FMT SAID

ARGV LEN 0 GT
IF
  ARGV HEAD
ELSE
  "apprentice"
END
LET scribe

scribe "scribe={}" FMT SAID
```

Run it both ways:

```bash
mix cairn.run book/code/runewarden/chapters/ch01_welcome_to_ironhold/main.crn
mix cairn.run book/code/runewarden/chapters/ch01_welcome_to_ironhold/main.crn dorin
```

You should see `scribe=apprentice` in the first run and `scribe=dorin` in the second.

Nothing here is grand. That is exactly the point. We now have the first stone in place: a real program in a real project directory, with input, output, arithmetic, formatting, and a controlled fallback.

In the next chapter we will slow down and look directly at stack movement. If you do not learn to see the stack, you can still write Cairn, but you will write it with tension. We want the opposite. We want the calm feeling that comes when every value has a known place and every operator has a known effect.

---

# Chapter 02: Stacks Words And Postfix

The foreman in North Deep keeps two ledgers. One is for numbers. The other is for mistakes. The first grows every shift. The second grows whenever someone forgets what is on top of a stack.

If Chapter 1 proved that Cairn runs, Chapter 2 is where we learn to run Cairn without guessing.

In postfix code, each word does one thing to the stack. It either pushes a value, or it consumes values and pushes a result. You can read a line as a series of tiny before/after transformations.

Take this expression:

```cairn
12 3 MUL
```

Read it left to right:
`12` pushes `12`. `3` pushes `3`. `MUL` pops both and pushes `36`. The final stack contains `36`.

We can make this concrete inside `Runewarden`. Create:

```text
book/code/runewarden/chapters/ch02_stacks_words_and_postfix/main.crn
```

with:

```cairn
"Runewarden: stack drill begins." SAID

12 3 MUL LET ore_load
ore_load "ore_load={}" FMT SAID

ore_load 5 ADD LET reinforced_load
reinforced_load "reinforced_load={}" FMT SAID

reinforced_load DUP ADD LET twin_total
twin_total "twin_total={}" FMT SAID

"green" "north-deep" "shaft={} status={}" FMT SAID
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch02_stacks_words_and_postfix/main.crn
```

The first three numeric lines are a stack drill in slow motion.

`12 3 MUL LET ore_load` leaves no temporary values behind. `MUL` produces one value. `LET` consumes that value into a name. The stack is clear again.

`ore_load 5 ADD LET reinforced_load` does the same shape with a named value plus a literal.

`reinforced_load DUP ADD LET twin_total` adds one new operator. `DUP` copies the top value so `ADD` can consume two numbers. In plain terms, it doubles the current load.

The last line is the first place beginners usually stumble:

```cairn
"north-deep" "green" "shaft={} status={}" FMT SAID
```

`FMT` expects the format string on top. The placeholder values sit under it. The first `{}` gets the top value under the format string, which is `"green"` in this line. That means this exact line prints the wrong sentence for our intent.

To produce `shaft=north-deep status=green`, push values from right to left:

```cairn
"green" "north-deep" "shaft={} status={}" FMT SAID
```

Now the top value under the format string is `"north-deep"`, which lands in the first `{}`.

This is the stack habit in practice. When output is wrong, do not panic and rewrite the whole line. Check consumption order. Most early bugs in Cairn are order bugs, not logic bugs.

Chapter 3 will introduce function boundaries and contracts, so these small stack transformations can be named, reused, and checked.

---

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

---

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

---

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

---

# Chapter 06: Collections And Pipelines

By evening, the record hall has moved from single incidents to patterns. One cave-in is a problem. Three cave-ins in the same district is a warning. The dwarves who keep Ironhold alive do not read events one by one; they read flows.

Chapter 6 is where Runewarden starts doing the same.

We already have typed incidents. Now we need whole-shift summaries. That means list pipelines.

Create:

```text
book/code/runewarden/chapters/ch06_collections_and_pipelines/
  main.crn
  lib/
    domain.crn
    shift.crn
```

`lib/domain.crn` is the same typed incident module from Chapter 5.

Put this in `lib/shift.crn`:

```cairn
IMPORT "domain.crn"

DEF shift_total_score : [incident] -> int
  { incident_score } MAP
  SUM
END

DEF shift_max_score : [incident] -> int
  0 { incident_score MAX } REDUCE
END

DEF shift_crimson_count : [incident] -> int
  { incident_alert Crimson EQ } FILTER
  LEN
END

DEF shift_incident_names : [incident] -> [str]
  { incident_name } MAP
END

DEF shift_incidents_by_alert : [incident] -> [tuple[str [incident]]]
  { incident_alert alert_text } GROUP_BY
  PAIRS
END

DEF alert_group_pair_count : tuple[str [incident]] -> tuple[str int]
  DUP FST LET level
  SND LEN LET count
  #( level count )
END

DEF shift_alert_count_pairs : [incident] -> [tuple[str int]]
  shift_incidents_by_alert
  { alert_group_pair_count } MAP
END
```

Now `main.crn`:

```cairn
IMPORT "lib/shift.crn"

"Runewarden v0.2: shift pipeline report." SAID

[ 9 CaveIn 3 GasLeak 2 RuneFlare 1 GasLeak ]
LET incidents

incidents shift_total_score "total_score={}" FMT SAID
incidents shift_max_score "max_score={}" FMT SAID
incidents shift_crimson_count "crimson_count={}" FMT SAID
incidents shift_incident_names "incident_names={}" FMT SAID
incidents shift_alert_count_pairs "grouped_by_alert={}" FMT SAID
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch06_collections_and_pipelines/main.crn
```

You should see a total shift score, a maximum single-incident score, the number of crimson incidents, the incident names, and grouped counts by alert level.

The chapter's center is `REDUCE`:

```cairn
0 { incident_score MAX } REDUCE
```

Read it as: start with accumulator `0`; for each incident, turn it into a score and keep the larger of `(score, accumulator)`.

Inside the REDUCE block, the stack arrives with the current element on top and the current accumulator below it.

That is why `incident_score MAX` works directly. `incident_score` transforms the element on top into an integer score, and `MAX` compares it against the accumulator underneath.

The other helpers are the same pattern at different angles: transform (`MAP`), keep (`FILTER`), summarize (`LEN`, `SUM`), group (`GROUP_BY`), reshape (`PAIRS` + `MAP`).

Runewarden now has a typed shift report pipeline. Chapter 7 will stop hardcoding incident lists and start parsing them from real input files.

---

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

---

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

---

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

---

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

---

# Chapter 11: Assurance Workflow

On inspection days, Ironhold does not send one specialist. It sends three. One checks recent incidents against known cases. One stress-tests systems under varying conditions. One does formal sign-off on the parts that can be certified. They overlap on purpose, because each one catches a different class of error.

Chapter 11 turns that pattern into a repeatable Runewarden workflow.

We now have three assurance tools. The mistake is to treat them as rivals. They are a sequence.

Create:

```text
book/code/runewarden/chapters/ch11_assurance_workflow/
  test.crn
  verify.crn
  prove.crn
  run_assurance.sh
  lib/
    workflow.crn
```

Write `lib/workflow.crn`:

```cairn
DEF clamp_to_ten : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  DUP 10 GT
  IF
    DROP 10
  END
  POST DUP 0 GTE SWAP 10 LTE AND
END

DEF risk_band : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  clamp_to_ten
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

DEF risk_band_with_let : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  clamp_to_ten LET score
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

DEF risk_label : int -> str EFFECT pure
  PRE { DUP 0 GTE SWAP 2 LTE AND }
  DUP 2 EQ
  IF
    DROP "crimson"
  ELSE
    DUP 1 EQ
    IF
      DROP "amber"
    ELSE
      DROP "green"
    END
  END
END

DEF risk_label_for_score : int -> str EFFECT pure
  PRE { DUP 0 GTE }
  risk_band_with_let
  risk_label
END

DEF risk_label_known : int -> bool EFFECT pure
  PRE { DUP 0 GTE }
  clamp_to_ten
  risk_band
  risk_label
  DUP "green" EQ
  OVER "amber" EQ OR
  SWAP "crimson" EQ OR
  POST DUP
END

DEF risk_label_for_score_known : int -> bool EFFECT pure
  PRE { DUP 0 GTE }
  risk_label_known
  POST DUP
END

DEF clamp_idempotent_gap : int -> int EFFECT pure
  PRE { DUP 0 GTE }
  DUP
  clamp_to_ten
  SWAP
  clamp_to_ten
  SUB
  POST DUP 0 EQ
END
```

Now `test.crn`:

```cairn
IMPORT "lib/workflow.crn"

TEST "score above ten still maps to crimson"
  12 risk_label_for_score
  "crimson" ASSERT_EQ
END

TEST "mid score maps to amber"
  5 risk_label_for_score
  "amber" ASSERT_EQ
END

TEST "small score maps to green"
  1 risk_label_for_score
  "green" ASSERT_EQ
END

TEST "clamping remains idempotent for concrete score"
  9 clamp_idempotent_gap
  0 ASSERT_EQ
END
```

`verify.crn`:

```cairn
IMPORT "lib/workflow.crn"

VERIFY clamp_to_ten 80
VERIFY risk_band 80
VERIFY risk_label_known 80
VERIFY risk_label_for_score_known 80
VERIFY clamp_idempotent_gap 80
```

`prove.crn`:

```cairn
IMPORT "lib/workflow.crn"

PROVE clamp_to_ten
PROVE risk_band
PROVE risk_band_with_let
PROVE clamp_idempotent_gap
```

And a helper script:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="book/code/runewarden/chapters/ch11_assurance_workflow"

echo "[1/3] native tests"
./cairn --test "$ROOT/test.crn"

echo "[2/3] property checks"
./cairn "$ROOT/verify.crn"

echo "[3/3] proofs"
./cairn "$ROOT/prove.crn"
```

Run the full sequence:

```bash
book/code/runewarden/chapters/ch11_assurance_workflow/run_assurance.sh
```

You should see tests pass, properties pass, and proofs return a mixed result: three `PROVEN` and one `UNKNOWN` for the `LET`-based function.

That mixed result is healthy. It tells us the workflow is doing what it should do. Concrete behavior is locked by tests. Invariants are stressed by property checks. Proof-friendly kernel functions are certified where the solver applies. The remainder is still covered by the first two layers.

This is the operating model we will carry forward into web, persistence, and concurrency chapters. Chapter 12 will start the architectural side of that model by separating pure core logic from effectful boundaries.

---

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

---

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

---

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

---

# Chapter 15: First Web Endpoint

By the time a message reaches the outer gate, it has already passed through three rooms: the recorder who writes it, the runner who carries it, and the guard who reads it back before opening the latch. Ironhold does not trust silent pipes. It trusts explicit handoff.

Chapter 15 is the first network handoff in Runewarden. We take the reporting flow from previous chapters and serve it over HTTP.

Create:

```text
book/code/runewarden/chapters/ch15_first_web_endpoint/
  main.crn
  data/
    shift_day_005.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

`lib/core.crn` and `lib/shell.crn` carry forward from Chapter 14.

Use this data file:

```text
cave_in,7
gas_leak,2
rune_flare,1
```

Add `lib/shared.crn`:

```cairn
# Chapter-local shared helpers.

DEF argv_head_or : str -> str EFFECT io
  LET fallback
  ARGV LEN 0 GT
  IF
    ARGV HEAD
  ELSE
    fallback
  END
END

DEF argv_second_int_or : int -> int EFFECT io
  LET fallback
  ARGV LEN 1 GT
  IF
    fallback ARGV TAIL HEAD to_int_or
  ELSE
    fallback
  END
END
```

Add `lib/web.crn`:

```cairn
IMPORT "core.crn"
IMPORT "shell.crn"

DEF render_shift_summary_text : [incident] str -> str EFFECT pure
  LET incidents
  LET source_path

  incidents LEN LET incident_count
  incidents shift_total_score LET total_score
  incidents shift_max_score LET max_score
  incidents shift_crimson_count LET crimson_count
  incidents shift_alert_count_pairs LET grouped

  grouped crimson_count max_score total_score incident_count source_path
  "source={}\nincident_count={}\ntotal_score={}\nmax_score={}\ncrimson_count={}\ngrouped_by_alert={}\n" FMT
END

DEF handle_report_request_with_source : str str str map[str str] map[str str] map[str str] map[str str] map[str str] -> str map[str str] int EFFECT io
  LET source_path
  LET path
  LET method
  LET query
  LET form
  LET headers
  LET cookies
  LET session
  query DROP
  form DROP
  headers DROP
  cookies DROP
  session DROP

  method "GET" EQ
  IF
    path "/" EQ
    IF
      source_path load_incidents_with_fallback LET incidents
      source_path incidents render_shift_summary_text
      http_text_ok
    ELSE
      "not found\n" http_text_not_found
    END
  ELSE
    "method not allowed\n" http_text_method_not_allowed
  END
END
```

Now `main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch15_first_web_endpoint/data/shift_day_005.txt" argv_head_or LET source_path
8125 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v0.7 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_request_with_source
} HTTP_SERVE
```

Run it:

```bash
./cairn book/code/runewarden/chapters/ch15_first_web_endpoint/main.crn
```

Then in another terminal:

```bash
curl http://127.0.0.1:8125/
```

You should get the live shift summary as plain text over HTTP.

The shape is the point. `HTTP_SERVE` owns transport. Our handler owns route policy and response content. The pure renderer is still pure. The I/O shell still owns file fallback and warnings. We added network delivery without collapsing those boundaries.

Chapter 16 will keep the same core and turn this single endpoint into explicit multi-route handling so the web surface can grow without becoming an if/else thicket.

---

# Chapter 16: Routing And Html Helpers

At shift change, the outer gate does not ask one question. It asks several in order. Are you expected? Are you carrying sealed cargo? Are you here for inspection? The gate works because each path is explicit, and the fallback is explicit too.

Chapter 16 gives Runewarden that same shape for HTTP routes.

In Chapter 15 we had one endpoint and manual branching. Here we introduce a route chain: small route functions, combined with `route_or`, finalized with `route_finish_get`.

Create:

```text
book/code/runewarden/chapters/ch16_routing_and_html_helpers/
  main.crn
  data/
    shift_day_006.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

`lib/core.crn`, `lib/shell.crn`, and `lib/shared.crn` carry forward from Chapter 15.

Use this input file:

```text
cave_in,5
gas_leak,4
rune_flare,2
```

Now `lib/web.crn`:

```cairn
IMPORT "core.crn"
IMPORT "shell.crn"

DEF render_shift_summary_text : [incident] str -> str EFFECT pure
  LET incidents
  LET source_path

  incidents LEN LET incident_count
  incidents shift_total_score LET total_score
  incidents shift_max_score LET max_score
  incidents shift_crimson_count LET crimson_count
  incidents shift_alert_count_pairs LET grouped

  grouped crimson_count max_score total_score incident_count source_path
  "source={}\nincident_count={}\ntotal_score={}\nmax_score={}\ncrimson_count={}\ngrouped_by_alert={}\n" FMT
END

DEF route_get_root_report : str str str -> result[tuple[str map[str str] int] str] EFFECT io
  LET source_path
  LET method
  LET path

  method "GET" EQ
  path "/" EQ
  AND
  IF
    source_path load_incidents_with_fallback LET incidents
    source_path incidents render_shift_summary_text
    http_text_ok
    http_pack_response
    Ok
  ELSE
    "no_match" Err
  END
END

DEF route_get_health : str str -> result[tuple[str map[str str] int] str] EFFECT pure
  LET method
  LET path
  path method "/health" "ok\n" route_get_text
END

DEF route_get_alerts : str str str -> result[tuple[str map[str str] int] str] EFFECT io
  LET source_path
  LET method
  LET path

  method "GET" EQ
  path "/alerts" EQ
  AND
  IF
    source_path load_incidents_with_fallback
    shift_alert_count_pairs
    source_path "source={}\nalerts={}\n" FMT
    http_text_ok
    http_pack_response
    Ok
  ELSE
    "no_match" Err
  END
END

DEF handle_report_routes_with_source : str str str map[str str] map[str str] map[str str] map[str str] map[str str] -> str map[str str] int EFFECT io
  LET source_path
  LET path
  LET method
  LET query
  LET form
  LET headers
  LET cookies
  LET session
  query DROP
  form DROP
  headers DROP
  cookies DROP
  session DROP

  path method source_path route_get_root_report
  path method route_get_health
  route_or
  path method source_path route_get_alerts
  route_or
  method route_finish_get
END
```

And `main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch16_routing_and_html_helpers/data/shift_day_006.txt" argv_head_or LET source_path
8126 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v0.8 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run the server:

```bash
./cairn book/code/runewarden/chapters/ch16_routing_and_html_helpers/main.crn
```

Then try:

```bash
curl -i http://127.0.0.1:8126/
curl -i http://127.0.0.1:8126/health
curl -i http://127.0.0.1:8126/alerts
curl -i http://127.0.0.1:8126/missing
curl -i -X POST http://127.0.0.1:8126/health
```

Expected shape is straightforward: report text on `/`, `ok` on `/health`, alert summary on `/alerts`, `404` for unknown GET paths, and `405` for non-GET methods.

The key gain is compositional routing. Each route is small and local. The chain reads top to bottom in priority order. Fallback behavior is centralized in `route_finish_get` instead of copied into each route.

Chapter 17 will keep this route structure and add form-based mutation so the web app can change state instead of only reporting it.

---

# Chapter 17: Forms And Mutations

By the time the third bell sounds, the slate in the record hall is already wrong. The mine changed while the page was still drying. A report that cannot be amended is not a report, only a monument.

Today Runewarden learns to accept new incidents from the browser and write them back to disk. We keep the chapter deliberately narrow: one HTML form, one POST route, one file-backed mutation path, and the same route-chain style from Chapter 16.

Create:

```text
book/code/runewarden/chapters/ch17_forms_and_mutations/
  main.crn
  data/
    shift_day_007.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

Carry `lib/core.crn` and `lib/shared.crn` from Chapter 16.

Use this seed file:

```text
gas_leak,3
```

## Shell Boundary: Load And Save

`lib/shell.crn` keeps file IO and serialization out of route code:

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

DEF incident_to_line : incident -> str EFFECT pure
  MATCH
    CaveIn { "cave_in,{}" FMT }
    GasLeak { "gas_leak,{}" FMT }
    RuneFlare { "rune_flare,{}" FMT }
  END
END

DEF serialize_incidents : [incident] -> str EFFECT pure
  { incident_to_line } MAP
  "\n" JOIN
END

DEF save_incidents_to_path : [incident] str -> void EFFECT io
  LET incidents
  LET source_path

  incidents serialize_incidents LET body
  body LEN 0 GT
  IF
    body "\n" CONCAT LET final
    final source_path WRITE_FILE!
  ELSE
    "" source_path WRITE_FILE!
  END
END
```

The important boundary decision is this: route handlers decide *what* the new list should be; shell helpers decide *how* that list reaches the file.

## Web Layer: GET + POST

`lib/web.crn` adds form parsing and one mutation endpoint.

```cairn
IMPORT "shell.crn"

DEF form_incident_kind : map[str str] -> str EFFECT pure
  "kind" SWAP "gas_leak" map_get_or LOWER
END

DEF form_incident_magnitude : map[str str] -> int EFFECT pure
  "magnitude" SWAP "1" map_get_or
  1 SWAP to_int_or
  DUP 0 LT
  IF
    DROP 0
  END
END

DEF form_to_incident : map[str str] -> incident EFFECT pure
  LET form
  form form_incident_kind LET kind
  form form_incident_magnitude LET magnitude

  kind "cave_in" EQ
  IF
    magnitude CaveIn
  ELSE
    kind "rune_flare" EQ
    IF
      magnitude RuneFlare
    ELSE
      magnitude GasLeak
    END
  END
END

DEF render_incident_item_html : incident -> str EFFECT pure
  incident_to_line
  html_escape
  "<li>{}</li>" FMT
END

DEF render_incident_items_html : [incident] -> str EFFECT pure
  DUP LEN 0 EQ
  IF
    DROP
    "<li>no incidents yet</li>"
  ELSE
    { render_incident_item_html } MAP
    "\n" JOIN
  END
END

DEF render_report_page_html : [incident] str -> str EFFECT pure
  LET incidents
  LET source_path

  incidents LEN LET incident_count
  incidents shift_total_score LET total_score
  incidents shift_max_score LET max_score
  incidents shift_crimson_count LET crimson_count
  incidents shift_alert_count_pairs LET grouped
  incidents render_incident_items_html LET items_html
  source_path html_escape LET safe_source

  items_html grouped crimson_count max_score total_score incident_count safe_source "<!doctype html>\n<html lang=\"en\">\n  <head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n    <title>Runewarden</title>\n  </head>\n  <body>\n    <main>\n      <h1>Runewarden Report</h1>\n      <p>source: {}</p>\n      <p>incidents: {} | total_score: {} | max_score: {} | crimson_count: {}</p>\n      <p>alerts: {}</p>\n      <form method=\"post\" action=\"/add\">\n        <label>kind\n          <select name=\"kind\">\n            <option value=\"gas_leak\">gas_leak</option>\n            <option value=\"cave_in\">cave_in</option>\n            <option value=\"rune_flare\">rune_flare</option>\n          </select>\n        </label>\n        <label>magnitude\n          <input name=\"magnitude\" value=\"1\" />\n        </label>\n        <button type=\"submit\">add incident</button>\n      </form>\n      <ul>\n{}\n      </ul>\n    </main>\n  </body>\n</html>\n" FMT
END

DEF route_get_root_page : str str str -> result[tuple[str map[str str] int] str] EFFECT io
  LET source_path
  LET method
  LET path

  method "GET" EQ
  path "/" EQ
  AND
  IF
    source_path load_incidents_with_fallback LET incidents
    source_path incidents render_report_page_html
    http_html_ok
    http_pack_response
    Ok
  ELSE
    "no_match" Err
  END
END

DEF route_get_health : str str -> result[tuple[str map[str str] int] str] EFFECT pure
  LET method
  LET path
  path method "/health" "ok\n" route_get_text
END

DEF handle_report_routes_with_source : str str str map[str str] map[str str] map[str str] map[str str] map[str str] -> str map[str str] int EFFECT io
  LET source_path
  LET path
  LET method
  LET query
  LET form
  LET headers
  LET cookies
  LET session
  query DROP
  headers DROP
  cookies DROP
  session DROP

  method "GET" EQ
  IF
    path method source_path route_get_root_page
    path method route_get_health
    route_or
    method route_finish_get
  ELSE
    method "POST" EQ
    IF
      path "/add" EQ
      IF
        source_path load_incidents_with_fallback LET incidents
        form form_to_incident LET added
        incidents added [] CONS CONCAT LET updated
        source_path updated save_incidents_to_path
        updated LET incidents
        source_path incidents render_report_page_html
        http_html_ok
      ELSE
        "not found\n" http_text_not_found
      END
    ELSE
      "method not allowed\n" http_text_method_not_allowed
    END
  END
END
```

The POST branch does three things, in order:

1. Read current incidents.
2. Build one new `incident` from form fields.
3. Persist the appended list, then render the updated page.

No silent magic, no hidden mutation point.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch17_forms_and_mutations/data/shift_day_007.txt" argv_head_or LET source_path
8127 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v0.9 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch17_forms_and_mutations/main.crn
```

Then in another shell:

```bash
curl -i http://127.0.0.1:8127/
curl -i -X POST \
  -d 'kind=cave_in&magnitude=4' \
  http://127.0.0.1:8127/add
curl -i http://127.0.0.1:8127/
```

After the POST, the rendered report should show one extra incident, and `shift_day_007.txt` should include the new line.

## Why This Matters

This is the first chapter where the web edge changes program state. It is still small, but it establishes three habits we will keep:

- Keep domain transformations pure when possible.
- Isolate IO in explicit shell helpers.
- Make mutation routes easy to read from top to bottom.

In Chapter 18 we will stop pretending every request is stateless and add cookies plus sessions.

---

# Chapter 18: Sessions Cookies And Login

A gate without memory is no gate at all. If every guard greets every face as a stranger, the city survives only by luck. Ironhold solved this long ago with stamped brass tokens: present one at the right post, and the watch knows who trusted you in the first place.

Today we teach Runewarden the same trick. We keep HTTP stateless at the wire, but we add a session layer so the app can remember who is signed in.

Create:

```text
book/code/runewarden/chapters/ch18_sessions_cookies_and_login/
  main.crn
  data/
    shift_day_008.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

Carry `lib/core.crn`, `lib/shell.crn`, and `lib/shared.crn` from Chapter 17.

Use this seed data:

```text
gas_leak,3
rune_flare,1
```

## One New Boundary Rule

The chapter handler now returns four values instead of three:

- `body`
- `headers`
- `session`
- `status`

That extra `session` value is how `HTTP_SERVE` decides whether to issue `Set-Cookie`, keep the existing session, or clear it.

`lib/web.crn` starts with tiny helpers:

```cairn
IMPORT "shell.crn"

DEF logged_in_p : map[str str] -> bool EFFECT pure
  session_has_user
END

DEF current_user_name : map[str str] -> str EFFECT pure
  "user" SWAP "" map_get_or
END

DEF with_session : map[str str] str map[str str] int -> str map[str str] map[str str] int EFFECT pure
  LET session
  LET body
  LET headers
  LET status
  status session headers body
END
```

`with_session` is just stack plumbing: if a response does not mutate session state, preserve the incoming session untouched.

## Login Page And Report Page

We render either the login page or the authenticated report page.

```cairn
DEF render_login_page : str -> str map[str str] int EFFECT pure
  LET error_message

  error_message LEN 0 GT
  IF
    error_message html_escape
    "<p><mark>{}</mark></p>" FMT
  ELSE
    ""
  END
  LET error_html

  error_html "<!doctype html>\n<html lang=\"en\">\n  <head>\n    <meta charset=\"utf-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n    <title>Runewarden Login</title>\n  </head>\n  <body>\n    <main>\n      <h1>Runewarden Access</h1>\n      <p>Sign in to inspect and amend the shift report.</p>\n      {}\n      <form method=\"post\" action=\"/login\">\n        <label>username <input name=\"username\" value=\"warden\" /></label>\n        <label>password <input name=\"password\" type=\"password\" value=\"ironhold\" /></label>\n        <button type=\"submit\">sign in</button>\n      </form>\n    </main>\n  </body>\n</html>\n" FMT
  http_html_ok
END
```

The authenticated page keeps the Chapter 17 report and adds a logout form.

## Route Flow

The central handler enforces three rules:

1. `GET /` shows report when logged in, login page otherwise.
2. `POST /login` validates credentials and writes session keys.
3. `POST /add` is rejected unless a session user exists.

```cairn
DEF handle_report_routes_with_source : str str str map[str str] map[str str] map[str str] map[str str] map[str str] -> str map[str str] map[str str] int EFFECT io
  LET source_path
  LET path
  LET method
  LET query
  LET form
  LET headers
  LET cookies
  LET session
  query DROP
  headers DROP
  cookies DROP

  method "GET" EQ
  IF
    path "/" EQ
    IF
      session logged_in_p
      IF
        source_path load_incidents_with_fallback LET incidents
        session current_user_name LET username
        username source_path incidents render_report_page_html
        session with_session
      ELSE
        "" render_login_page
        session with_session
      END
    ELSE
      path "/login" EQ
      IF
        "" render_login_page
        session with_session
      ELSE
        path method "/health" "ok\n" route_get_text
        route_finish
        session with_session
      END
    END
  ELSE
    method "POST" EQ
    IF
      path "/login" EQ
      IF
        "username" form "" map_get_or TRIM LET username
        "password" form "" map_get_or TRIM LET password

        username "warden" EQ
        password "ironhold" EQ
        AND
        IF
          source_path load_incidents_with_fallback LET incidents
          username source_path incidents render_report_page_html
          LET body
          LET headers
          LET status
          status session headers body "role" "watch" session_put
          "user" username session_put
        ELSE
          "invalid credentials" render_login_page
          session with_session
        END
      ELSE
        path "/logout" EQ
        IF
          "" render_login_page
          LET body
          LET headers
          LET status
          status session headers body session_clear
        ELSE
          path "/add" EQ
          IF
            session logged_in_p
            IF
              source_path load_incidents_with_fallback LET incidents
              form form_to_incident LET added
              incidents added [] CONS CONCAT LET updated
              source_path updated save_incidents_to_path
              session current_user_name LET username
              username source_path updated render_report_page_html
              session with_session
            ELSE
              "login required\n" http_text_unauthorized
              session with_session
            END
          ELSE
            "not found\n" http_text_not_found
            session with_session
          END
        END
      END
    ELSE
      "method not allowed\n" http_text_method_not_allowed
      session with_session
    END
  END
END
```

Note the successful login path:

```cairn
status session headers body "role" "watch" session_put
"user" username session_put
```

The first `session_put` writes role, the second writes user. The runtime serializes that session map and emits the session cookie automatically.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch18_sessions_cookies_and_login/data/shift_day_008.txt" argv_head_or LET source_path
8128 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v1.0 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch18_sessions_cookies_and_login/main.crn
```

Then test with a cookie jar:

```bash
curl -i -c /tmp/runewarden.cookies http://127.0.0.1:8128/
curl -i -b /tmp/runewarden.cookies -X POST \
  -d 'kind=cave_in&magnitude=4' \
  http://127.0.0.1:8128/add
curl -i -b /tmp/runewarden.cookies -c /tmp/runewarden.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8128/login
curl -i -b /tmp/runewarden.cookies -X POST \
  -d 'kind=cave_in&magnitude=4' \
  http://127.0.0.1:8128/add
curl -i -b /tmp/runewarden.cookies -X POST http://127.0.0.1:8128/logout
```

Expected behavior:

- first `/` request renders login page
- unauthenticated `/add` returns `401 Unauthorized`
- `/login` returns report page and sets cookie
- authenticated `/add` mutates the report file
- `/logout` clears session and returns login page

Chapter 19 will keep this session foundation and add authorization policy checks so login is not the only gate.

---

# Chapter 19: Authorization In Ironhold

Knowing a name is not the same as granting authority. Ironhold does not hand a blasting rune to every miner who can spell it. One guard checks identity; another checks whether that identity may perform the act.

Chapter 18 gave us login and sessions. Chapter 19 adds role-based authorization and a concrete admin-only action.

Create:

```text
book/code/runewarden/chapters/ch19_authorization_in_ironhold/
  main.crn
  data/
    shift_day_009.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    web.crn
```

Carry `lib/core.crn`, `lib/shell.crn`, and `lib/shared.crn` from Chapter 18.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## Policy Shape

This chapter uses two identities:

- `warden / ironhold` with role `watch`
- `thane / anvil` with role `admin`

We reuse the prelude guard helpers:

- `guard_require_login`
- `guard_require_role`

Role checks live in route branches, not hidden in runtime code.

## Core Additions

`lib/web.crn` introduces role-aware helpers:

```cairn
DEF current_user_role : map[str str] -> str EFFECT pure
  "role" SWAP "" map_get_or
END

DEF incident_not_crimson : incident -> bool EFFECT pure
  incident_alert Crimson EQ
  IF
    FALSE
  ELSE
    TRUE
  END
END

DEF clear_crimson_incidents : [incident] -> [incident] EFFECT pure
  { incident_not_crimson } FILTER
END
```

`clear_crimson_incidents` is the admin-only mutation used in this chapter.

## Admin Route

`GET /admin` requires both login and role:

```cairn
path "/admin" EQ
IF
  session guard_require_login
  IF
    session "admin" guard_require_role
    IF
      source_path load_incidents_with_fallback LET incidents
      session current_user_name incidents render_admin_page_html
      session with_session
    ELSE
      render_forbidden_page
      session with_session
    END
  ELSE
    render_unauthorized_page
    session with_session
  END
```

This branch makes the difference explicit:

- not logged in: unauthorized
- logged in, wrong role: forbidden
- logged in, admin role: admin page

## Admin-Only Mutation

`POST /admin/clear-crimson` uses the same guard sequence:

```cairn
path "/admin/clear-crimson" EQ
IF
  session guard_require_login
  IF
    session "admin" guard_require_role
    IF
      source_path load_incidents_with_fallback
      clear_crimson_incidents LET cleaned
      source_path cleaned save_incidents_to_path
      session current_user_name cleaned render_admin_page_html
      session with_session
    ELSE
      render_forbidden_page
      session with_session
    END
  ELSE
    render_unauthorized_page
    session with_session
  END
```

This is a real policy gate, not a cosmetic one. The file only changes on the admin path.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch19_authorization_in_ironhold/data/shift_day_009.txt" argv_head_or LET source_path
8129 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v1.1 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch19_authorization_in_ironhold/main.crn
```

Try this sequence:

```bash
# unauthenticated admin page
curl -i http://127.0.0.1:8129/admin

# watch login
curl -i -c /tmp/watch.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8129/login

# forbidden for watch role
curl -i -b /tmp/watch.cookies http://127.0.0.1:8129/admin
curl -i -b /tmp/watch.cookies -X POST http://127.0.0.1:8129/admin/clear-crimson

# admin login
curl -i -c /tmp/admin.cookies -X POST \
  -d 'username=thane&password=anvil' \
  http://127.0.0.1:8129/login

# admin can access and mutate
curl -i -b /tmp/admin.cookies http://127.0.0.1:8129/admin
curl -i -b /tmp/admin.cookies -X POST http://127.0.0.1:8129/admin/clear-crimson
```

After the final POST, `shift_day_009.txt` should no longer contain crimson incidents.

Chapter 20 will separate policy and storage concerns more formally so this web layer stops carrying all orchestration responsibilities itself.

---

# Chapter 20: Datastore Boundary

The stone ledgers of Ironhold are not kept at the gate. The gate decides who may pass; the archive decides how records are read and written. If one clerk changes writing tools, the guard rotation should not change with him.

That is the chapter move: split persistence orchestration out of route handlers and into a datastore boundary module.

Create:

```text
book/code/runewarden/chapters/ch20_datastore_boundary/
  main.crn
  data/
    shift_day_010.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
```

Carry `core`, `shell`, and `shared` from Chapter 19.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## Why A Boundary

In Chapter 19, web handlers still performed read/transform/write sequences directly.

That was workable, but it coupled HTTP routes to storage mechanics. The coupling gets painful as soon as you add a second backend.

The boundary in this chapter is a new module, `lib/store.crn`, with exactly three operations.

## Store Module

```cairn
IMPORT "shell.crn"

DEF incident_not_crimson : incident -> bool EFFECT pure
  incident_alert Crimson EQ
  IF
    FALSE
  ELSE
    TRUE
  END
END

DEF store_load_incidents : str -> [incident] EFFECT io
  load_incidents_with_fallback
END

DEF store_append_incident : incident str -> [incident] EFFECT io
  LET incident
  LET source_path

  source_path load_incidents_with_fallback LET incidents
  incidents incident [] CONS CONCAT LET updated
  source_path updated save_incidents_to_path
  updated
END

DEF store_clear_crimson_incidents : str -> [incident] EFFECT io
  LET source_path

  source_path load_incidents_with_fallback
  { incident_not_crimson } FILTER
  LET cleaned
  source_path cleaned save_incidents_to_path
  cleaned
END
```

The web layer no longer knows how file parsing or serialization works. It asks the store for domain values.

## Web Layer Changes

`lib/web.crn` imports `store.crn` and replaces direct shell persistence calls.

Add incident route, before:

```cairn
source_path load_incidents_with_fallback LET incidents
form form_to_incident LET added
incidents added [] CONS CONCAT LET updated
source_path updated save_incidents_to_path
```

After:

```cairn
form form_to_incident LET added
source_path added store_append_incident LET updated
```

Admin clear route, before:

```cairn
source_path load_incidents_with_fallback
clear_crimson_incidents LET cleaned
source_path cleaned save_incidents_to_path
```

After:

```cairn
source_path store_clear_crimson_incidents LET cleaned
```

The route intent is now obvious: authenticate, authorize, call store operation, render.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch20_datastore_boundary/data/shift_day_010.txt" argv_head_or LET source_path
8130 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v1.2 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch20_datastore_boundary/main.crn
```

Smoke check:

```bash
curl -i http://127.0.0.1:8130/health
curl -i -c /tmp/watch.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8130/login
curl -i -b /tmp/watch.cookies -X POST \
  -d 'kind=gas_leak&magnitude=5' \
  http://127.0.0.1:8130/add
curl -i -c /tmp/admin.cookies -X POST \
  -d 'username=thane&password=anvil' \
  http://127.0.0.1:8130/login
curl -i -b /tmp/admin.cookies -X POST \
  http://127.0.0.1:8130/admin/clear-crimson
```

Chapter 21 will keep the same `store_*` surface and swap implementation details underneath it using Mnesia.

---

# Chapter 21: Mnesia Default Backend

A ledger carved on a slate dies with the slate. Ironhold keeps the real books in the deep archive, where a shift change does not erase yesterday. The gate scribes still ask the same questions, but they no longer trust a single page on a single desk.

In this chapter we keep the Chapter 20 route and policy code almost untouched and swap only the datastore implementation underneath `store_*`.

Create:

```text
book/code/runewarden/chapters/ch21_mnesia_default_backend/
  main.crn
  data/
    shift_day_011.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
```

Carry `core`, `shell`, `shared`, and `web` from Chapter 20.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## Same Boundary, New Backend

`lib/web.crn` still calls:

- `store_load_incidents`
- `store_append_incident`
- `store_clear_crimson_incidents`

Only `lib/store.crn` changes.

## Mnesia Store Module

```cairn
IMPORT "shell.crn"

DEF store_key_for_source : str -> str EFFECT pure
  "runewarden:{}" FMT
END

DEF incident_not_crimson : incident -> bool EFFECT pure
  incident_alert Crimson EQ
  IF
    FALSE
  ELSE
    TRUE
  END
END

DEF store_put_incidents : [incident] str -> void EFFECT db
  LET incidents
  LET source_path

  source_path store_key_for_source LET key
  incidents serialize_incidents LET body
  body key data_put
END

DEF store_load_incidents : str -> [incident] EFFECT io
  LET source_path
  source_path store_key_for_source LET key

  key data_get
  MATCH
    Ok {
      parse_incident_lines
    }
    Err {
      DROP
      source_path load_incidents_with_fallback LET seeded
      source_path seeded store_put_incidents
      seeded
    }
  END
END

DEF store_append_incident : incident str -> [incident] EFFECT io
  LET incident
  LET source_path

  source_path store_load_incidents LET incidents
  incidents incident [] CONS CONCAT LET updated
  source_path updated store_put_incidents
  updated
END

DEF store_clear_crimson_incidents : str -> [incident] EFFECT io
  LET source_path

  source_path store_load_incidents
  { incident_not_crimson } FILTER
  LET cleaned
  source_path cleaned store_put_incidents
  cleaned
END
```

The key design point is lazy seeding:

- first read for a source key misses in DB
- store loads from file seed once
- store writes seeded value into Mnesia
- subsequent reads use DB value

This lets us migrate without a dedicated import command.

## Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch21_mnesia_default_backend/data/shift_day_011.txt" argv_head_or LET source_path
8131 argv_second_int_or LET port
"127.0.0.1" LET bind_host

source_path port bind_host "Runewarden v1.3 web: serving http://{}:{}/ (source={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch21_mnesia_default_backend/main.crn
```

## Persistence Check Across Restart

Run once, login, add one incident, stop server, run again, login again.

If Mnesia is active, the second run should still show the added incident even though the seed file did not change.

Example sequence:

```bash
curl -i -c /tmp/watch.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8131/login
curl -i -b /tmp/watch.cookies -X POST \
  -d 'kind=gas_leak&magnitude=5' \
  http://127.0.0.1:8131/add
# stop and restart server
curl -i -c /tmp/admin.cookies -X POST \
  -d 'username=thane&password=anvil' \
  http://127.0.0.1:8131/login
```

In Chapter 22 we keep this same Cairn-side `store_*` contract and switch the runtime data backend to Postgres.

---

# Chapter 22: Postgres Backend Swap

Ironhold keeps two archives: the stone hall under the keep, and the ledger house across the river where merchants reconcile every ingot twice. The forms differ, the clerks differ, but the guard at the gate should not care which archive answers a query.

This chapter performs that exact move. We keep Runewarden’s Cairn app shape unchanged and switch the runtime datastore backend from Mnesia to Postgres.

Create:

```text
book/code/runewarden/chapters/ch22_postgres_backend_swap/
  main.crn
  data/
    shift_day_012.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
```

Carry `lib/core.crn`, `lib/shell.crn`, `lib/store.crn`, and `lib/web.crn` from Chapter 21.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## No New App API

The point of Chapters 20-22 is now visible:

- web routes still call `store_load_incidents`, `store_append_incident`, `store_clear_crimson_incidents`
- `store.crn` still talks through `data_get/data_put`
- the backend decision is runtime configuration, not application rewrites

## Entrypoint With Backend Visibility

`main.crn` now reports which backend is active:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch22_postgres_backend_swap/data/shift_day_012.txt" argv_head_or LET source_path
8132 argv_second_int_or LET port
"127.0.0.1" LET bind_host
"mnesia" data_backend_or LET active_backend

active_backend source_path port bind_host "Runewarden v1.4 web: serving http://{}:{}/ (source={}, backend={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

And `lib/shared.crn` gets one helper:

```cairn
DEF data_backend_or : str -> str EFFECT io
  LET fallback
  [ "CAIRN_DATA_STORE_BACKEND" ] HOST_CALL env_get LET configured
  configured LEN 0 GT
  IF
    configured
  ELSE
    fallback
  END
END
```

## Run On Postgres

You can use a local Postgres and set runtime env vars directly:

```bash
CAIRN_DATA_STORE_BACKEND=postgres \
CAIRN_PG_HOST=127.0.0.1 \
CAIRN_PG_PORT=55433 \
CAIRN_PG_DATABASE=cairn \
CAIRN_PG_USER=postgres \
CAIRN_PG_PASSWORD=postgres \
CAIRN_PG_SSLMODE=disable \
./cairn book/code/runewarden/chapters/ch22_postgres_backend_swap/main.crn
```

If you want a one-command project harness for Postgres integration tests, use:

```bash
bash scripts/test_pg.sh
```

## Isolated Smoke Flow

With backend set to Postgres:

```bash
curl -i -c /tmp/watch.cookies -X POST \
  -d 'username=warden&password=ironhold' \
  http://127.0.0.1:8132/login
curl -i -b /tmp/watch.cookies -X POST \
  -d 'kind=gas_leak&magnitude=5' \
  http://127.0.0.1:8132/add
# restart the app process
curl -i -c /tmp/admin.cookies -X POST \
  -d 'username=thane&password=anvil' \
  http://127.0.0.1:8132/login
```

After restart, the report should still include the added incident (`incidents: 4`), showing that persistence is now provided by Postgres under the same Cairn-side store contract.

Chapter 23 will focus on operational testing: repeatable checks for these end-to-end behaviors across backend choices.

---

# Chapter 23: Operational Testing

Ironhold does not trust a machine because it worked once in front of a magistrate. Every shift master keeps a short ritual: check the warning bell, check the gate seal, check that yesterday’s record still exists after the lamps are relit. Reliability is a habit, not a speech.

This chapter turns Runewarden into that habit. We add repeatable smoke scripts that exercise the full web flow and restart persistence for both datastore backends.

Create:

```text
book/code/runewarden/chapters/ch23_operational_testing/
  main.crn
  data/
    shift_day_013.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
  scripts/
    common.sh
    run_smoke_mnesia.sh
    run_smoke_postgres.sh
```

Carry `lib/*` from Chapter 22.

Use seed data:

```text
gas_leak,3
rune_flare,2
cave_in,1
```

## Why Operational Scripts

Unit and property tests are necessary but not sufficient for a web service boundary. We also need short end-to-end checks that answer practical questions quickly:

- does the server start and become healthy?
- do auth gates still behave as expected?
- does mutation persist across process restart?
- do these claims hold on both Mnesia and Postgres?

## Shared Script Helpers

`scripts/common.sh` provides small primitives:

- `wait_for_health PORT`
- `assert_status RESPONSE CODE`
- `assert_contains RESPONSE NEEDLE`
- `start_server SOURCE PORT [ENV...]`

`start_server` records the PID for clean restart checks.

## Mnesia Smoke Script

`scripts/run_smoke_mnesia.sh` checks:

1. unauthenticated `POST /add` is rejected (unauthorized page)
2. watch login sees seeded `incidents: 3`
3. add operation yields `incidents: 4`
4. after restart, admin login still sees `incidents: 4`

Run:

```bash
book/code/runewarden/chapters/ch23_operational_testing/scripts/run_smoke_mnesia.sh
```

Expected tail:

```text
[mnesia] smoke checks passed
```

## Postgres Smoke Script

`scripts/run_smoke_postgres.sh` adds a temporary Postgres container and runs the same flow with backend env wiring:

- `CAIRN_DATA_STORE_BACKEND=postgres`
- `CAIRN_PG_HOST`
- `CAIRN_PG_PORT`
- `CAIRN_PG_DATABASE`
- `CAIRN_PG_USER`
- `CAIRN_PG_PASSWORD`
- `CAIRN_PG_SSLMODE`

Run:

```bash
book/code/runewarden/chapters/ch23_operational_testing/scripts/run_smoke_postgres.sh
```

Expected tail:

```text
[postgres] smoke checks passed
```

## Entrypoint

`main.crn` stays simple and reports the active backend:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch23_operational_testing/data/shift_day_013.txt" argv_head_or LET source_path
8133 argv_second_int_or LET port
"127.0.0.1" LET bind_host
"mnesia" data_backend_or LET active_backend

active_backend source_path port bind_host "Runewarden v1.5 web: serving http://{}:{}/ (source={}, backend={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

The app surface did not change. The tests around it became more operational and repeatable.

Chapter 24 will move us into actor workflows for mine-watch coordination while keeping this operations discipline in place.

---

# Chapter 24: Actors For Mine Watch

When the lower galleries open, Ironhold does not trust one scribe to hear every hammer strike. Each shaft has a watcher. Reports move as messages, not as shared ink. If one watcher stumbles, the others still speak.

This chapter is the first actor chapter in Runewarden. We build a small mine-watch flow with typed messages:

- one watcher actor receives gas scans
- one sensor actor sends a bounded sequence of scans
- the watcher emits a summary and exits

Create:

```text
book/code/runewarden/chapters/ch24_actors_for_mine_watch/
  main.crn
  lib/
    actor.crn
```

`lib/actor.crn`:

```cairn
# Small shared helpers for actor examples.

DEF send_self[T] : T -> void EFFECT pure
  SELF SWAP SEND
END
```

## Mine Watch Actor Program

`main.crn`:

```cairn
IMPORT "lib/actor.crn"

TYPE watch_msg = Scan str int | Report
TYPE sensor_msg = SetWatcher pid[watch_msg]

DEF handle_scan : str int int int -> int int EFFECT io
  LET shaft
  LET gas
  LET seen
  LET critical

  gas shaft "scan shaft={} gas={}" FMT SAID

  gas 7 GTE
  IF
    shaft "critical alert at {}" FMT SAID
    critical 1 ADD LET critical
  END

  seen 1 ADD LET seen
  critical seen
END

DEF sensor_a_boot : pid[watch_msg] -> void EFFECT pure
  LET watcher
  "shaft-a" 5 Scan watcher SWAP SEND
  "shaft-a" 9 Scan watcher SWAP SEND
  "shaft-a" 4 Scan watcher SWAP SEND
  watcher Report SEND
END

SPAWN watch_msg {
  0 LET critical
  0 LET seen

  RECEIVE
    Scan {
      LET gas
      LET shaft
      critical seen shaft gas handle_scan
      LET critical
      LET seen
      critical seen
    }
    Report { critical seen }
  END
  LET critical
  LET seen

  RECEIVE
    Scan {
      LET gas
      LET shaft
      critical seen shaft gas handle_scan
      LET critical
      LET seen
      critical seen
    }
    Report { critical seen }
  END
  LET critical
  LET seen

  RECEIVE
    Scan {
      LET gas
      LET shaft
      critical seen shaft gas handle_scan
      LET critical
      LET seen
      critical seen
    }
    Report { critical seen }
  END
  LET critical
  LET seen

  RECEIVE
    Report {
      critical seen "mine-watch summary scans={} critical={}" FMT SAID
      critical seen
    }
    Scan {
      LET shaft
      LET gas
      shaft DROP
      gas DROP
      critical seen
    }
  END
  LET critical
  LET seen

  DROP
}
LET watcher

SPAWN sensor_msg {
  RECEIVE
    SetWatcher { sensor_a_boot }
  END
  DROP
}
LET sensor_a

sensor_a watcher SetWatcher SEND
watcher MONITOR AWAIT
"watcher_exit={}" FMT SAID
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch24_actors_for_mine_watch/main.crn
```

Expected output shape:

```text
scan shaft=shaft-a gas=5
scan shaft=shaft-a gas=9
critical alert at shaft-a
scan shaft=shaft-a gas=4
mine-watch summary scans=3 critical=1
watcher_exit=normal
```

This is intentionally explicit. We repeat `RECEIVE` blocks and thread state manually because the chapter goal is actor semantics first.

Chapter 25 will compress this into a cleaner state loop with `WITH_STATE` and `STEP`.

---

# Chapter 25: Stateful Actor Loops

In Ironhold, a seasoned watch captain does not rewrite the whole logbook every time a bell rings. He keeps one state in hand and applies one rule per event. This chapter gives Runewarden that same discipline.

Chapter 24 proved actor messaging. Chapter 25 removes the repetitive `RECEIVE` blocks by introducing a typed state and a single step function.

Create:

```text
book/code/runewarden/chapters/ch25_stateful_actor_loops/
  main.crn
  lib/
    actor.crn
```

`lib/actor.crn` is the same tiny helper from Chapter 24.

## State Model

We add one ADT for watcher state:

```cairn
TYPE watch_state = WatchState int int bool
```

Fields are:

- total scans seen
- critical scans seen
- done flag (set after `Report`)

## Step Function

All event handling moves into one state transition:

```cairn
DEF step_watch : watch_state -> watch_state EFFECT io
  MATCH
    WatchState {
      LET seen
      LET critical
      LET done

      done
      IF
        seen critical done WatchState
      ELSE
        RECEIVE
          Scan {
            LET shaft
            LET gas

            gas shaft "scan shaft={} gas={}" FMT SAID

            gas 7 GTE
            IF
              shaft "critical alert at {}" FMT SAID
              critical 1 ADD LET critical
            END

            seen 1 ADD LET seen
            seen critical FALSE WatchState
          }
          Report {
            critical seen "mine-watch summary scans={} critical={}" FMT SAID
            seen critical TRUE WatchState
          }
        END
      END
    }
  END
END
```

This gives one local, testable place for all watcher behavior.

## Actor Loop

Watcher actor now uses the state-loop combinator pattern:

```cairn
SPAWN watch_msg {
  0
  0
  FALSE
  WatchState

  {
    4 {
      STEP step_watch
    } REPEAT
  } WITH_STATE

  DROP
  DROP
}
```

`REPEAT` is bounded at 4 because sensor sends 3 scans and 1 report.

## Full Program

`main.crn` keeps the same sensor flow as Chapter 24, then waits for watcher exit:

```cairn
sensor_a watcher SetWatcher SEND
watcher MONITOR AWAIT
"watcher_exit={}" FMT SAID
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch25_stateful_actor_loops/main.crn
```

Expected output shape:

```text
scan shaft=shaft-a gas=5
scan shaft=shaft-a gas=9
critical alert at shaft-a
scan shaft=shaft-a gas=4
mine-watch summary scans=3 critical=1
watcher_exit=normal
```

The behavior is unchanged; the structure is cleaner and easier to extend.

Chapter 26 will add protocol-checked workflows on top of this actor foundation.

---

# Chapter 26: Protocol Checked Workflows

In Ironhold, the gate captain does not merely hope the watch follows the proper exchange. The sequence is written on stone: first the shaft report, then the hazard report, then the summary bell. If someone skips a step, the gate closes.

This chapter adds that same discipline to our actor flow. We keep the mine-watch logic from Chapter 25, and we add a protocol that statically checks the watcher inbox sequence.

Create:

```text
book/code/runewarden/chapters/ch26_protocol_checked_workflows/
  main.crn
  protocol_mismatch.crn
  lib/
    actor.crn
```

## Message And Protocol

`main.crn` defines a finite receive workflow:

```cairn
TYPE msg = ScanA5 | ScanA9 | ScanA4 | Report

PROTOCOL watch_cycle =
  RECV ScanA5
  RECV ScanA9
  RECV ScanA4
  RECV Report
END
```

The watcher actor declares that protocol endpoint:

```cairn
SPAWN msg USING watch_cycle {
  ...
}
```

## Watcher Behavior

The actor still computes scan and critical counters with the same helper as Chapter 25:

```cairn
DEF apply_scan : str int int int -> int int EFFECT io
  LET shaft
  LET gas
  LET seen
  LET critical

  gas shaft "scan shaft={} gas={}" FMT SAID

  gas 7 GTE
  IF
    shaft "critical alert at {}" FMT SAID
    critical 1 ADD LET critical
  END

  seen 1 ADD LET seen
  critical seen
END
```

It then receives the protocol sequence in order and emits the summary:

```cairn
RECEIVE
  ScanA5 {
    critical seen 5 "shaft-a" apply_scan
    LET seen
    LET critical
  }
END
...
RECEIVE
  Report {
    critical seen "mine-watch summary scans={} critical={}" FMT SAID
    critical seen
    LET seen
    LET critical
  }
END
```

Outside the actor, we enqueue the expected messages and wait for clean exit:

```cairn
watcher ScanA5 SEND
watcher ScanA9 SEND
watcher ScanA4 SEND
watcher Report SEND
watcher MONITOR AWAIT
"watcher_exit={}" FMT SAID
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch26_protocol_checked_workflows/main.crn
```

Expected output shape:

```text
scan shaft=shaft-a gas=5
scan shaft=shaft-a gas=9
critical alert at shaft-a
scan shaft=shaft-a gas=4
mine-watch summary scans=3 critical=1
watcher_exit=normal
```

## Intentional Failure Example

`protocol_mismatch.crn` intentionally violates the declared protocol by trying to receive `ScanA9` first.

Run:

```bash
./cairn book/code/runewarden/chapters/ch26_protocol_checked_workflows/protocol_mismatch.crn
```

Expected checker error includes:

```text
RECEIVE under protocol expects ScanA5
```

That is the point of the feature: reject illegal conversation order before execution.

Chapter 27 will build supervision and restart behavior on top of these actor workflow guarantees.

---

# Chapter 27: Supervision And Restarts

In Ironhold, a watcher who drops his lantern does not end the shift. The foreman marks the failure, replaces the watcher, and the mine keeps moving. Reliability is not the absence of failure; it is a practiced restart.

This chapter adds that pattern to Runewarden: one watcher fails intentionally, the supervisor observes the exit reason, starts a replacement, and the replacement completes the mine-watch cycle.

Create:

```text
book/code/runewarden/chapters/ch27_supervision_and_restarts/
  main.crn
  lib/
    supervision.crn
```

`lib/supervision.crn`:

```cairn
# Small supervision helpers for actor lifecycle examples.

DEF watch_exit[T] : pid[T] -> monitor[T] EFFECT pure
  MONITOR
END

DEF await_exit[T] : monitor[T] -> str EFFECT pure
  AWAIT
END
```

## Protocols For The Two Phases

`main.crn` defines two protocol endpoints:

```cairn
TYPE msg = Crash | ScanA5 | ScanA9 | ScanA4 | Report

PROTOCOL crash_once =
  RECV Crash
END

PROTOCOL watch_cycle =
  RECV ScanA5
  RECV ScanA9
  RECV ScanA4
  RECV Report
END
```

- `crash_once` is the intentional failure phase.
- `watch_cycle` is the normal restarted watcher flow.

## Failing Watcher

```cairn
DEF start_failing_watcher : pid[msg] EFFECT pure
  SPAWN msg USING crash_once {
    RECEIVE
      Crash { "watcher_crash_simulated" SWAP DROP EXIT }
    END
  }
END
```

The actor exits with a clear reason string that the supervisor can report.

## Healthy Watcher

The replacement watcher is the Chapter 26 flow:

- receive three scan events
- accumulate `seen` and `critical`
- receive `Report`
- emit summary and exit normally

## Supervisor Flow

```cairn
DEF supervise_watch_once : void EFFECT io
  "supervisor=starting_failing_watcher" SAID
  start_failing_watcher LET failing
  failing watch_exit LET first_mon
  failing Crash SEND
  first_mon await_exit "first_exit={}" FMT SAID

  "supervisor=restarting_watcher" SAID
  start_healthy_watcher LET watcher
  watcher watch_exit LET second_mon

  watcher ScanA5 SEND
  watcher ScanA9 SEND
  watcher ScanA4 SEND
  watcher Report SEND

  second_mon await_exit "second_exit={}" FMT SAID
END

supervise_watch_once
```

This is the minimal supervision cycle: observe failure, restart, observe healthy completion.

Run:

```bash
./cairn book/code/runewarden/chapters/ch27_supervision_and_restarts/main.crn
```

Expected output shape:

```text
supervisor=starting_failing_watcher
first_exit=watcher_crash_simulated
supervisor=restarting_watcher
scan shaft=shaft-a gas=5
scan shaft=shaft-a gas=9
critical alert at shaft-a
scan shaft=shaft-a gas=4
mine-watch summary scans=3 critical=1
second_exit=normal
```

Chapter 28 will assemble the major pieces into a coherent capstone run instead of isolated slices.

---

# Chapter 28: Capstone Assembly

A full shift in Ironhold begins before the gate opens. The foreman runs a safety drill, verifies replacements are working, then opens the reporting desk for the day. This chapter assembles our language pieces into that same order.

Runewarden now does two things in one executable flow:

1. actor supervision preflight (fail once, restart once)
2. authenticated web reporting service with datastore boundary

Create:

```text
book/code/runewarden/chapters/ch28_capstone_assembly/
  main.crn
  data/
    shift_day_014.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
    supervision.crn
    mine_watch.crn
```

`core/shell/shared/store/web` are carried from Chapter 23.
`supervision.crn` comes from Chapter 27.
`mine_watch.crn` wraps the Chapter 27 watcher lifecycle as a callable preflight.

## Preflight Module

`lib/mine_watch.crn` exposes:

```cairn
DEF run_mine_watch_preflight : void EFFECT io
```

Behavior:

- starts a failing watcher (`Crash`)
- monitors and records the first exit reason
- starts a healthy watcher (`ScanA5`, `ScanA9`, `ScanA4`, `Report`)
- monitors and records normal second exit

This gives a bounded runtime confidence check before starting the web edge.

## Capstone Entrypoint

`main.crn`:

```cairn
IMPORT "lib/shared.crn"
IMPORT "lib/mine_watch.crn"
IMPORT "lib/web.crn"

"book/code/runewarden/chapters/ch28_capstone_assembly/data/shift_day_014.txt" argv_head_or LET source_path
8134 argv_second_int_or LET port
"127.0.0.1" LET bind_host
"mnesia" data_backend_or LET active_backend

"capstone=run preflight checks" SAID
run_mine_watch_preflight

active_backend source_path port bind_host "capstone=web serving http://{}:{}/ (source={}, backend={})" FMT SAID
bind_host port {
  source_path handle_report_routes_with_source
} HTTP_SERVE
```

The important design point is sequencing:

- actor lifecycle checks first
- persistent/reporting service second

## Run

```bash
./cairn book/code/runewarden/chapters/ch28_capstone_assembly/main.crn
```

Expected startup shape:

```text
capstone=run preflight checks
preflight=mine_watch starting failing watcher
preflight first_exit=watcher_crash_simulated
preflight=mine_watch restarting watcher
...scan output...
preflight second_exit=normal
capstone=web serving http://127.0.0.1:8134/ (...)
```

Then verify service is up:

```bash
curl -i http://127.0.0.1:8134/health
```

Chapter 29 will review this assembled system as a safety/hardening pass and identify what still needs explicit guards before production use.

---

# Chapter 29: Safety Review And Hardening

A city survives not by one perfect shift, but by habits that make bad shifts less dangerous. Ironhold assumes malformed reports, wrong forms, and careless clients will appear every day. The gate must refuse bad input clearly and still keep the ledger sane.

This chapter is a hardening pass over the Chapter 28 capstone.

Create:

```text
book/code/runewarden/chapters/ch29_safety_review_and_hardening/
  main.crn
  data/
    shift_day_015.txt
  lib/
    core.crn
    shell.crn
    shared.crn
    store.crn
    web.crn
    supervision.crn
    mine_watch.crn
    hardening.crn
```

Carry the capstone modules from Chapter 28. Add `hardening.crn` and update `web.crn`.

## Hardening Helpers

`lib/hardening.crn` centralizes boundary response policy:

```cairn
DEF http_html_bad_request : str -> str map[str str] int EFFECT pure
  400
  M[ "Content-Type" "text/html; charset=utf-8" ]
  ROT
END

DEF harden_response_headers : str map[str str] int -> str map[str str] int EFFECT pure
  "X-Content-Type-Options" "nosniff" http_add_header
  "X-Frame-Options" "DENY" http_add_header
  "Referrer-Policy" "no-referrer" http_add_header
  "Cache-Control" "no-store" http_add_header
  "Content-Security-Policy" "default-src 'self'; style-src 'self' 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'" http_add_header
END
```

Every HTML renderer now ends with `harden_response_headers`.

## Strict Incident Input Validation

`form_to_incident` now returns `result[incident str]` instead of silently coercing invalid input:

```cairn
DEF form_to_incident : map[str str] -> result[incident str] EFFECT pure
```

Rules:

- `kind` must be one of: `gas_leak`, `cave_in`, `rune_flare`
- `magnitude` must parse as integer
- `magnitude` must be in `0..10`

In the `/add` route, invalid input returns a hardened `400 Bad Request` page.

## Login Form Cleanup

Login form fields no longer prefill credentials. They now use autocomplete hints only:

- `autocomplete="username"`
- `autocomplete="current-password"`

## Capstone Entrypoint

`main.crn` remains the Chapter 28 assembly shape, with updated path/port/version:

```cairn
"book/code/runewarden/chapters/ch29_safety_review_and_hardening/data/shift_day_015.txt" argv_head_or LET source_path
8135 argv_second_int_or LET port
...
"capstone=v1.6 web serving http://{}:{}/ (source={}, backend={})" FMT SAID
```

Run:

```bash
./cairn book/code/runewarden/chapters/ch29_safety_review_and_hardening/main.crn
```

Check startup:

```bash
curl -i http://127.0.0.1:8135/health
```

Check headers on a rendered page:

```bash
curl -i -X POST -d 'username=warden&password=ironhold' http://127.0.0.1:8135/login
```

You should see `CSP`, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, and `Cache-Control`.

Check strict bad request path (authenticated):

```bash
curl -i -c /tmp/ch29.cookies -X POST -d 'username=warden&password=ironhold' http://127.0.0.1:8135/login
curl -i -b /tmp/ch29.cookies -X POST -d 'kind=oops&magnitude=999' http://127.0.0.1:8135/add
```

Expected result: `HTTP/1.1 400 Bad Request` with a bounded error page.

Chapter 30 closes the book with a clear map of what to build next and what to stabilize before broader usage.

---

# Chapter 30: Where To Carve Next

The dawn bell sounds twice in Ironhold: once for the miners, and once for the clerks who must decide which warnings were noise and which were prophecy. By first light the watch ledger is already warm from too many hands.

The Runewarden does not get to choose between theory and duty. The mountain asks for both. A bad proof is useless in a collapse. A fast patch without invariants is only a delayed collapse. So the final lesson is not a new operator. It is how to steer the language once the tutorial scaffold is gone.

By Chapter 29 we built a complete vertical slice: typed domain data, pure business logic, effectful shells, datastore swapping, actor supervision, protocol checks, web boundaries, sessions, and hardening. That stack is enough to build software that does real work.

The important point is not that every layer is perfect. The important point is that every layer is visible. In Cairn, shape is explicit. Stack effects are explicit. Side effects are explicit. Failure channels are explicit. You can read a function signature and know what power it has and what obligations it carries.

Assurance in Cairn is strongest when used as a loop, not as a ceremony. `TEST` protects known examples. `VERIFY` pressures broad input space and catches boundary mistakes that examples miss. `PROVE` settles bounded obligations where symbolic arithmetic applies. Effects constrain where IO and persistence are allowed to occur. None of these tools replace design, but together they make design honest.

This book also exposed the practical boundary. Solver-backed proof is excellent for local arithmetic and structural invariants. It is not the right tool for process scheduling, browser behavior, or distributed timing. For those domains, we relied on type discipline, explicit protocols, supervised runtime behavior, and operational tests. That split is healthy. It keeps proof where proof is crisp and keeps engineering where engineering belongs.

If you want one final runnable milestone before leaving the book, run the hardened capstone and exercise both happy and unhappy paths:

```bash
./cairn book/code/runewarden/chapters/ch29_safety_review_and_hardening/main.crn
curl -i http://127.0.0.1:8135/health
curl -i -c /tmp/ch30.cookies -X POST -d 'username=warden&password=ironhold' http://127.0.0.1:8135/login
curl -i -b /tmp/ch30.cookies -X POST -d 'kind=oops&magnitude=999' http://127.0.0.1:8135/add
```

You should see a healthy service, successful authentication, and a bounded `400 Bad Request` for malformed incident input. That is the shape of a trustworthy boundary: useful to good clients, boring to malicious ones.

From here, the roadmap naturally splits into three practical campaigns.

First, deepen data modeling where application code still leans on ad hoc maps. Records and richer product shapes reduce accidental key mismatches and make web and datastore code read closer to the domain. The language has already moved in that direction with tuples and generic ADTs; continuing that work pays immediate dividends.

Second, keep tightening effect boundaries around infrastructure integrations. The database path already moved from direct runtime calls to a backend boundary and then to Postgres. The same discipline should guide additional integrations: narrow host interop, explicit effect annotations, and test surfaces that can run locally and in CI without hidden machine state.

Third, continue the web story without turning Cairn into framework sprawl. The right next features are the ones that preserve language clarity while enabling real applications: request/response boundary polish, authentication/session lifecycle hardening, and composable helpers that remain thin over explicit primitives.

The mountain metaphor has done enough work; now the code must do the rest. The book is finished, but the project is not. A good next Cairn program should be chosen not by novelty, but by pressure: pick the one that forces one missing piece into the open, implement that piece cleanly, and fold it back into the language with tests and documentation.

When the next bell rings, you should be able to answer three questions quickly: what this program promises, where it can fail, and how we know it behaves. If Cairn keeps making those answers easier to obtain, it is on the right path.
