# Practical Pipeline

This document summarizes the staged practical workflow chain in `examples/practical/`.

## Stage 1: Baseline

- File: `examples/practical/main.crn`
- Purpose: minimal file-backed flow using prelude helpers and VERIFY
- Inputs: `examples/practical/data/scores.csv`
- Outputs: `source`, `total`, `avg`
- Invariant check: `VERIFY score_total 40`

## Stage 2: Focused Apps

### Ledger

- File: `examples/practical/ledger.crn`
- Inputs: default `examples/practical/data/ledger.csv` or argv path
- Outputs: `source`, `balance`, `volume`, `count`
- Round-trip: writes `/tmp/cairn_ledger_report.txt` and validates markers
- Invariant checks: `VERIFY credit_nonneg 60`, `VERIFY ledger_balance_bounded 60`

### Todo

- File: `examples/practical/todo.crn`
- Inputs: default `examples/practical/data/todo.txt` or argv path
- Outputs: `source`, `open`, `done`, `total`, `done_pct`
- Round-trip: writes `/tmp/cairn_todo_report.txt` and validates markers
- Invariant checks: `VERIFY count_open 60`, `VERIFY todo_partition_ok 60`

## Stage 3: Larger Module-Split App

- File: `examples/practical/expenses.crn`
- Modules:
  - `examples/practical/lib/expenses_parser.crn`
  - `examples/practical/lib/expenses_agg.crn`
  - `examples/practical/lib/expenses_report.crn`
- Inputs: default `examples/practical/data/expenses.csv` or argv path
- Outputs: `source`, `total`, `max`, `avg`, `over_100`
- Round-trip: writes `/tmp/cairn_expenses_report.txt` and validates markers
- Invariant check: `VERIFY abs_total_nonneg 60`

## Stage 4: Composed Workflow

- File: `examples/practical/cashflow.crn`
- Modules:
  - `examples/practical/lib/cashflow.crn`
  - shared `examples/practical/lib/report_common.crn`
- Inputs: ledger + expenses paths (argv override supported)
- Outputs: `ledger_source`, `expenses_source`, `balance`, `expenses_total`, `net_cashflow`, `volume`, `capacity`, `cashflow_score`
- Round-trip: writes `/tmp/cairn_cashflow_report.txt` and validates markers
- Invariant checks:
  - `VERIFY abs_total_nonneg 60`
  - `VERIFY ledger_balance_bounded 60`
  - `VERIFY cashflow_score 60`

## Stage 5: Alerts Extension

- File: `examples/practical/cashflow_alerts.crn`
- Module: `examples/practical/lib/cashflow_alerts.crn`
- Inputs: same as cashflow
- Outputs: `ledger_source`, `expenses_source`, `cashflow_score`, `risk_level`, `risk_label`, `action`
- Round-trip: writes `/tmp/cairn_cashflow_alerts_report.txt` and validates markers
- Invariant checks:
  - `VERIFY abs_total_nonneg 60`
  - `VERIFY ledger_balance_bounded 60`
  - `VERIFY cashflow_score 60`
  - `VERIFY risk_level 60`

## Convenience Commands

- Run complete practical chain: `mix cairn.run examples/practical/all_practical.crn`
- Run practical-only tests: `mix test.practical`
- Run full test suite: `mix test`
