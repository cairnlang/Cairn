defmodule Cairn.DBTest do
  use ExUnit.Case, async: false

  setup do
    previous = System.get_env("CAIRN_DB_DIR")
    previous_backend = Application.get_env(:cairn, :data_store_backend)
    dir = Path.join(System.tmp_dir!(), "cairn_db_test_#{System.unique_integer([:positive])}")

    System.put_env("CAIRN_DB_DIR", dir)
    Application.put_env(:cairn, :data_store_backend, Cairn.DataStore.Backend.Mnesia)
    Cairn.DB.reset_for_tests!()

    on_exit(fn ->
      Cairn.DB.reset_for_tests!()

      if previous do
        System.put_env("CAIRN_DB_DIR", previous)
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

  test "DB_PUT, DB_GET, DB_DEL, and DB_PAIRS round-trip string records" do
    assert [[]] = Cairn.eval("DB_PAIRS")

    assert [] = Cairn.eval("\"value one\" \"alpha\" DB_PUT")
    assert [] = Cairn.eval("\"value two\" \"beta\" DB_PUT")

    assert [{:variant, "result", "Ok", ["value one"]}] = Cairn.eval("\"alpha\" DB_GET")
    assert [{:variant, "result", "Ok", ["value two"]}] = Cairn.eval("\"beta\" DB_GET")

    assert [[{:tuple, ["alpha", "value one"]}, {:tuple, ["beta", "value two"]}]] =
             Cairn.eval("DB_PAIRS")

    assert [] = Cairn.eval("\"alpha\" DB_DEL")
    assert [{:variant, "result", "Err", ["missing key 'alpha'"]}] = Cairn.eval("\"alpha\" DB_GET")
    assert [[{:tuple, ["beta", "value two"]}]] = Cairn.eval("DB_PAIRS")
  end

  test "DB data survives a Mnesia restart in the same directory" do
    assert [] = Cairn.eval("\"persist me\" \"todo:1\" DB_PUT")

    Cairn.DB.restart_for_tests!()

    assert [{:variant, "result", "Ok", ["persist me"]}] = Cairn.eval("\"todo:1\" DB_GET")
  end

  test "DB_* runtime ops delegate through the DataStore boundary" do
    Application.put_env(:cairn, :data_store_backend, Cairn.TestDataStoreFake)
    Cairn.TestDataStoreFake.reset!()

    assert [[]] = Cairn.eval("DB_PAIRS")

    assert [] = Cairn.eval("\"value one\" \"alpha\" DB_PUT")
    assert [{:variant, "result", "Ok", ["value one"]}] = Cairn.eval("\"alpha\" DB_GET")
    assert [[{:tuple, ["alpha", "value one"]}]] = Cairn.eval("DB_PAIRS")

    assert [] = Cairn.eval("\"alpha\" DB_DEL")
    assert [{:variant, "result", "Err", ["missing key 'alpha'"]}] = Cairn.eval("\"alpha\" DB_GET")
  end
end

defmodule Cairn.TestDataStoreFake do
  @behaviour Cairn.DataStore

  def reset! do
    Process.put(:cairn_test_data_store_fake, %{})
    :ok
  end

  @impl true
  def put(key, value) do
    store = Process.get(:cairn_test_data_store_fake, %{})
    Process.put(:cairn_test_data_store_fake, Map.put(store, key, value))
    :ok
  end

  @impl true
  def get(key) do
    store = Process.get(:cairn_test_data_store_fake, %{})

    case Map.fetch(store, key) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  @impl true
  def delete(key) do
    store = Process.get(:cairn_test_data_store_fake, %{})
    Process.put(:cairn_test_data_store_fake, Map.delete(store, key))
    :ok
  end

  @impl true
  def pairs do
    Process.get(:cairn_test_data_store_fake, %{})
    |> Enum.map(fn {key, value} -> {:tuple, [key, value]} end)
    |> Enum.sort_by(fn {:tuple, [key, _]} -> key end)
  end
end
