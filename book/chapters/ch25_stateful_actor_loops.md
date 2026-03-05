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
