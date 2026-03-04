defmodule Cairn.CLITest do
  use ExUnit.Case, async: false

  setup do
    on_exit(fn ->
      System.delete_env("CAIRN_NO_PRELUDE")
      System.delete_env("CAIRN_SKIP_ASSURANCE")
    end)
    :ok
  end

  test "prints standalone help text" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = Cairn.CLI.run(["--help"], halt_on_error: false)
      end)

    assert output =~ "Usage:"
    assert output =~ "cairn [options]"
    assert output =~ "No file given     Start the REPL"
    assert output =~ "CAIRN_NO_PRELUDE=1"
    assert output =~ "CAIRN_SKIP_ASSURANCE=1"
  end

  test "prints examples index from standalone CLI" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = Cairn.CLI.run(["--examples"], halt_on_error: false)
      end)

    assert output =~ "Examples:"
    assert output =~ "basics:"
    assert output =~ "examples/hello_world.crn"
    assert output =~ "examples/generics.crn"
    assert output =~ "examples/practical/mini_grep.crn"
    assert output =~ "examples/practical/mini_env.crn"
    assert output =~ "examples/practical/mini_ini.crn"
    assert output =~ "examples/prelude/env_parse.crn"
    assert output =~ "examples/prelude/ini_parse.crn"
    assert output =~ "examples/prelude/web_helpers.crn"
    assert output =~ "examples/concurrency/guess_binary.crn"
    assert output =~ "ambitious:"
    assert output =~ "examples/ambitious/orchestrator.crn"
    assert output =~ "policy:"
    assert output =~ "examples/policy/approval/main.crn"
    assert output =~ "examples/policy/approval/verify.crn"
    assert output =~ "web:"
    assert output =~ "examples/web/hello_static.crn"
    assert output =~ "examples/web/session_demo.crn"
    assert output =~ "examples/web/todo_app.crn"
    assert output =~ "examples/web/afford_app.crn"
    assert output =~ "examples/web/afford_verify.crn"
  end

  test "no args dispatches to the REPL in standalone mode" do
    parent = self()

    repl = fn ->
      send(parent, :repl_started)
    end

    assert :ok = Cairn.CLI.run([], halt_on_error: false, repl: repl)

    assert_receive :repl_started
  end

  test "file mode passes remaining args through ARGV" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "cairn_cli_argv_test.crn")
    File.write!(path, "ARGV LEN SAID")

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = Cairn.CLI.run([path, "alpha", "beta"], halt_on_error: false)
      end)

    assert output =~ "2"
    assert Process.get(:cairn_argv) == ["alpha", "beta"]
  end

  test "file mode stops option parsing at the script path" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "cairn_cli_flag_argv_test.crn")
    File.write!(path, "ARGV HEAD SAID")

    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = Cairn.CLI.run([path, "-n", "value"], halt_on_error: false)
      end)

    assert output =~ "-n"
    assert Process.get(:cairn_argv) == ["-n", "value"]
  end

  test "file mode supports json diagnostics" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "cairn_cli_error_test.crn")
    File.write!(path, "1 ADD")

    stderr =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert :error = Cairn.CLI.run(["--json-errors", path], halt_on_error: false)
      end)

    assert stderr =~ "\"kind\":\"static\""
    assert stderr =~ "RUN SUMMARY: status=error kind=static"
  end

  test "native test mode runs Cairn TEST blocks and prints a summary" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        stderr =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            assert :ok = Cairn.CLI.run(["--test", "examples/web/afford_test.crn"], halt_on_error: false)
          end)

        send(self(), {:test_stderr, stderr})
      end)

    stderr =
      receive do
        {:test_stderr, captured} -> captured
      end

    assert output =~ "PASS safe one-time purchase remains safe"
    assert output =~ "PASS score 2 maps to the strongest warning"
    assert stderr =~ "TEST SUMMARY: total=6 passed=6 failed=0"
  end
end
