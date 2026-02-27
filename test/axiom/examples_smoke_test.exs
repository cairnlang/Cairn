defmodule Axiom.ExamplesSmokeTest do
  use ExUnit.Case, async: false

  @examples ["examples/hello_world.ax", "examples/imports/main.ax", "examples/prelude/result_flow.ax", "examples/practical/main.ax", "examples/practical/ledger.ax", "examples/practical/todo.ax", "examples/practical/expenses.ax"]

  test "curated examples run end-to-end" do
    Enum.each(@examples, fn path ->
      assert {[], _env} = Axiom.eval_file(path)
    end)
  end

  test "practical examples print expected output markers" do
    assert_output_markers("examples/practical/main.ax", ["total=71", "avg=14", "VERIFY score_total: OK"])

    assert_output_markers("examples/practical/ledger.ax", [
      "balance=65",
      "volume=115",
      "count=5",
      "report_ok=T",
      "VERIFY ledger_balance_bounded: OK"
    ])

    assert_output_markers("examples/practical/todo.ax", [
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
