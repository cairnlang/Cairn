defmodule Axiom.Checker.Unify do
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

  # Map unification
  def unify({:map, k1, v1}, {:map, k2, v2}) do
    with {:ok, k} <- unify(k1, k2),
         {:ok, v} <- unify(v1, v2) do
      {:ok, {:map, k, v}}
    else
      _ -> :error
    end
  end

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
end
