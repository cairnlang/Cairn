defmodule Cairn.UserStore do
  @moduledoc """
  Minimal user-store abstraction for bounded login demos.

  App code should think in terms of users and credentials, not raw DB keys.
  The default implementation is backed by the existing Mnesia key/value store.
  """

  @prefix "__user__:"

  def ensure_demo_users do
    ensure_user("alice", "cairn", "admin")
    ensure_user("bob", "cairn", "operator")
    :ok
  end

  def load(username) when is_binary(username) do
    ensure_demo_users()

    case Cairn.DB.get(user_key(username)) do
      {:ok, encoded} ->
        case decode_user(encoded) do
          {:ok, user} -> {:ok, user}
          :error -> :error
        end

      :error ->
        :error
    end
  end

  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    case load(username) do
      {:ok, %{"password" => ^password} = user} ->
        {:ok, %{"user" => user["user"], "role" => user["role"]}}

      _ ->
        :error
    end
  end

  defp ensure_user(username, password, role) do
    case Cairn.DB.get(user_key(username)) do
      {:ok, _value} ->
        :ok

      :error ->
        user =
          %{
            "user" => username,
            "password" => password,
            "role" => role
          }

        Cairn.DB.put(user_key(username), encode_user(user))
    end
  end

  defp user_key(username), do: @prefix <> username

  defp encode_user(user_map) do
    user_map
    |> :erlang.term_to_binary()
    |> Base.encode64()
  end

  defp decode_user(encoded) do
    with {:ok, binary} <- Base.decode64(encoded),
         user when is_map(user) <- :erlang.binary_to_term(binary),
         true <- valid_user?(user) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp valid_user?(%{"user" => user, "password" => password, "role" => role})
       when is_binary(user) and is_binary(password) and is_binary(role),
       do: true

  defp valid_user?(_), do: false
end
