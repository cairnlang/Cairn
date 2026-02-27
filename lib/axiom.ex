defmodule Axiom do
  @moduledoc """
  Axiom — an AI-native programming language targeting the BEAM.

  Public API for compiling and evaluating Axiom source code.
  """

  alias Axiom.{Lexer, Parser, Evaluator, Checker, Verify, Loader}
  alias Axiom.Types.TypeDef
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
    env = with_prelude(env)

    with {:ok, tokens} <- Lexer.tokenize(source),
         {:ok, items} <- Parser.parse(tokens) do
      if Enum.any?(items, &match?({:import, _}, &1)) do
        raise Axiom.RuntimeError, "IMPORT requires file mode; use Axiom.eval_file/3 or mix axiom.run"
      end

      eval_items(items, env, stack)
    else
      {:error, errors} when is_list(errors) ->
        raise Axiom.StaticError, errors

      {:error, msg} ->
        raise Axiom.RuntimeError, msg
    end
  end

  @doc """
  Evaluates an Axiom source file and resolves recursive IMPORT statements.
  Returns both stack and environment.
  """
  @spec eval_file(String.t(), map(), list()) :: {list(), map()}
  def eval_file(path, env \\ %{}, stack \\ []) do
    env = with_prelude(env)
    path = Path.expand(path)

    with {:ok, prelude_items} <- load_prelude_items(path),
         {:ok, items} <- Loader.load_items(path) do
      eval_items(prelude_items ++ items, env, stack)
    else
      {:error, msg} ->
        raise Axiom.RuntimeError, msg
    end
  end

  defp load_prelude_items(target_path) do
    disable? = System.get_env("AXIOM_NO_PRELUDE") in ["1", "true", "TRUE"]
    prelude_path = Path.expand("lib/prelude.ax", File.cwd!())

    cond do
      disable? ->
        {:ok, []}

      target_path == prelude_path ->
        {:ok, []}

      File.exists?(prelude_path) ->
        Loader.load_items(prelude_path)

      true ->
        {:ok, []}
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
        case Prove.prove(func, env) do
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

  defp eval_items(items, env, stack) do
    with :ok <- Checker.check(items, env) do
      Enum.reduce(items, {stack, env}, fn
        {:expr, expr_tokens}, {stack, env} ->
          Evaluator.eval_tokens_with_env(expr_tokens, stack, env)

        %Axiom.Types.Function{} = func, {stack, env} ->
          {stack, Map.put(env, func.name, func)}

        %Axiom.Types.TypeDef{} = typedef, {stack, env} ->
          types = Map.get(env, "__types__", %{})
          ctors = Map.get(env, "__constructors__", %{})

          new_ctors =
            Enum.reduce(typedef.variants, ctors, fn {ctor_name, field_types}, acc ->
              Map.put(acc, ctor_name, {typedef.name, field_types})
            end)

          env =
            env
            |> Map.put("__types__", Map.put(types, typedef.name, typedef))
            |> Map.put("__constructors__", new_ctors)

          {stack, env}

        {:verify, name, count}, {stack, env} ->
          run_verify(name, count, env)
          {stack, env}

        {:prove, name}, {stack, env} ->
          run_prove(name, env)
          {stack, env}

        {:import, _path}, {stack, env} ->
          {stack, env}
      end)
    else
      {:error, errors} when is_list(errors) ->
        raise Axiom.StaticError, errors
    end
  end

  defp with_prelude(env) do
    types = Map.get(env, "__types__", %{})
    ctors = Map.get(env, "__constructors__", %{})

    types =
      Map.put_new(types, "result", %TypeDef{
        name: "result",
        variants: %{"Ok" => [:any], "Err" => [:str]}
      })

    ctors =
      ctors
      |> Map.put_new("Ok", {"result", [:any]})
      |> Map.put_new("Err", {"result", [:str]})

    env
    |> Map.put("__types__", types)
    |> Map.put("__constructors__", ctors)
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
