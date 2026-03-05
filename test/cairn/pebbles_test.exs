defmodule Cairn.PebblesTest do
  use ExUnit.Case, async: false

  @pebbles_main "tools/pebbles/main.crn"

  setup do
    previous_db_dir = System.get_env("CAIRN_DB_DIR")
    previous_backend = Application.get_env(:cairn, :data_store_backend)

    dir = Path.join(System.tmp_dir!(), "cairn_pebbles_test_#{System.unique_integer([:positive])}")
    System.put_env("CAIRN_DB_DIR", dir)
    Application.put_env(:cairn, :data_store_backend, Cairn.DataStore.Backend.Mnesia)
    Cairn.DB.reset_for_tests!()

    on_exit(fn ->
      Cairn.DB.reset_for_tests!()

      if previous_db_dir do
        System.put_env("CAIRN_DB_DIR", previous_db_dir)
      else
        System.delete_env("CAIRN_DB_DIR")
      end

      if previous_backend do
        Application.put_env(:cairn, :data_store_backend, previous_backend)
      else
        Application.delete_env(:cairn, :data_store_backend)
      end
    end)

    :ok
  end

  test "shows usage for no args and unknown command" do
    assert run_pebbles([]) =~ "usage: pebbles <init|add|ls|next|do|done|block> [args]"
    assert run_pebbles(["wat"]) =~ "usage: pebbles <init|add|ls|next|do|done|block> [args]"
  end

  test "init, add, and ls round-trip through DataStore" do
    assert run_pebbles(["init"]) =~ "pebbles: initialized"
    assert run_pebbles(["ls"]) =~ "pebbles: no items"

    assert run_pebbles(["add", "first", "task"]) =~ "pebbles: added #1"
    assert run_pebbles(["add", "second"]) =~ "pebbles: added #2"

    lines =
      run_pebbles(["ls"])
      |> String.trim()
      |> String.split("\n")

    assert lines == ["#1 [open] first task", "#2 [open] second"]
  end

  test "next, do, done, and block enforce lifecycle transitions" do
    assert run_pebbles(["add", "first"]) =~ "pebbles: added #1"
    assert run_pebbles(["add", "second"]) =~ "pebbles: added #2"

    assert run_pebbles(["next"]) =~ "#1 [open] first"
    assert run_pebbles(["do", "1"]) =~ "#1 [doing] first"
    assert run_pebbles(["block", "2", "waiting", "on", "deps"]) =~ "#2 [blocked] second -- waiting on deps"
    assert run_pebbles(["done", "1"]) =~ "#1 [done] first"

    assert run_pebbles(["do", "1"]) =~ "pebbles: cannot move done pebble to doing"
    assert run_pebbles(["next"]) =~ "pebbles: no open items"
    assert run_pebbles(["done", "404"]) =~ "pebbles: unknown pebble #404"
  end

  test "cairn-native pebbles tests run through --test mode" do
    parent = self()

    stdout =
      ExUnit.CaptureIO.capture_io(fn ->
        stderr =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            assert :ok = Cairn.CLI.run(["--test", "tools/pebbles/test.crn"], halt_on_error: false)
          end)

        send(parent, {:captured_stderr, stderr})
      end)

    stderr =
      receive do
        {:captured_stderr, captured} -> captured
      end

    assert stdout =~ "PASS init keeps next id at least one"
    assert stdout =~ "PASS add returns monotonic ids"
    assert stdout =~ "PASS encoded row title round-trips through decode helper"
    assert stdout =~ "PASS do transition moves open pebble to doing"
    assert stdout =~ "PASS done transition rejects already done pebbles"
    assert stdout =~ "PASS block transition requires reason"
    assert stderr =~ "TEST SUMMARY: total=6 passed=6 failed=0"
  end

  defp run_pebbles(argv) do
    Process.put(:cairn_argv, argv)

    ExUnit.CaptureIO.capture_io(fn ->
      {stack, _env} = Cairn.eval_file(@pebbles_main)
      assert stack == []
    end)
  end
end
