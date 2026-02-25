defmodule Axiom do
  @moduledoc """
  Axiom — an AI-native programming language targeting the BEAM.

  Public API for compiling and evaluating Axiom source code.
  """

  alias Axiom.{Lexer, Parser, Evaluator, Checker, Verify}
  alias Axiom.Solver.Prove

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
         {:ok, items} <- Parser.parse(tokens),
         :ok <- Checker.check(items, env) do
      Enum.reduce(items, {stack, env}, fn
        {:expr, expr_tokens}, {stack, env} ->
          Evaluator.eval_tokens_with_env(expr_tokens, stack, env)

        %Axiom.Types.Function{} = func, {stack, env} ->
          {stack, Map.put(env, func.name, func)}

        {:verify, name, count}, {stack, env} ->
          run_verify(name, count, env)
          {stack, env}

        {:prove, name}, {stack, env} ->
          run_prove(name, env)
          {stack, env}
      end)
    else
      {:error, errors} when is_list(errors) ->
        raise Axiom.StaticError, errors

      {:error, msg} ->
        raise Axiom.RuntimeError, msg
    end
  end

  defp run_verify(name, count, env) do
    case Map.get(env, name) do
      nil ->
        raise Axiom.RuntimeError, "VERIFY: undefined function '#{name}'"

      %Axiom.Types.Function{} = func ->
        case Verify.run(func, count, env) do
          {:ok, %{passed: passed, skipped: skipped}} ->
            skip_msg = if skipped > 0, do: " (#{skipped} skipped by PRE)", else: ""
            IO.puts("VERIFY #{name}: OK — #{passed} tests passed#{skip_msg}")

          {:error, %{counterexample: nil, error: msg}} ->
            raise Axiom.RuntimeError, "VERIFY #{name}: FAILED — #{msg}"

          {:error, %{counterexample: ce, error: msg, passed: passed}} ->
            raise Axiom.ContractError,
              message: "VERIFY #{name}: FAILED after #{passed} tests\n  counterexample: #{ce}\n  error: #{msg}",
              function_name: name,
              stack: []
        end
    end
  end

  defp run_prove(name, env) do
    case Map.get(env, name) do
      nil ->
        raise Axiom.RuntimeError, "PROVE: undefined function '#{name}'"

      %Axiom.Types.Function{} = func ->
        case Prove.prove(func) do
          {:proven, _msg} ->
            IO.puts("PROVE #{name}: PROVEN — POST holds for all inputs satisfying PRE")

          {:disproven, counterexample, _model} ->
            raise Axiom.ContractError,
              message: "PROVE #{name}: DISPROVEN\n  counterexample: #{counterexample}",
              function_name: name,
              stack: []

          {:unknown, reason} ->
            IO.puts("PROVE #{name}: UNKNOWN — #{reason}")

          {:error, reason} ->
            raise Axiom.RuntimeError, "PROVE #{name}: ERROR — #{reason}"
        end
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
