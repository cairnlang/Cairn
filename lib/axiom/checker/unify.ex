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

  # Block types unify with each other
  def unify({:block, _} = a, {:block, _}), do: {:ok, a}

  # Everything else fails
  def unify(_, _), do: :error
end
