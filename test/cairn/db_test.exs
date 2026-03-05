defmodule Cairn.DBTest do
  use ExUnit.Case, async: false

  setup do
    previous = System.get_env("CAIRN_DB_DIR")
    dir = Path.join(System.tmp_dir!(), "cairn_db_test_#{System.unique_integer([:positive])}")

    System.put_env("CAIRN_DB_DIR", dir)
    Cairn.DB.reset_for_tests!()

    on_exit(fn ->
      Cairn.DB.reset_for_tests!()

      if previous do
        System.put_env("CAIRN_DB_DIR", previous)
      else
        System.delete_env("CAIRN_DB_DIR")
      end
    end)

    :ok
  end

  test "DB_PUT, DB_GET, DB_DEL, and DB_PAIRS round-trip string records" do
    assert [[]] = Cairn.eval("DB_PAIRS")

    assert [] = Cairn.eval("\"value one\" \"alpha\" DB_PUT")
    assert [] = Cairn.eval("\"value two\" \"beta\" DB_PUT")

    assert [{:variant, "result", "Ok", ["value one"]}] = Cairn.eval("\"alpha\" DB_GET")
    assert [{:variant, "result", "Ok", ["value two"]}] = Cairn.eval("\"beta\" DB_GET")
    assert [[{:tuple, ["alpha", "value one"]}, {:tuple, ["beta", "value two"]}]] = Cairn.eval("DB_PAIRS")

    assert [] = Cairn.eval("\"alpha\" DB_DEL")
    assert [{:variant, "result", "Err", ["missing key 'alpha'"]}] = Cairn.eval("\"alpha\" DB_GET")
    assert [[{:tuple, ["beta", "value two"]}]] = Cairn.eval("DB_PAIRS")
  end

  test "DB data survives a Mnesia restart in the same directory" do
    assert [] = Cairn.eval("\"persist me\" \"todo:1\" DB_PUT")

    Cairn.DB.restart_for_tests!()

    assert [{:variant, "result", "Ok", ["persist me"]}] = Cairn.eval("\"todo:1\" DB_GET")
  end
end
