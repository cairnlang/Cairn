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
