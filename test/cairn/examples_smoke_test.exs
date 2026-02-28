defmodule Cairn.ExamplesSmokeTest do
  use ExUnit.Case, async: false

  @examples ["examples/hello_world.crn", "examples/collections.crn", "examples/math.crn", "examples/strings.crn", "examples/interop.crn", "examples/imports/main.crn", "examples/prelude/result_flow.crn", "examples/prelude/env_parse.crn", "examples/prelude/ini_parse.crn", "examples/prelude/web_helpers.crn", "examples/practical/all_practical.crn", "examples/practical/main.crn", "examples/practical/ledger.crn", "examples/practical/todo.crn", "examples/practical/expenses.crn", "examples/practical/cashflow.crn", "examples/practical/cashflow_alerts.crn", "examples/practical/mini_grep.crn", "examples/practical/mini_grep_verify.crn", "examples/practical/mini_env.crn", "examples/practical/mini_ini.crn", "examples/concurrency/ping_pong_types.crn", "examples/concurrency/traffic_light_types.crn", "examples/concurrency/guess_binary.crn", "examples/ambitious/orchestrator.crn"]

  test "curated examples run end-to-end" do
    Enum.each(@examples, fn path ->
      assert {[], _env} = Cairn.eval_file(path)
    end)
  end

  test "practical examples print expected output markers" do
    assert_output_markers("examples/collections.crn", [
      "[[1, 10], [2, 20], [3, 30]]",
      "[[1, \"red\"], [2, \"green\"]]",
      "[1, 2]",
      "{:variant, \"result\", \"Ok\", [2]}",
      "[1, 10, 2, 20, 3, 30]",
      "[[0, [2, 4]], [1, [1, 3]]]"
    ])

    assert_output_markers("examples/math.crn", [
      "sin(0)=0.0",
      "cos(0)=1.0",
      "pi=",
      "e=",
      "floor(3.7)=3.0",
      "ceil(3.2)=4.0",
      "round(3.6)=4.0",
      "exp(1)=",
      "pow(8,2)=64.0",
      "log(10)=",
      "sqrt(100)=10.0"
    ])

    assert_output_markers("examples/strings.crn", [
      "upper=HELLO",
      "lower=one two",
      "reverse=cba",
      "replace=xo xo",
      "ends=T"
    ])

    assert_output_markers("examples/interop.crn", [
      "int=42",
      "float=3.14"
    ])

    assert_output_markers("examples/practical/main.crn", [
      "source=examples/practical/data/scores.csv",
      "total=71",
      "avg=14",
      "VERIFY score_total: OK"
    ])

    assert_output_markers("examples/practical/ledger.crn", [
      "source=examples/practical/data/ledger.csv",
      "balance=65",
      "volume=115",
      "count=5",
      "report_ok=T",
      "VERIFY ledger_balance_bounded: OK"
    ])

    assert_output_markers("examples/practical/todo.crn", [
      "source=examples/practical/data/todo.txt",
      "open=3",
      "done=2",
      "total=5",
      "done_pct=40",
      "report_ok=T",
      "VERIFY todo_partition_ok: OK"
    ])

    assert_output_markers("examples/practical/expenses.crn", [
      "source=examples/practical/data/expenses.csv",
      "total=1960",
      "max=1200",
      "avg=392",
      "over_100=4",
      "report_ok=T",
      "VERIFY abs_total_nonneg: OK"
    ])

    assert_output_markers("examples/practical/cashflow.crn", [
      "ledger_source=examples/practical/data/ledger.csv",
      "expenses_source=examples/practical/data/expenses.csv",
      "balance=65",
      "expenses_total=1960",
      "net_cashflow=-1895",
      "volume=115",
      "capacity=2075",
      "cashflow_score=9",
      "report_ok=T",
      "VERIFY cashflow_score: OK"
    ])

    assert_output_markers("examples/practical/cashflow_alerts.crn", [
      "ledger_source=examples/practical/data/ledger.csv",
      "expenses_source=examples/practical/data/expenses.csv",
      "cashflow_score=9",
      "risk_level=2",
      "risk_label=high",
      "action=reduce_costs",
      "report_ok=T",
      "VERIFY risk_level: OK"
    ])

    assert_output_markers("examples/practical/mini_grep.crn", [
      "1:Cairn",
      "5:delta Cairn"
    ])

    assert_output_markers("examples/practical/mini_grep_verify.crn", [
      "VERIFY leading_flag_count_bounded: OK"
    ])

    assert_output_markers("examples/prelude/env_parse.crn", [
      "app_name=Cairn",
      "port=4000",
      "keys=3",
      "token=abc=123"
    ])

    assert_output_markers("examples/prelude/ini_parse.crn", [
      "server_host=localhost",
      "sections=2",
      "auth_token=abc123"
    ])

    assert_output_markers("examples/prelude/web_helpers.crn", [
      "html_status=200",
      "html_type=text/html; charset=utf-8",
      "html_body=<h1>Cairn</h1>",
      "missing_status=404",
      "missing_type=text/plain; charset=utf-8",
      "missing_body=missing"
    ])

    assert_output_markers("examples/practical/mini_env.crn", [
      "Cairn"
    ])

    assert_output_markers("examples/practical/mini_ini.crn", [
      "4000"
    ])

    assert_output_markers("examples/ambitious/orchestrator.crn", [
      "VERIFY parsed_job_count_matches: OK",
      "orchestrator: parsed=4 jobs",
      "worker_b: failing job 3 reason=boom",
      "coordinator: restarting worker_b once",
      "reporter: completed=3",
      "reporter: failed=1",
      "reporter: restarted=1",
      "reporter: run finished"
    ])
  end

  defp assert_output_markers(path, markers) do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Cairn.eval_file(path)
      end)

    Enum.each(markers, fn marker ->
      assert output =~ marker
    end)
  end
end
