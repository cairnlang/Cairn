defmodule Axiom.Solver.Symbolic do
  @moduledoc """
  Symbolic executor: walks token lists and builds formula ASTs.

  Mirrors `Axiom.Evaluator.run/3` but operates on symbolic values instead of
  concrete ones. Each supported operation produces symbolic expressions;
  unsupported operations bail with a reason.
  """

  alias Axiom.Solver.Formula

  @type result ::
          {:ok, [Formula.sym_val()]}
          | {:unsupported, String.t()}

  @doc """
  Symbolically execute a list of tokens starting from the given symbolic stack.

  Returns `{:ok, stack}` on success or `{:unsupported, reason}` if the token
  list contains operations we can't handle symbolically.
  """
  @spec execute([Axiom.Types.token()], [Formula.sym_val()]) :: result()
  def execute(tokens, stack) do
    walk(tokens, stack)
  end

  @doc """
  Build an initial symbolic stack for the given param types.

  For `[:int, :int]`, returns `[{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]`
  where p0 is the top of stack (first param).

  Returns `{:ok, stack, vars}` or `{:unsupported, reason}` if non-int params exist.
  """
  @spec build_initial_stack([atom()]) ::
          {:ok, [Formula.sym_val()], [String.t()]} | {:unsupported, String.t()}
  def build_initial_stack(param_types) do
    indexed = param_types |> Enum.with_index()

    if Enum.all?(indexed, fn {t, _} -> t == :int end) do
      vars = Enum.map(indexed, fn {_, i} -> "p#{i}" end)

      stack =
        indexed
        |> Enum.map(fn {_, i} -> {:int_expr, {:var, "p#{i}"}} end)

      {:ok, stack, vars}
    else
      {:unsupported, "non-int parameter types are not supported by PROVE"}
    end
  end

  @doc """
  Extract the top-of-stack boolean constraint after executing PRE or POST tokens.
  """
  @spec extract_bool_constraint([Formula.sym_val()]) ::
          {:ok, Formula.constraint()} | {:error, String.t()}
  def extract_bool_constraint([{:bool_expr, c} | _]), do: {:ok, c}
  def extract_bool_constraint([_ | _]), do: {:error, "top of stack is not a boolean constraint"}
  def extract_bool_constraint([]), do: {:error, "stack is empty after condition execution"}

  # --- Token walker ---

  defp walk([], stack), do: {:ok, stack}

  # Integer literal
  defp walk([{:int_lit, n, _} | rest], stack) do
    walk(rest, [{:int_expr, {:const, n}} | stack])
  end

  # Boolean literal
  defp walk([{:bool_lit, true, _} | rest], stack) do
    walk(rest, [{:bool_expr, true} | stack])
  end

  defp walk([{:bool_lit, false, _} | rest], stack) do
    walk(rest, [{:bool_expr, false} | stack])
  end

  # Arithmetic: ADD, SUB, MUL, DIV, MOD
  defp walk([{:op, :add, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:int_expr, {:add, b, a}} | stack])
  end

  defp walk([{:op, :sub, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:int_expr, {:sub, b, a}} | stack])
  end

  defp walk([{:op, :mul, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:int_expr, {:mul, b, a}} | stack])
  end

  defp walk([{:op, :div, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:int_expr, {:div, b, a}} | stack])
  end

  defp walk([{:op, :mod, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:int_expr, {:mod, b, a}} | stack])
  end

  # Unary: NEG
  defp walk([{:op, :neg, _} | rest], [{:int_expr, a} | stack]) do
    walk(rest, [{:int_expr, {:neg, a}} | stack])
  end

  # SQ: a -> a*a
  defp walk([{:op, :sq, _} | rest], [{:int_expr, a} | stack]) do
    walk(rest, [{:int_expr, {:mul, a, a}} | stack])
  end

  # Comparisons: GTE, GT, LTE, LT, EQ, NEQ
  defp walk([{:op, :gte, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:bool_expr, {:gte, b, a}} | stack])
  end

  defp walk([{:op, :gt, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:bool_expr, {:gt, b, a}} | stack])
  end

  defp walk([{:op, :lte, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:bool_expr, {:lte, b, a}} | stack])
  end

  defp walk([{:op, :lt, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:bool_expr, {:lt, b, a}} | stack])
  end

  defp walk([{:op, :eq, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:bool_expr, {:eq, b, a}} | stack])
  end

  defp walk([{:op, :neq, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack]) do
    walk(rest, [{:bool_expr, {:neq, b, a}} | stack])
  end

  # Boolean EQ/NEQ (compare two booleans)
  defp walk([{:op, :eq, _} | rest], [{:bool_expr, a}, {:bool_expr, b} | stack]) do
    # a EQ b is equivalent to (a AND b) OR (NOT a AND NOT b)
    equiv = {:or, {:and, b, a}, {:and, {:not, b}, {:not, a}}}
    walk(rest, [{:bool_expr, equiv} | stack])
  end

  defp walk([{:op, :neq, _} | rest], [{:bool_expr, a}, {:bool_expr, b} | stack]) do
    # a NEQ b is NOT (a EQ b)
    equiv = {:not, {:or, {:and, b, a}, {:and, {:not, b}, {:not, a}}}}
    walk(rest, [{:bool_expr, equiv} | stack])
  end

  # Logic: AND, OR, NOT
  defp walk([{:op, :and, _} | rest], [{:bool_expr, a}, {:bool_expr, b} | stack]) do
    walk(rest, [{:bool_expr, {:and, b, a}} | stack])
  end

  defp walk([{:op, :or, _} | rest], [{:bool_expr, a}, {:bool_expr, b} | stack]) do
    walk(rest, [{:bool_expr, {:or, b, a}} | stack])
  end

  defp walk([{:op, :not, _} | rest], [{:bool_expr, a} | stack]) do
    walk(rest, [{:bool_expr, {:not, a}} | stack])
  end

  # Stack manipulation: DUP, DROP, SWAP, OVER, ROT
  defp walk([{:op, :dup, _} | rest], [top | _] = stack) do
    walk(rest, [top | stack])
  end

  defp walk([{:op, :drop, _} | rest], [_ | stack]) do
    walk(rest, stack)
  end

  defp walk([{:op, :swap, _} | rest], [a, b | stack]) do
    walk(rest, [b, a | stack])
  end

  defp walk([{:op, :over, _} | rest], [_a, b | _] = stack) do
    walk(rest, [b | stack])
  end

  defp walk([{:op, :rot, _} | rest], [a, b, c | stack]) do
    walk(rest, [c, a, b | stack])
  end

  # Unsupported ops — bail with reason
  defp walk([{:op, :abs, _} | _], _stack) do
    {:unsupported, "ABS requires if-then-else (not yet supported by PROVE)"}
  end

  defp walk([{:op, :min, _} | _], _stack) do
    {:unsupported, "MIN requires if-then-else (not yet supported by PROVE)"}
  end

  defp walk([{:op, :max, _} | _], _stack) do
    {:unsupported, "MAX requires if-then-else (not yet supported by PROVE)"}
  end

  defp walk([{:op, op, _} | _], _stack)
       when op in [
              :filter,
              :map,
              :reduce,
              :times,
              :while,
              :apply,
              :sum,
              :len,
              :head,
              :tail,
              :cons,
              :concat,
              :sort,
              :reverse,
              :range,
              :print,
              :say,
              :argv,
              :read_file,
              :write_file,
              :read_line,
              :words,
              :lines,
              :contains,
              :get,
              :put,
              :del,
              :keys,
              :values,
              :has,
              :mlen,
              :merge
            ] do
    {:unsupported, "#{String.upcase(to_string(op))} is not supported by PROVE — use VERIFY instead"}
  end

  # Float literals are unsupported
  defp walk([{:float_lit, _, _} | _], _stack) do
    {:unsupported, "float literals are not supported by PROVE"}
  end

  # String literals are unsupported
  defp walk([{:str_lit, _, _} | _], _stack) do
    {:unsupported, "string literals are not supported by PROVE"}
  end

  # List/map literals are unsupported
  defp walk([{:list_open, _, _} | _], _stack) do
    {:unsupported, "list operations are not supported by PROVE — use VERIFY instead"}
  end

  defp walk([{:list_lit, _, _} | _], _stack) do
    {:unsupported, "list operations are not supported by PROVE — use VERIFY instead"}
  end

  defp walk([{:map_open, _, _} | _], _stack) do
    {:unsupported, "map operations are not supported by PROVE — use VERIFY instead"}
  end

  defp walk([{:map_lit, _, _} | _], _stack) do
    {:unsupported, "map operations are not supported by PROVE — use VERIFY instead"}
  end

  # IF/ELSE is unsupported (future extension)
  defp walk([{:if_kw, _, _} | _], _stack) do
    {:unsupported, "IF/ELSE is not yet supported by PROVE — use VERIFY instead"}
  end

  # Block literals are unsupported
  defp walk([{:block_open, _, _} | _], _stack) do
    {:unsupported, "block literals are not supported by PROVE — use VERIFY instead"}
  end

  # Function calls are unsupported
  defp walk([{:ident, name, _} | _], _stack) do
    {:unsupported, "function call '#{name}' is not supported by PROVE — use VERIFY instead"}
  end

  # Catch-all: unsupported token
  defp walk([token | _], _stack) do
    {:unsupported, "unsupported token #{inspect(token)} in PROVE"}
  end
end
