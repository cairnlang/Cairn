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

  @spec put(String.t(), String.t()) :: :ok
  def put(key, value) when is_binary(key) and is_binary(value) do
    backend().put(key, value)
  end

  @spec get(String.t()) :: {:ok, String.t()} | :error
  def get(key) when is_binary(key) do
    backend().get(key)
  end

  @spec delete(String.t()) :: :ok
  def delete(key) when is_binary(key) do
    backend().delete(key)
  end

  @spec pairs() :: [kv_pair()]
  def pairs do
    backend().pairs()
  end

  defp backend do
    Application.get_env(:cairn, :data_store_backend, Cairn.DataStore.Backend.Mnesia)
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
end
