defmodule Cairn.DataStore do
  @moduledoc """
  Runtime-side boundary for application key/value data access.

  Cairn built-ins (`DB_PUT`, `DB_GET`, `DB_DEL`, `DB_PAIRS`) delegate here so
  backend selection stays outside Cairn app code.
  """

  @type kv_pair :: {:tuple, [String.t()]}

  @callback put(String.t(), String.t()) :: :ok
  @callback get(String.t()) :: {:ok, String.t()} | :error
  @callback delete(String.t()) :: :ok
  @callback pairs() :: [kv_pair()]
  @callback refresh() :: :ok

  @spec put(String.t(), String.t()) :: :ok
  def put(key, value) when is_binary(key) and is_binary(value) do
    backend_module().put(key, value)
  end

  @spec get(String.t()) :: {:ok, String.t()} | :error
  def get(key) when is_binary(key) do
    backend_module().get(key)
  end

  @spec delete(String.t()) :: :ok
  def delete(key) when is_binary(key) do
    backend_module().delete(key)
  end

  @spec pairs() :: [kv_pair()]
  def pairs do
    backend_module().pairs()
  end

  @spec refresh() :: :ok
  def refresh do
    backend_module().refresh()
  end

  @spec backend_module() :: module()
  def backend_module do
    from_env_backend() ||
      Application.get_env(:cairn, :data_store_backend, Cairn.DataStore.Backend.Mnesia)
  end

  defp from_env_backend do
    case System.get_env("CAIRN_DATA_STORE_BACKEND") do
      nil -> nil
      "" -> nil
      "mnesia" -> Cairn.DataStore.Backend.Mnesia
      "postgres" -> Cairn.DataStore.Backend.Postgres
      other -> raise Cairn.RuntimeError, "unknown CAIRN_DATA_STORE_BACKEND=#{inspect(other)}"
    end
  end
end

defmodule Cairn.DataStore.Backend.Mnesia do
  @moduledoc false

  @behaviour Cairn.DataStore

  @impl true
  def put(key, value), do: Cairn.DB.put(key, value)

  @impl true
  def get(key), do: Cairn.DB.get(key)

  @impl true
  def delete(key), do: Cairn.DB.delete(key)

  @impl true
  def pairs, do: Cairn.DB.pairs()

  @impl true
  def refresh, do: Cairn.DB.refresh()
end

defmodule Cairn.DataStore.Backend.Postgres do
  @moduledoc false

  @behaviour Cairn.DataStore

  @table "cairn_kv"

  @impl true
  def put(key, value) when is_binary(key) and is_binary(value) do
    with_conn(fn conn ->
      ensure_table!(conn)

      query!(
        conn,
        "INSERT INTO #{@table} (key, value) VALUES ($1, $2) ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value",
        [key, value],
        "DB_PUT"
      )

      :ok
    end)
  end

  @impl true
  def get(key) when is_binary(key) do
    with_conn(fn conn ->
      ensure_table!(conn)

      case query!(conn, "SELECT value FROM #{@table} WHERE key = $1", [key], "DB_GET").rows do
        [[value]] -> {:ok, value}
        [] -> :error
      end
    end)
  end

  @impl true
  def delete(key) when is_binary(key) do
    with_conn(fn conn ->
      ensure_table!(conn)
      query!(conn, "DELETE FROM #{@table} WHERE key = $1", [key], "DB_DEL")
      :ok
    end)
  end

  @impl true
  def pairs do
    with_conn(fn conn ->
      ensure_table!(conn)

      query!(conn, "SELECT key, value FROM #{@table} ORDER BY key ASC", [], "DB_PAIRS").rows
      |> Enum.map(fn [key, value] -> {:tuple, [key, value]} end)
    end)
  end

  @impl true
  def refresh, do: :ok

  defp with_conn(fun) when is_function(fun, 1) do
    ensure_postgrex!()

    opts = connection_options()

    case Postgrex.start_link(opts) do
      {:ok, conn} ->
        try do
          fun.(conn)
        after
          GenServer.stop(conn)
        end

      {:error, reason} ->
        raise Cairn.RuntimeError, "Postgres connection failed: #{inspect(reason)}"
    end
  end

  defp ensure_table!(conn) do
    query!(
      conn,
      "CREATE TABLE IF NOT EXISTS #{@table} (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
      [],
      "DB_BOOT"
    )

    :ok
  end

  defp query!(conn, statement, params, op) do
    case Postgrex.query(conn, statement, params) do
      {:ok, result} ->
        result

      {:error, reason} ->
        raise Cairn.RuntimeError, "#{op} failed via Postgres: #{inspect(reason)}"
    end
  end

  defp ensure_postgrex! do
    unless Code.ensure_loaded?(Postgrex) do
      raise Cairn.RuntimeError,
            "Postgres backend requires :postgrex dependency; run `mix deps.get` and rebuild"
    end
  end

  defp connection_options do
    configured = Application.get_env(:cairn, :data_store_postgres, %{})

    host = pg_env("CAIRN_PG_HOST", configured, :host, "127.0.0.1")
    port = pg_env("CAIRN_PG_PORT", configured, :port, 5432)
    database = pg_env("CAIRN_PG_DATABASE", configured, :database, "cairn")
    username = pg_env("CAIRN_PG_USER", configured, :username, "postgres")
    password = pg_env("CAIRN_PG_PASSWORD", configured, :password, "postgres")
    ssl = pg_ssl_option(pg_env("CAIRN_PG_SSLMODE", configured, :sslmode, "disable"))
    timeout = pg_env("CAIRN_PG_TIMEOUT_MS", configured, :timeout, 5_000)

    [
      hostname: host,
      port: int_value(port, "CAIRN_PG_PORT"),
      database: database,
      username: username,
      password: password,
      ssl: ssl,
      timeout: int_value(timeout, "CAIRN_PG_TIMEOUT_MS")
    ]
  end

  defp pg_env(env_key, configured, conf_key, default) do
    case System.get_env(env_key) do
      nil ->
        Map.get(configured, conf_key, default)

      "" ->
        Map.get(configured, conf_key, default)

      value ->
        value
    end
  end

  defp pg_ssl_option("disable"), do: false
  defp pg_ssl_option("require"), do: true

  defp pg_ssl_option(other) do
    raise Cairn.RuntimeError,
          "unsupported CAIRN_PG_SSLMODE=#{inspect(other)} (supported: disable, require)"
  end

  defp int_value(value, _name) when is_integer(value), do: value

  defp int_value(value, name) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> raise Cairn.RuntimeError, "#{name} must be an integer, got #{inspect(value)}"
    end
  end
end
