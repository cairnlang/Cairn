defmodule Axiom do
  @moduledoc """
  Axiom — an AI-native programming language targeting the BEAM.

  Public API for compiling and evaluating Axiom source code.
  """

  alias Axiom.{Lexer, Parser, Evaluator}

  @doc """
  Evaluates an Axiom expression string and returns the resulting stack.

  ## Examples

      iex> Axiom.eval("3 4 ADD")
      [7]

      iex> Axiom.eval("[ 1 2 3 4 5 ] { 2 MOD 1 EQ } FILTER")
      [[1, 3, 5]]
  """
  @spec eval(String.t()) :: list()
  def eval(source) do
    {stack, _env} = eval_with_env(source)
    stack
  end

  @doc """
  Evaluates Axiom source and returns both the stack and the environment.
  The environment contains any function definitions.
  """
  @spec eval_with_env(String.t(), map(), list()) :: {list(), map()}
  def eval_with_env(source, env \\ %{}, stack \\ []) do
    with {:ok, tokens} <- Lexer.tokenize(source),
         {:ok, items} <- Parser.parse(tokens) do
      Enum.reduce(items, {stack, env}, fn
        {:expr, expr_tokens}, {stack, env} ->
          Evaluator.eval_tokens_with_env(expr_tokens, stack, env)

        %Axiom.Types.Function{} = func, {stack, env} ->
          {stack, Map.put(env, func.name, func)}
      end)
    else
      {:error, msg} -> raise Axiom.RuntimeError, msg
    end
  end

  @doc """
  Evaluates multiple lines of Axiom source, maintaining state between them.
  Useful for the REPL.
  """
  @spec eval_lines([String.t()], list(), map()) :: {list(), map()}
  def eval_lines(lines, stack \\ [], env \\ %{}) do
    Enum.reduce(lines, {stack, env}, fn line, {stack, env} ->
      line = String.trim(line)
      if line == "" do
        {stack, env}
      else
        eval_with_env(line, env) |> then(fn {new_stack, new_env} -> {new_stack, new_env} end)
      end
    end)
  end
end
