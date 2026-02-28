defmodule Cairn.CLITest do
  use ExUnit.Case, async: false

  setup do
    on_exit(fn -> System.delete_env("CAIRN_NO_PRELUDE") end)
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
  end

  test "prints examples index from standalone CLI" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert :ok = Cairn.CLI.run(["--examples"], halt_on_error: false)
      end)

    assert output =~ "Examples:"
    assert output =~ "basics:"
    assert output =~ "examples/hello_world.crn"
    assert output =~ "examples/practical/mini_grep.crn"
    assert output =~ "examples/practical/mini_env.crn"
    assert output =~ "examples/prelude/env_parse.crn"
    assert output =~ "examples/concurrency/guess_binary.crn"
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
end
