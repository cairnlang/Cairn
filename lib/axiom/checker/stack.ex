defmodule Axiom.Checker.Stack do
  @moduledoc """
  Symbolic stack for the static type checker.

  Holds type entries instead of values. Head of items = top of stack.
  """

  defstruct items: []

  @type type_entry ::
          :int
          | :float
          | :bool
          | :str
          | :any
          | :void
          | :num
          | {:list, type_entry}
          | {:tvar, integer()}
          | {:block, [Axiom.Types.token()]}

  @type t :: %__MODULE__{items: [type_entry]}

  @doc "Create a new empty symbolic stack."
  @spec new() :: t()
  def new, do: %__MODULE__{items: []}

  @doc "Push a type onto the stack."
  @spec push(t(), type_entry) :: t()
  def push(%__MODULE__{items: items}, type) do
    %__MODULE__{items: [type | items]}
  end

  @doc "Pop the top type from the stack."
  @spec pop(t()) :: {:ok, type_entry, t()} | :underflow
  def pop(%__MODULE__{items: []}), do: :underflow

  def pop(%__MODULE__{items: [top | rest]}) do
    {:ok, top, %__MODULE__{items: rest}}
  end

  @doc "Pop N types from the stack. Returns {types, remaining_stack} or :underflow."
  @spec pop_n(t(), non_neg_integer()) :: {[type_entry], t()} | :underflow
  def pop_n(stack, 0), do: {[], stack}

  def pop_n(%__MODULE__{items: items}, n) when length(items) >= n do
    {popped, rest} = Enum.split(items, n)
    {popped, %__MODULE__{items: rest}}
  end

  def pop_n(_, _), do: :underflow

  @doc "Peek at the top type without removing it."
  @spec peek(t()) :: {:ok, type_entry} | :underflow
  def peek(%__MODULE__{items: []}), do: :underflow
  def peek(%__MODULE__{items: [top | _]}), do: {:ok, top}

  @doc "Return the depth (number of items) on the stack."
  @spec depth(t()) :: non_neg_integer()
  def depth(%__MODULE__{items: items}), do: length(items)

  @doc "Reverse the stack items (used after building a result stack)."
  @spec reverse(t()) :: t()
  def reverse(%__MODULE__{items: items}) do
    %__MODULE__{items: Enum.reverse(items)}
  end
end
