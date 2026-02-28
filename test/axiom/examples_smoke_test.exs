defmodule Axiom.ExamplesSmokeTest do
  use ExUnit.Case, async: false

  @examples ["examples/hello_world.ax", "examples/collections.ax", "examples/math.ax", "examples/interop.ax", "examples/imports/main.ax", "examples/prelude/result_flow.ax", "examples/practical/all_practical.ax", "examples/practical/main.ax", "examples/practical/ledger.ax", "examples/practical/todo.ax", "examples/practical/expenses.ax", "examples/practical/cashflow.ax", "examples/practical/cashflow_alerts.ax", "examples/practical/mini_grep.ax", "examples/practical/mini_grep_verify.ax", "examples/concurrency/ping_pong_types.ax", "examples/concurrency/traffic_light_types.ax", "examples/concurrency/guess_binary.ax"]

  test "curated examples run end-to-end" do
    Enum.each(@examples, fn path ->
      assert {[], _env} = Axiom.eval_file(path)
    end)
  end

  test "practical examples print expected output markers" do
    assert_output_markers("examples/collections.ax", [
      "[[1, 10], [2, 20], [3, 30]]",
      "[[1, \"red\"], [2, \"green\"]]",
      "[1, 2]",
      "{:variant, \"result\", \"Ok\", [2]}",
      "[1, 10, 2, 20, 3, 30]",
      "[[0, [2, 4]], [1, [1, 3]]]"
    ])

    assert_output_markers("examples/math.ax", [
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

    assert_output_markers("examples/interop.ax", [
      "up=HELLO",
      "down=one two",
      "rev=cba",
      "replace=xo xo",
      "int=42",
      "float=3.14"
    ])

    assert_output_markers("examples/practical/main.ax", [
      "source=examples/practical/data/scores.csv",
      "total=71",
      "avg=14",
      "VERIFY score_total: OK"
    ])

    assert_output_markers("examples/practical/ledger.ax", [
      "source=examples/practical/data/ledger.csv",
      "balance=65",
      "volume=115",
      "count=5",
      "report_ok=T",
      "VERIFY ledger_balance_bounded: OK"
    ])

    assert_output_markers("examples/practical/todo.ax", [
      "source=examples/practical/data/todo.txt",
      "open=3",
      "done=2",
      "total=5",
      "done_pct=40",
      "report_ok=T",
      "VERIFY todo_partition_ok: OK"
    ])

    assert_output_markers("examples/practical/expenses.ax", [
      "source=examples/practical/data/expenses.csv",
      "total=1960",
      "max=1200",
      "avg=392",
      "over_100=4",
      "report_ok=T",
      "VERIFY abs_total_nonneg: OK"
    ])

    assert_output_markers("examples/practical/cashflow.ax", [
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

    assert_output_markers("examples/practical/cashflow_alerts.ax", [
      "ledger_source=examples/practical/data/ledger.csv",
      "expenses_source=examples/practical/data/expenses.csv",
      "cashflow_score=9",
      "risk_level=2",
      "risk_label=high",
      "action=reduce_costs",
      "report_ok=T",
      "VERIFY risk_level: OK"
    ])

    assert_output_markers("examples/practical/mini_grep.ax", [
      "1:Axiom",
      "5:delta Axiom"
    ])

    assert_output_markers("examples/practical/mini_grep_verify.ax", [
      "VERIFY leading_flag_count_bounded: OK"
    ])
  end

  defp assert_output_markers(path, markers) do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Axiom.eval_file(path)
      end)

    Enum.each(markers, fn marker ->
      assert output =~ marker
    end)
  end
end
