defmodule Cairn.DB do
  @moduledoc """
  Minimal Mnesia-backed key/value store for Cairn.

  This is intentionally narrow:
  - one fixed table
  - string keys
  - string values
  - local-node persistence only
  """

  @table :cairn_kv
  @default_dir ".cairn_mnesia"

  def put(key, value) when is_binary(key) and is_binary(value) do
    ensure_started()

    case :mnesia.transaction(fn -> :mnesia.write({@table, key, value}) end) do
      {:atomic, :ok} ->
        sync_log!()
        :ok

      {:aborted, reason} ->
        raise Cairn.RuntimeError, "DB_PUT failed: #{inspect(reason)}"
    end
  end

  def get(key) when is_binary(key) do
    ensure_started()

    case :mnesia.transaction(fn -> :mnesia.read(@table, key) end) do
      {:atomic, [{@table, ^key, value}]} -> {:ok, value}
      {:atomic, []} -> :error
      {:aborted, reason} -> raise Cairn.RuntimeError, "DB_GET failed: #{inspect(reason)}"
    end
  end

  def delete(key) when is_binary(key) do
    ensure_started()

    case :mnesia.transaction(fn -> :mnesia.delete({@table, key}) end) do
      {:atomic, :ok} ->
        sync_log!()
        :ok

      {:aborted, reason} ->
        raise Cairn.RuntimeError, "DB_DEL failed: #{inspect(reason)}"
    end
  end

  def pairs do
    ensure_started()

    case :mnesia.transaction(fn ->
           :mnesia.foldl(
             fn {@table, key, value}, acc -> [{:tuple, [key, value]} | acc] end,
             [],
             @table
           )
         end) do
      {:atomic, pairs} ->
        Enum.sort_by(pairs, fn {:tuple, [key, _]} -> key end)

      {:aborted, reason} ->
        raise Cairn.RuntimeError, "DB_PAIRS failed: #{inspect(reason)}"
    end
  end

  def refresh do
    # Mnesia keeps an in-memory copy; restarting reloads persisted state
    # produced by other short-lived Cairn processes using the same DB dir.
    if mnesia_running?() do
      :mnesia.stop()
      wait_until_stopped()
    end

    ensure_started()
    :ok
  end

  def reset_for_tests! do
    dir = data_dir()

    if mnesia_running?() do
      :mnesia.stop()
      wait_until_stopped()
    end

    File.rm_rf!(dir)
    Application.delete_env(:mnesia, :dir)
    :ok
  end

  def restart_for_tests! do
    if mnesia_running?() do
      :mnesia.stop()
      wait_until_stopped()
    end

    Application.delete_env(:mnesia, :dir)
    :ok
  end

  defp ensure_started do
    dir = configure_dir!()
    ensure_schema!(dir)

    unless mnesia_running?() do
      case Application.ensure_all_started(:mnesia) do
        {:ok, _} -> :ok
        {:error, reason} -> raise Cairn.RuntimeError, "cannot start Mnesia: #{inspect(reason)}"
      end
    end

    ensure_table!()
    :ok
  end

  defp configure_dir! do
    dir = data_dir()
    desired = String.to_charlist(dir)
    current = Application.get_env(:mnesia, :dir)

    cond do
      current == desired ->
        :ok

      mnesia_running?() ->
        :mnesia.stop()
        wait_until_stopped()
        Application.put_env(:mnesia, :dir, desired)

      true ->
        Application.put_env(:mnesia, :dir, desired)
    end

    dir
  end

  defp ensure_schema!(dir) do
    File.mkdir_p!(dir)
    schema_file = Path.join(dir, "schema.DAT")

    unless File.exists?(schema_file) do
      case :mnesia.create_schema([node()]) do
        :ok ->
          :ok

        {:error, {_, {:already_exists, _}}} ->
          :ok

        {:error, {:already_exists, _}} ->
          :ok

        {:error, reason} ->
          raise Cairn.RuntimeError, "cannot create Mnesia schema: #{inspect(reason)}"
      end
    end
  end

  defp ensure_table! do
    case :mnesia.create_table(@table, attributes: [:key, :value], disc_copies: [node()]) do
      {:atomic, :ok} ->
        :ok

      {:aborted, {:already_exists, @table}} ->
        :ok

      {:aborted, reason} ->
        raise Cairn.RuntimeError, "cannot create Mnesia table: #{inspect(reason)}"
    end

    case :mnesia.wait_for_tables([@table], 5_000) do
      :ok ->
        :ok

      {:timeout, tables} ->
        raise Cairn.RuntimeError, "Mnesia table wait timed out: #{inspect(tables)}"

      {:error, reason} ->
        raise Cairn.RuntimeError, "Mnesia table wait failed: #{inspect(reason)}"
    end
  end

  defp data_dir do
    path =
      case System.get_env("CAIRN_DB_DIR") do
        nil -> @default_dir
        "" -> @default_dir
        value -> value
      end

    Path.expand(path, File.cwd!())
  end

  defp mnesia_running? do
    try do
      :mnesia.system_info(:is_running) == :yes
    catch
      :exit, _ -> false
    end
  end

  defp wait_until_stopped do
    if mnesia_running?() do
      Process.sleep(25)
      wait_until_stopped()
    else
      :ok
    end
  end

  defp sync_log! do
    case :mnesia.sync_log() do
      :ok ->
        :ok

      {:error, reason} ->
        raise Cairn.RuntimeError, "Mnesia log sync failed: #{inspect(reason)}"
    end
  end
end
