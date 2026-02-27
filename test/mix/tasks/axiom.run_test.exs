defmodule Mix.Tasks.Axiom.RunTest do
  use ExUnit.Case, async: false

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
end
