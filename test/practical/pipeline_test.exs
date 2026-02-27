defmodule Axiom.PracticalPipelineTest do
  use ExUnit.Case, async: false

  test "all_practical pipeline runs end-to-end" do
    assert {[], _env} = Axiom.eval_file("examples/practical/all_practical.ax")
  end

  test "cashflow alerts stage emits deterministic markers" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Axiom.eval_file("examples/practical/cashflow_alerts.ax")
      end)

    markers = [
      "ledger_source=examples/practical/data/ledger.csv",
      "expenses_source=examples/practical/data/expenses.csv",
      "cashflow_score=9",
      "risk_level=2",
      "risk_label=high",
      "action=reduce_costs",
      "report_ok=T",
      "VERIFY risk_level: OK"
    ]

    Enum.each(markers, fn marker ->
      assert output =~ marker
    end)
  end
end
