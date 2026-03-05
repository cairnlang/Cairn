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
