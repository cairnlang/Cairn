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
