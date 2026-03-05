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
    assert run_pebbles([]) =~
             "usage: pebbles <init|add|ls|next|do|done|block|note|reopen|edit|find|export|import> [args]"

    assert run_pebbles(["wat"]) =~
             "usage: pebbles <init|add|ls|next|do|done|block|note|reopen|edit|find|export|import> [args]"
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

    assert lines == [
             "pebbles: status=all total=2 open=2 doing=0 blocked=0 done=0",
             "#1 [open] first task",
             "#2 [open] second"
           ]
  end

  test "next, do, done, reopen, edit, and block enforce lifecycle transitions" do
    assert run_pebbles(["add", "first"]) =~ "pebbles: added #1"
    assert run_pebbles(["add", "second"]) =~ "pebbles: added #2"

    assert run_pebbles(["next"]) =~ "#1 [open] first"
    assert run_pebbles(["do", "1"]) =~ "#1 [doing] first"
    assert run_pebbles(["block", "2", "waiting", "on", "deps"]) =~ "#2 [blocked] second -- waiting on deps"
    assert run_pebbles(["note", "2", "waiting", "on", "review"]) =~
             "#2 [blocked] second -- waiting on deps (notes:1)"

    assert run_pebbles(["done", "1"]) =~ "#1 [done] first"
    assert run_pebbles(["reopen", "1"]) =~ "#1 [open] first"
    assert run_pebbles(["edit", "1", "first", "renamed"]) =~ "#1 [open] first renamed"
    assert run_pebbles(["reopen", "1"]) =~ "pebbles: already open"
    assert run_pebbles(["done", "1"]) =~ "#1 [done] first renamed"

    assert run_pebbles(["next"]) =~ "pebbles: no open items"
    assert run_pebbles(["done", "404"]) =~ "pebbles: unknown pebble #404"
  end

  test "ls filters and find search return bounded results" do
    assert run_pebbles(["add", "ship", "api"]) =~ "pebbles: added #1"
    assert run_pebbles(["add", "write", "docs"]) =~ "pebbles: added #2"
    assert run_pebbles(["do", "1"]) =~ "#1 [doing] ship api"
    assert run_pebbles(["block", "2", "waiting", "on", "qa"]) =~ "#2 [blocked] write docs -- waiting on qa"
    assert run_pebbles(["note", "2", "needs", "security", "review"]) =~
             "#2 [blocked] write docs -- waiting on qa (notes:1)"

    filtered =
      run_pebbles(["ls", "blocked"])
      |> String.trim()
      |> String.split("\n")

    assert filtered == [
             "pebbles: status=blocked total=1 open=0 doing=0 blocked=1 done=0",
             "#2 [blocked] write docs -- waiting on qa (notes:1)"
           ]

    assert run_pebbles(["find", "SECURITY"]) =~ "#2 [blocked] write docs -- waiting on qa (notes:1)"
    assert run_pebbles(["find", "nonexistent"]) =~ "pebbles: no matches for nonexistent"
  end

  test "export and import snapshot round-trip state and next id" do
    snapshot_path = Path.join(System.tmp_dir!(), "pebbles_snapshot_#{System.unique_integer([:positive])}.txt")

    assert run_pebbles(["add", "first"]) =~ "pebbles: added #1"
    assert run_pebbles(["add", "second"]) =~ "pebbles: added #2"
    assert run_pebbles(["do", "1"]) =~ "#1 [doing] first"
    assert run_pebbles(["block", "2", "waiting", "on", "deploy"]) =~ "#2 [blocked] second -- waiting on deploy"
    assert run_pebbles(["note", "2", "follow", "up"]) =~ "#2 [blocked] second -- waiting on deploy (notes:1)"

    assert run_pebbles(["export", snapshot_path]) =~ "pebbles: exported 3 rows"
    assert File.exists?(snapshot_path)

    assert run_pebbles(["done", "1"]) =~ "#1 [done] first"
    assert run_pebbles(["add", "third"]) =~ "pebbles: added #3"

    assert run_pebbles(["import", snapshot_path]) =~ "pebbles: imported 3 rows"

    lines =
      run_pebbles(["ls"])
      |> String.trim()
      |> String.split("\n")

    assert lines == [
             "pebbles: status=all total=2 open=0 doing=1 blocked=1 done=0",
             "#1 [doing] first",
             "#2 [blocked] second -- waiting on deploy (notes:1)"
           ]

    assert run_pebbles(["add", "after-import"]) =~ "pebbles: added #3"
  end

  test "import rejects invalid header and keeps existing state" do
    snapshot_path = Path.join(System.tmp_dir!(), "pebbles_bad_snapshot_#{System.unique_integer([:positive])}.txt")
    File.write!(snapshot_path, "oops\npebble/000000000001\topen|x||\n")

    assert run_pebbles(["add", "keep"]) =~ "pebbles: added #1"
    assert run_pebbles(["import", snapshot_path]) =~
             "pebbles: invalid snapshot header (expected pebbles-v1)"

    assert run_pebbles(["ls"]) =~ "#1 [open] keep"
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
    assert stdout =~ "PASS note transition prepends newest note"
    assert stdout =~ "PASS store note appends through command boundary"
    assert stdout =~ "PASS snapshot line parser preserves key and value"
    assert stdout =~ "PASS import lines rejects invalid header without clearing store"
    assert stdout =~ "PASS snapshot export and import round-trips rows and next id"
    assert stdout =~ "PASS reopen transition moves done pebble to open"
    assert stdout =~ "PASS edit transition requires non-empty title"
    assert stdout =~ "PASS text search matches notes and title case-insensitively"
    assert stdout =~ "PASS store reopen and edit persist updated fields"
    assert stderr =~ "TEST SUMMARY: total=15 passed=15 failed=0"
  end

  defp run_pebbles(argv) do
    Process.put(:cairn_argv, argv)

    ExUnit.CaptureIO.capture_io(fn ->
      {stack, _env} = Cairn.eval_file(@pebbles_main)
      assert stack == []
    end)
  end
end
