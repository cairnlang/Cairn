defmodule Mix.Tasks.Axiom.RunTest do
  use ExUnit.Case, async: false

  setup do
    on_exit(fn -> System.delete_env("AXIOM_NO_PRELUDE") end)
    :ok
  end

  test "prints help text" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Task.reenable("axiom.run")
        Mix.Tasks.Axiom.Run.run(["--help"])
      end)

    assert output =~ "Usage:"
    assert output =~ "--show-prelude"
    assert output =~ "--examples"
    assert output =~ "--json-errors"
    assert output =~ "AXIOM_NO_PRELUDE=1"
    assert output =~ "AXIOM_PROVE_TRACE=summary|verbose|json"
  end

  test "prints categorized examples index" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Task.reenable("axiom.run")
        Mix.Tasks.Axiom.Run.run(["--examples"])
      end)

    assert output =~ "Examples:"
    assert output =~ "basics:"
    assert output =~ "examples/hello_world.ax"
    assert output =~ "practical:"
    assert output =~ "examples/practical/all_practical.ax"
    assert output =~ "examples/practical/main.ax"
    assert output =~ "examples/practical/ledger.ax"
    assert output =~ "examples/practical/todo.ax"
    assert output =~ "examples/practical/ledger_cli.ax"
    assert output =~ "examples/practical/expenses.ax"
    assert output =~ "examples/practical/cashflow.ax"
    assert output =~ "examples/practical/cashflow_alerts.ax"
    assert output =~ "concurrency:"
    assert output =~ "examples/concurrency/ping_pong_types.ax"
    assert output =~ "examples/concurrency/traffic_light_types.ax"
    assert output =~ "examples/concurrency/traffic_light.ax"
    assert output =~ "examples/concurrency/ping_once.ax"
    assert output =~ "examples/concurrency/self_boot.ax"
    assert output =~ "examples/concurrency/two_pings.ax"
    assert output =~ "examples/concurrency/counter.ax"
    assert output =~ "prelude:"
    assert output =~ "examples/prelude/result_flow.ax"
    assert output =~ "diagnostics:"
    assert output =~ "examples/diagnostics/runtime_div_zero.ax"
    assert output =~ "prove:"
    assert output =~ "examples/prove/all_proven.ax"
  end

  test "prints run summary to stderr on successful run" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "axiom_run_summary_test.ax")
    File.write!(path, "1 2")

    Mix.Task.reenable("axiom.run")

    parent = self()

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        stdout =
          ExUnit.CaptureIO.capture_io(fn ->
            Mix.Tasks.Axiom.Run.run([path])
          end)

        send(parent, {:captured_stdout, stdout})
      end)

    stdout =
      receive do
        {:captured_stdout, out} -> out
      end

    assert stdout =~ "1"
    assert stdout =~ "2"
    assert stderr =~ "RUN SUMMARY: status=ok"
    assert stderr =~ "values=2"
    assert stderr =~ "elapsed_ms="
  end

  test "prints prelude discoverability banner with --show-prelude" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "axiom_run_prelude_test.ax")
    File.write!(path, "1")

    Mix.Task.reenable("axiom.run")

    parent = self()

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        stdout =
          ExUnit.CaptureIO.capture_io(fn ->
            Mix.Tasks.Axiom.Run.run(["--show-prelude", path])
          end)

        send(parent, {:captured_stdout, stdout})
      end)

    stdout =
      receive do
        {:captured_stdout, out} -> out
      end

    assert stdout =~ "1"
    assert stderr =~ "PRELUDE: auto-load enabled"
    assert stderr =~ "lib/prelude/result.ax"
    assert stderr =~ "result_unwrap_or"
    assert stderr =~ "lib/prelude/str.ax"
    assert stderr =~ "csv_ints"
    assert stderr =~ "lib/prelude.ax"
    assert stderr =~ "ask_or"
  end
end
