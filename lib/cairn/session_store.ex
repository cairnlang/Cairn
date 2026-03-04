defmodule Cairn.SessionStore do
  @moduledoc """
  Minimal server-side session storage for Cairn web apps.

  The Cairn-facing API is session-oriented, not storage-oriented:
  - handlers receive a session map
  - handlers return an updated or cleared session map
  - this module hides the default Mnesia-backed persistence

  The current implementation deliberately reuses the bounded Cairn.DB layer.
  """

  alias Cairn.DB

  @cookie_name "cairn_session"
  @prefix "__session__:"

  def cookie_name, do: @cookie_name

  def load(session_id) when is_binary(session_id) do
    case DB.get(storage_key(session_id)) do
      {:ok, encoded} ->
        decode_session(encoded)

      :error ->
        :error
    end
  end

  def save(session_id, session) when is_binary(session_id) and is_map(session) do
    validate_session!(session)
    DB.put(storage_key(session_id), encode_session(session))
  end

  def delete(session_id) when is_binary(session_id) do
    DB.delete(storage_key(session_id))
  end

  def new_id do
    :crypto.strong_rand_bytes(24)
    |> Base.url_encode64(padding: false)
  end

  defp storage_key(session_id), do: @prefix <> session_id

  defp validate_session!(session) do
    unless Enum.all?(session, fn {key, value} -> is_binary(key) and is_binary(value) end) do
      raise Cairn.RuntimeError,
        "session data must be a map[str str], got #{inspect(session)}"
    end
  end

  defp encode_session(session) do
    session
    |> :erlang.term_to_binary()
    |> Base.encode64(padding: false)
  end

  defp decode_session(encoded) when is_binary(encoded) do
    with {:ok, binary} <- Base.decode64(encoded, padding: false),
         session when is_map(session) <- :erlang.binary_to_term(binary),
         true <- Enum.all?(session, fn {key, value} -> is_binary(key) and is_binary(value) end) do
      {:ok, session}
    else
      _ -> :error
    end
  end
end
