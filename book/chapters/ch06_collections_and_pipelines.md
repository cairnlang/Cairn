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
