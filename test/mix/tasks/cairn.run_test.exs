defmodule Mix.Tasks.Cairn.RunTest do
  use ExUnit.Case, async: false

  setup do
    on_exit(fn ->
      System.delete_env("CAIRN_NO_PRELUDE")
      System.delete_env("CAIRN_SKIP_ASSURANCE")
    end)
    :ok
  end

  test "prints help text" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Task.reenable("cairn.run")
        Mix.Tasks.Cairn.Run.run(["--help"])
      end)

    assert output =~ "Usage:"
    assert output =~ "--show-prelude"
    assert output =~ "--test <file.crn>"
    assert output =~ "--examples"
    assert output =~ "--json-errors"
    assert output =~ "CAIRN_NO_PRELUDE=1"
    assert output =~ "CAIRN_SKIP_ASSURANCE=1"
    assert output =~ "CAIRN_PROVE_TRACE=summary|verbose|json"
  end

  test "native test mode runs through the Mix task wrapper" do
    Mix.Task.reenable("cairn.run")

    parent = self()

    stdout =
      ExUnit.CaptureIO.capture_io(fn ->
        stderr =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            Mix.Tasks.Cairn.Run.run(["--test", "examples/web/afford_test.crn"])
          end)

        send(parent, {:captured_stderr, stderr})
      end)

    stderr =
      receive do
        {:captured_stderr, captured} -> captured
      end

    assert stdout =~ "PASS safe one-time purchase remains safe"
    assert stderr =~ "TEST SUMMARY: total=6 passed=6 failed=0"
  end

  test "prints categorized examples index" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        Mix.Task.reenable("cairn.run")
        Mix.Tasks.Cairn.Run.run(["--examples"])
      end)

    assert output =~ "Examples:"
    assert output =~ "basics:"
    assert output =~ "examples/hello_world.crn"
    assert output =~ "examples/collections.crn"
    assert output =~ "examples/math.crn"
    assert output =~ "examples/strings.crn"
    assert output =~ "examples/interop.crn"
    assert output =~ "practical:"
    assert output =~ "examples/practical/all_practical.crn"
    assert output =~ "examples/practical/main.crn"
    assert output =~ "examples/practical/ledger.crn"
    assert output =~ "examples/practical/todo.crn"
    assert output =~ "examples/practical/ledger_cli.crn"
    assert output =~ "examples/practical/expenses.crn"
    assert output =~ "examples/practical/cashflow.crn"
    assert output =~ "examples/practical/cashflow_alerts.crn"
    assert output =~ "examples/practical/mini_grep.crn"
    assert output =~ "examples/practical/mini_grep_verify.crn"
    assert output =~ "examples/practical/mini_env.crn"
    assert output =~ "examples/practical/mini_ini.crn"
    assert output =~ "concurrency:"
    assert output =~ "examples/concurrency/ping_pong_types.crn"
    assert output =~ "examples/concurrency/protocol_ping_pong.crn"
    assert output =~ "examples/concurrency/traffic_light_types.crn"
    assert output =~ "examples/concurrency/traffic_light.crn"
    assert output =~ "examples/concurrency/ping_once.crn"
    assert output =~ "examples/concurrency/self_boot.crn"
    assert output =~ "examples/concurrency/two_pings.crn"
    assert output =~ "examples/concurrency/counter.crn"
    assert output =~ "examples/concurrency/notifier.crn"
    assert output =~ "examples/concurrency/restart_once.crn"
    assert output =~ "examples/concurrency/supervisor_worker.crn"
    assert output =~ "examples/concurrency/guess_binary.crn"
    assert output =~ "ambitious:"
    assert output =~ "examples/ambitious/orchestrator.crn"
    assert output =~ "web:"
    assert output =~ "examples/web/hello_static.crn"
    assert output =~ "examples/web/todo_app.crn"
    assert output =~ "examples/web/afford_app.crn"
    assert output =~ "examples/web/afford_verify.crn"
    assert output =~ "prelude:"
    assert output =~ "examples/prelude/result_flow.crn"
    assert output =~ "examples/prelude/env_parse.crn"
    assert output =~ "examples/prelude/ini_parse.crn"
    assert output =~ "examples/prelude/web_helpers.crn"
    assert output =~ "diagnostics:"
    assert output =~ "examples/diagnostics/runtime_div_zero.crn"
    assert output =~ "prove:"
    assert output =~ "examples/prove/all_proven.crn"
  end

  test "prints run summary to stderr on successful run" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "cairn_run_summary_test.crn")
    File.write!(path, "1 2")

    Mix.Task.reenable("cairn.run")

    parent = self()

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        stdout =
          ExUnit.CaptureIO.capture_io(fn ->
            Mix.Tasks.Cairn.Run.run([path])
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
    path = Path.join(dir, "cairn_run_prelude_test.crn")
    File.write!(path, "1")

    Mix.Task.reenable("cairn.run")

    parent = self()

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        stdout =
          ExUnit.CaptureIO.capture_io(fn ->
            Mix.Tasks.Cairn.Run.run(["--show-prelude", path])
          end)

        send(parent, {:captured_stdout, stdout})
      end)

    stdout =
      receive do
        {:captured_stdout, out} -> out
      end

    assert stdout =~ "1"
    assert stderr =~ "PRELUDE: auto-load enabled"
    assert stderr =~ "lib/prelude/result.crn"
    assert stderr =~ "result_unwrap_or"
    assert stderr =~ "lib/prelude/str.crn"
    assert stderr =~ "csv_ints"
    assert stderr =~ "lib/prelude/config.crn"
    assert stderr =~ "env_map"
    assert stderr =~ "lib/prelude/ini.crn"
    assert stderr =~ "ini_map"
    assert stderr =~ "lib/prelude/web.crn"
    assert stderr =~ "http_html_ok"
    assert stderr =~ "html_escape"
    assert stderr =~ "http_text_method_not_allowed"
    assert stderr =~ "route_get_html_file"
    assert stderr =~ "lib/prelude.crn"
    assert stderr =~ "ask_or"
  end
end
