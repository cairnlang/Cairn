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

defmodule Cairn.DBPostgresIntegrationTest do
  use ExUnit.Case, async: false

  @run_pg? System.get_env("CAIRN_PG_TEST") == "1"

  setup do
    cond do
      not @run_pg? ->
        {:ok, skip: "set CAIRN_PG_TEST=1 to run Postgres integration tests"}

      true ->
        case test_connection_status() do
          :ok ->
            previous_backend = Application.get_env(:cairn, :data_store_backend)
            previous_backend_env = System.get_env("CAIRN_DATA_STORE_BACKEND")

            Application.put_env(:cairn, :data_store_backend, Cairn.DataStore.Backend.Postgres)
            System.put_env("CAIRN_DATA_STORE_BACKEND", "postgres")

            _ = clear_pg_table!()

            on_exit(fn ->
              _ = clear_pg_table!()

              if previous_backend do
                Application.put_env(:cairn, :data_store_backend, previous_backend)
              else
                Application.delete_env(:cairn, :data_store_backend)
              end

              if previous_backend_env do
                System.put_env("CAIRN_DATA_STORE_BACKEND", previous_backend_env)
              else
                System.delete_env("CAIRN_DATA_STORE_BACKEND")
              end
            end)

            :ok

          {:error, reason} ->
            {:ok, skip: "Postgres not reachable for integration test: #{inspect(reason)}"}
        end
    end
  end

  test "DB_* round trips against Postgres backend when enabled" do
    suffix = Integer.to_string(System.unique_integer([:positive]))
    key_a = "pg_test:alpha:" <> suffix
    key_b = "pg_test:beta:" <> suffix

    assert [] = Cairn.eval("\"value one\" \"#{key_a}\" DB_PUT")
    assert [] = Cairn.eval("\"value two\" \"#{key_b}\" DB_PUT")

    assert [{:variant, "result", "Ok", ["value one"]}] = Cairn.eval("\"#{key_a}\" DB_GET")
    assert [{:variant, "result", "Ok", ["value two"]}] = Cairn.eval("\"#{key_b}\" DB_GET")

    [pairs] = Cairn.eval("DB_PAIRS")
    assert Enum.any?(pairs, fn {:tuple, [k, v]} -> k == key_a and v == "value one" end)
    assert Enum.any?(pairs, fn {:tuple, [k, v]} -> k == key_b and v == "value two" end)

    assert [] = Cairn.eval("\"#{key_a}\" DB_DEL")

    expected_missing = "missing key '#{key_a}'"
    assert [{:variant, "result", "Err", [^expected_missing]}] = Cairn.eval("\"#{key_a}\" DB_GET")

    assert [] = Cairn.eval("\"#{key_b}\" DB_DEL")
  end

  defp clear_pg_table! do
    opts = postgres_options()

    case Postgrex.start_link(opts) do
      {:ok, conn} ->
        _ = Postgrex.query(conn, "DROP TABLE IF EXISTS cairn_kv", [])
        GenServer.stop(conn)
        :ok

      {:error, reason} ->
        raise "cannot connect to Postgres for CAIRN_PG_TEST=1: #{inspect(reason)}"
    end
  end

  defp test_connection_status do
    opts = postgres_options()

    case Postgrex.start_link(opts) do
      {:ok, conn} ->
        status =
          case Postgrex.query(conn, "SELECT 1", []) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end

        GenServer.stop(conn)
        status

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp postgres_options do
    [
      hostname: System.get_env("CAIRN_PG_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("CAIRN_PG_PORT", "5432")),
      database: System.get_env("CAIRN_PG_DATABASE", "cairn"),
      username: System.get_env("CAIRN_PG_USER", "postgres"),
      password: System.get_env("CAIRN_PG_PASSWORD", "postgres"),
      ssl: System.get_env("CAIRN_PG_SSLMODE", "disable") == "require",
      timeout: String.to_integer(System.get_env("CAIRN_PG_TIMEOUT_MS", "5000"))
    ]
  end
end
