# Access Control / Change Approval Gate

This example is a small typed policy engine. It decides whether a requested
action should be:

- `Allow`
- `RequireApproval`
- `Deny`

The goal is to showcase Cairn's assurance stack in one domain:

- domain types
- native `TEST`
- `VERIFY`
- selective `PROVE`

## Files

- `types.crn`: shared domain ADTs (`role`, `action`, `env`, `decision`, `workflow`)
- `kernel.crn`: small rank-based helpers kept solver-friendly
- `rules.crn`: readable policy logic built on top of the kernel
- `main.crn`: simple runnable demo with fixed scenarios
- `verify.crn`: `VERIFY` and `PROVE` runner
- `test.crn`: native Cairn `TEST` scenarios

## Run It

Run the fixed demo scenarios:

```bash
./cairn examples/policy/approval/main.crn
```

Run the assurance checks:

```bash
./cairn examples/policy/approval/verify.crn
```

Run the native Cairn tests:

```bash
./cairn --test examples/policy/approval/test.crn
```

## What It Proves

The example is intentionally split into layers:

- `kernel.crn` is where the most solver-friendly helpers live
- `rules.crn` is where the business policy is easiest to read

That lets Cairn show the difference between:

- exact scenario tests (`TEST`)
- randomized policy checks (`VERIFY`)
- solver-backed local guarantees (`PROVE`)

This is a policy example, not a web app. The point is to keep the rules
visible, explicit, and easy to audit.
