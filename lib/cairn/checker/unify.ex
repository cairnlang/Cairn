defmodule Cairn.Checker.Unify do
  @moduledoc """
  Type unification for the static type checker.

  Handles concrete types, the :num pseudo-type (int or float),
  :any (universal type), and type variables.
  """

  @doc """
  Unify two types. Returns `{:ok, unified_type}` or `:error`.

  Rules:
  - :any unifies with anything (result is the other type)
  - :num unifies with :int, :float, or :num
  - Concrete types unify with themselves
  - {:list, a} unifies with {:list, b} if a unifies with b
  - {:tvar, _} unifies with anything (result is the other type)
  - {:block, _} unifies with {:block, _}
  """
  @spec unify(term(), term()) :: {:ok, term()} | :error
  def unify(a, a), do: {:ok, a}

  # String literal refinement unifies with general strings.
  def unify({:lit_str, _}, :str), do: {:ok, :str}
  def unify(:str, {:lit_str, _}), do: {:ok, :str}
  def unify({:lit_str, _a}, {:lit_str, _b}), do: {:ok, :str}

  # :any unifies with everything
  def unify(:any, b), do: {:ok, b}
  def unify(a, :any), do: {:ok, a}

  # :num unifies with numeric types
  def unify(:num, :int), do: {:ok, :int}
  def unify(:num, :float), do: {:ok, :float}
  def unify(:num, :num), do: {:ok, :num}
  def unify(:int, :num), do: {:ok, :int}
  def unify(:float, :num), do: {:ok, :float}

  # Type variables unify with anything
  def unify({:tvar, _}, b), do: {:ok, b}
  def unify(a, {:tvar, _}), do: {:ok, a}

  # List unification
  def unify({:list, a}, {:list, b}) do
    case unify(a, b) do
      {:ok, unified} -> {:ok, {:list, unified}}
      :error -> :error
    end
  end

  # Tuple unification
  def unify({:tuple, a_elems}, {:tuple, b_elems}) when length(a_elems) == length(b_elems) do
    Enum.zip(a_elems, b_elems)
    |> Enum.reduce_while({:ok, []}, fn {a, b}, {:ok, acc} ->
      case unify(a, b) do
        {:ok, unified} -> {:cont, {:ok, [unified | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, elems} -> {:ok, {:tuple, Enum.reverse(elems)}}
      :error -> :error
    end
  end

  # Map unification
  def unify({:map, k1, v1}, {:map, k2, v2}) do
    with {:ok, k} <- unify(k1, k2),
         {:ok, v} <- unify(v1, v2) do
      {:ok, {:map, k, v}}
    else
      _ -> :error
    end
  end

  # Map shape refinement unifies with plain maps by key/value shape.
  def unify({:map_shape, _fields, k1, v1}, {:map, k2, v2}), do: unify({:map, k1, v1}, {:map, k2, v2})
  def unify({:map, k1, v1}, {:map_shape, _fields, k2, v2}), do: unify({:map, k1, v1}, {:map, k2, v2})

  def unify({:map_shape, _fields1, k1, v1}, {:map_shape, _fields2, k2, v2}),
    do: unify({:map, k1, v1}, {:map, k2, v2})

  # Pid unification
  def unify({:pid, a}, {:pid, b}) do
    case unify(a, b) do
      {:ok, unified} -> {:ok, {:pid, unified}}
      :error -> :error
    end
  end

  # Monitor unification
  def unify({:monitor, a}, {:monitor, b}) do
    case unify(a, b) do
      {:ok, unified} -> {:ok, {:monitor, unified}}
      :error -> :error
    end
  end

  # Block return-shape unification
  def unify({:block, {:returns, a}}, {:block, {:returns, b}}) do
    case unify(a, b) do
      {:ok, unified} -> {:ok, {:block, {:returns, unified}}}
      :error -> :error
    end
  end

  def unify({:block, {:returns, _}} = a, {:block, _}), do: {:ok, a}
  def unify({:block, _}, {:block, {:returns, _}} = b), do: {:ok, b}

  # Block types unify with each other
  def unify({:block, _} = a, {:block, _}), do: {:ok, a}

  def unify({:user_type, n, a_args}, {:user_type, n, b_args}) when length(a_args) == length(b_args) do
    unify_type_lists(a_args, b_args)
    |> case do
      {:ok, args} -> {:ok, {:user_type, n, args}}
      :error -> :error
    end
  end

  def unify(type_name, {:user_type, type_name, []}) when is_binary(type_name), do: {:ok, type_name}
  def unify({:user_type, type_name, []}, type_name) when is_binary(type_name), do: {:ok, type_name}

  def unify(type_name, {:user_type, type_name}) when is_binary(type_name), do: {:ok, type_name}
  def unify({:user_type, type_name}, type_name) when is_binary(type_name), do: {:ok, type_name}

  def unify({:tagged_variant, type_name, _ctor, type_args}, {:user_type, type_name, expected_args})
      when length(type_args) == length(expected_args) do
    unify_type_lists(type_args, expected_args)
    |> case do
      {:ok, args} -> {:ok, {:user_type, type_name, args}}
      :error -> :error
    end
  end

  def unify({:user_type, type_name, expected_args}, {:tagged_variant, type_name, _ctor, type_args})
      when length(type_args) == length(expected_args) do
    unify({:tagged_variant, type_name, :_, type_args}, {:user_type, type_name, expected_args})
  end

  def unify({:tagged_variant, type_name, _ctor, _type_args}, {:user_type, type_name}),
    do: {:ok, {:user_type, type_name}}

  def unify({:user_type, type_name}, {:tagged_variant, type_name, _ctor, _type_args}),
    do: {:ok, {:user_type, type_name}}

  def unify({:tagged_variant, type_name, _ctor, []}, expected_type_name) when is_binary(expected_type_name) and expected_type_name == type_name,
    do: {:ok, expected_type_name}

  def unify(expected_type_name, {:tagged_variant, type_name, _ctor, []}) when is_binary(expected_type_name) and expected_type_name == type_name,
    do: {:ok, expected_type_name}

  def unify({:tagged_variant, type_name, _ctor}, expected_type_name) when is_binary(expected_type_name) and expected_type_name == type_name,
    do: {:ok, expected_type_name}

  def unify(expected_type_name, {:tagged_variant, type_name, _ctor}) when is_binary(expected_type_name) and expected_type_name == type_name,
    do: {:ok, expected_type_name}

  def unify({:tagged_variant, type_name, ctor, type_args_a}, {:tagged_variant, type_name, ctor, type_args_b})
      when length(type_args_a) == length(type_args_b) do
    unify_type_lists(type_args_a, type_args_b)
    |> case do
      {:ok, args} -> {:ok, {:tagged_variant, type_name, ctor, args}}
      :error -> :error
    end
  end

  def unify({:tagged_variant, type_name, _ctor_a, type_args_a}, {:tagged_variant, type_name, _ctor_b, type_args_b})
      when length(type_args_a) == length(type_args_b) do
    unify_type_lists(type_args_a, type_args_b)
    |> case do
      {:ok, args} -> {:ok, {:user_type, type_name, args}}
      :error -> :error
    end
  end

  # Tagged constructor values unify with their declared sum type
  def unify({:tagged_variant, type_name, _ctor}, {:user_type, type_name}),
    do: {:ok, {:user_type, type_name}}

  def unify({:user_type, type_name}, {:tagged_variant, type_name, _ctor}),
    do: {:ok, {:user_type, type_name}}

  def unify({:tagged_variant, type_name, ctor}, {:tagged_variant, type_name, ctor}),
    do: {:ok, {:tagged_variant, type_name, ctor}}

  def unify({:tagged_variant, type_name, _ctor_a}, {:tagged_variant, type_name, _ctor_b}),
    do: {:ok, {:user_type, type_name}}

  # User-defined types unify when they name the same type
  def unify({:user_type, n}, {:user_type, n}), do: {:ok, {:user_type, n}}

  # Everything else fails
  def unify(_, _), do: :error

  defp unify_type_lists(a_types, b_types) do
    Enum.zip(a_types, b_types)
    |> Enum.reduce_while({:ok, []}, fn {a, b}, {:ok, acc} ->
      case unify(a, b) do
        {:ok, unified} -> {:cont, {:ok, [unified | acc]}}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, types} -> {:ok, Enum.reverse(types)}
      :error -> :error
    end
  end
end
