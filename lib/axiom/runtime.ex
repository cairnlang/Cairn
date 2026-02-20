defmodule Axiom.Runtime do
  @moduledoc """
  Stack-based runtime for Axiom operators.

  Every operator takes a stack (list, top element first) and returns a new stack.
  """

  # Arithmetic — binary, pop 2 push 1
  def execute(:add, [a, b | rest]) when is_number(a) and is_number(b), do: [b + a | rest]
  def execute(:sub, [a, b | rest]) when is_number(a) and is_number(b), do: [b - a | rest]
  def execute(:mul, [a, b | rest]) when is_number(a) and is_number(b), do: [b * a | rest]

  def execute(:div, [a, b | rest]) when is_number(a) and is_number(b) do
    if a == 0, do: raise(Axiom.RuntimeError, "division by zero")
    [div(b, a) | rest]
  end

  def execute(:mod, [a, b | rest]) when is_integer(a) and is_integer(b), do: [rem(b, a) | rest]

  # Arithmetic — unary, pop 1 push 1
  def execute(:sq, [a | rest]) when is_number(a), do: [a * a | rest]
  def execute(:abs, [a | rest]) when is_number(a), do: [Kernel.abs(a) | rest]
  def execute(:neg, [a | rest]) when is_number(a), do: [-a | rest]

  # Comparison — pop 2, push bool
  def execute(:eq, [a, b | rest]), do: [b == a | rest]
  def execute(:neq, [a, b | rest]), do: [b != a | rest]
  def execute(:gt, [a, b | rest]) when is_number(a) and is_number(b), do: [b > a | rest]
  def execute(:lt, [a, b | rest]) when is_number(a) and is_number(b), do: [b < a | rest]
  def execute(:gte, [a, b | rest]) when is_number(a) and is_number(b), do: [b >= a | rest]
  def execute(:lte, [a, b | rest]) when is_number(a) and is_number(b), do: [b <= a | rest]

  # Logic
  def execute(:and, [a, b | rest]) when is_boolean(a) and is_boolean(b), do: [b and a | rest]
  def execute(:or, [a, b | rest]) when is_boolean(a) and is_boolean(b), do: [b or a | rest]
  def execute(:not, [a | rest]) when is_boolean(a), do: [not a | rest]

  # Stack manipulation
  def execute(:dup, [a | rest]), do: [a, a | rest]
  def execute(:drop, [_ | rest]), do: rest
  def execute(:swap, [a, b | rest]), do: [b, a | rest]
  def execute(:over, [a, b | rest]), do: [b, a, b | rest]
  def execute(:rot, [a, b, c | rest]), do: [c, a, b | rest]

  # List operations — basic
  def execute(:len, [list | rest]) when is_list(list), do: [length(list) | rest]
  def execute(:head, [[h | _] | rest]), do: [h | rest]
  def execute(:tail, [[_ | t] | rest]), do: [t | rest]
  def execute(:cons, [list, elem | rest]) when is_list(list), do: [[elem | list] | rest]
  def execute(:concat, [b, a | rest]) when is_list(a) and is_list(b), do: [a ++ b | rest]
  def execute(:sum, [list | rest]) when is_list(list), do: [Enum.sum(list) | rest]

  # List operations — higher-order (take a block from the stack)
  # Blocks are {:block, tokens, env} — they capture the environment at creation.

  # FILTER: { block } list FILTER — keeps elements where block returns true
  def execute(:filter, [{:block, block_tokens, env}, list | rest]) when is_list(list) do
    filtered =
      Enum.filter(list, fn elem ->
        result = Axiom.Evaluator.eval_tokens(block_tokens, [elem], env)
        hd(result) == true
      end)

    [filtered | rest]
  end

  # MAP: { block } list MAP — applies block to each element
  def execute(:map, [{:block, block_tokens, env}, list | rest]) when is_list(list) do
    mapped =
      Enum.map(list, fn elem ->
        result = Axiom.Evaluator.eval_tokens(block_tokens, [elem], env)
        hd(result)
      end)

    [mapped | rest]
  end

  # Also support: list { block } FILTER (block on top)
  def execute(:filter, [list, {:block, _, _} = block | rest]) when is_list(list) do
    execute(:filter, [block, list | rest])
  end

  def execute(:map, [list, {:block, _, _} = block | rest]) when is_list(list) do
    execute(:map, [block, list | rest])
  end

  # Error cases
  def execute(op, stack) do
    raise Axiom.RuntimeError,
          "cannot apply #{op} to stack: #{inspect(Enum.take(stack, 3))}... (#{length(stack)} elements)"
  end
end

defmodule Axiom.RuntimeError do
  defexception [:message]
end

defmodule Axiom.ContractError do
  defexception [:message, :function_name, :stack]
end
