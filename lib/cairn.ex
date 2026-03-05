defmodule Cairn do
  @moduledoc """
  Cairn — an AI-native programming language targeting the BEAM.

  Public API for compiling and evaluating Cairn source code.
  """

  alias Cairn.{Lexer, Parser, Evaluator, Checker, Verify, Loader}
  alias Cairn.Types.{ProtocolDef, TypeAlias, TypeDef}
  alias Cairn.Solver.Prove

  @doc """
  Evaluates a Cairn expression string and returns the resulting stack.

  ## Examples

      iex> Cairn.eval("3 4 ADD")
      [7]

      iex> Cairn.eval("[ 1 2 3 4 5 ] { 2 MOD 1 EQ } FILTER")
      [[1, 3, 5]]
  """
  @spec eval(String.t()) :: list()
  def eval(source) do
    {stack, _env} = eval_with_env(source)
    stack
  end

  @doc """
  Evaluates Cairn source and returns both the stack and the environment.
  The environment contains any function definitions.
  """
  @spec eval_with_env(String.t(), map(), list()) :: {list(), map()}
  def eval_with_env(source, env \\ %{}, stack \\ []) do
    env = with_prelude(env)
    known_types = known_type_names_from_env(env)

    with {:ok, tokens} <- Lexer.tokenize(source),
         {:ok, items} <- Parser.parse(tokens, known_types) do
      if Enum.any?(items, &match?({:import, _}, &1)) do
        raise Cairn.RuntimeError, "IMPORT requires file mode; use Cairn.eval_file/3 or mix cairn.run"
      end

      eval_items(items, env, stack)
    else
      {:error, errors} when is_list(errors) ->
        raise Cairn.StaticError, errors

      {:error, msg} ->
        raise Cairn.RuntimeError, msg
    end
  end

  @doc """
  Evaluates a Cairn source file and resolves recursive IMPORT statements.
  Returns both stack and environment.
  """
  @spec eval_file(String.t(), map(), list()) :: {list(), map()}
  def eval_file(path, env \\ %{}, stack \\ []) do
    env = with_prelude(env)
    path = Path.expand(path)

    with {:ok, prelude_items} <- load_prelude_items(path),
         {:ok, items} <- Loader.load_items(path, known_type_names_from_items(prelude_items)) do
      eval_items(prelude_items ++ items, env, stack)
    else
      {:error, msg} ->
        raise Cairn.RuntimeError, msg
    end
  end

  defp load_prelude_items(target_path) do
    disable? = System.get_env("CAIRN_NO_PRELUDE") in ["1", "true", "TRUE"]
    prelude_path = Path.expand("lib/prelude.crn", File.cwd!())

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
        raise Cairn.RuntimeError, "VERIFY: undefined function '#{name}'"

      %Cairn.Types.Function{} = func ->
        case Verify.run(func, count, env) do
          {:ok, %{passed: passed, skipped: skipped}} ->
            skip_msg = if skipped > 0, do: " (#{skipped} skipped by PRE)", else: ""
            IO.puts("VERIFY #{name}: OK — #{passed} tests passed#{skip_msg}")

          {:error, %{counterexample: nil, error: msg}} ->
            raise Cairn.RuntimeError, "VERIFY #{name}: FAILED — #{msg}"

          {:error, %{counterexample: ce, error: msg, passed: passed}} ->
            raise Cairn.ContractError,
              message: "VERIFY #{name}: FAILED after #{passed} tests\n  counterexample: #{ce}\n  error: #{msg}",
              function_name: name,
              stack: []
        end
    end
  end

  defp run_prove(name, env) do
    case Map.get(env, name) do
      nil ->
        raise Cairn.RuntimeError, "PROVE: undefined function '#{name}'"

      %Cairn.Types.Function{} = func ->
        if Map.get(func, :effect, :io) != :pure do
          IO.puts("PROVE #{name}: UNKNOWN")
          IO.puts("  reason: function is not pure")
        else
          case Prove.prove(func, env) do
            {:proven, _msg} ->
              IO.puts("PROVE #{name}: PROVEN — POST holds for all inputs satisfying PRE")

            {:disproven, counterexample, _model} ->
              raise Cairn.ContractError,
                message: "PROVE #{name}: DISPROVEN\n  counterexample: #{counterexample}",
                function_name: name,
                stack: []

            {:unknown, reason} ->
              IO.puts("PROVE #{name}: UNKNOWN")
              IO.puts("  reason: #{reason}")
              maybe_print_prove_hint(reason)

            {:error, reason} ->
              hint = prove_error_hint(reason)

              message =
                if hint do
                  "PROVE #{name}: ERROR\n  reason: #{reason}\n  hint: #{hint}"
                else
                  "PROVE #{name}: ERROR\n  reason: #{reason}"
                end

              raise Cairn.RuntimeError, message
          end
        end
    end
  end

  defp maybe_print_prove_hint(reason) do
    if hint = prove_unknown_hint(reason) do
      IO.puts("  hint: #{hint}")
    end
  end

  defp skip_assurance? do
    System.get_env("CAIRN_SKIP_ASSURANCE") in ["1", "true", "TRUE"]
  end

  defp test_mode?(env), do: Map.get(env, "__test_mode__", false) == true

  defp append_test_result(env, result) do
    results = Map.get(env, "__test_results__", [])
    Map.put(env, "__test_results__", results ++ [result])
  end

  defp run_test_block(name, body, env) do
    try do
      {_stack, _env} = Evaluator.eval_tokens_with_env(body, [], env)
      append_test_result(env, %{name: name, status: :ok})
    rescue
      e in [Cairn.RuntimeError, Cairn.ContractError, Cairn.StaticError] ->
        append_test_result(env, %{name: name, status: :error, message: Exception.message(e)})

      e ->
        append_test_result(env, %{name: name, status: :error, message: Exception.message(e)})
    end
  end

  defp prove_unknown_hint(reason) do
    cond do
      String.contains?(reason, "not supported") ->
        "Try VERIFY for this function, or simplify PRE/body to PROVE-supported operators."

      String.contains?(reason, "inline depth") or String.contains?(reason, "recursive") ->
        "Refactor into non-recursive helper steps or smaller contracts, then PROVE each step."

      true ->
        "Run with CAIRN_PROVE_TRACE=summary|verbose|json to inspect proof shape and pruning decisions."
    end
  end

  defp prove_error_hint(reason) do
    cond do
      String.contains?(reason, "z3 not found") ->
        "Install Z3 and ensure `z3` is available on PATH."

      String.contains?(reason, "failed to open file") ->
        "Retry the run; if this persists, check write permissions for temporary files."

      true ->
        nil
    end
  end

  defp eval_items(items, env, stack) do
    with :ok <- Checker.check(items, env) do
      Enum.reduce(items, {stack, env}, fn
        {:expr, expr_tokens}, {stack, env} ->
          Evaluator.eval_tokens_with_env(expr_tokens, stack, env)

        %Cairn.Types.Function{} = func, {stack, env} ->
          {stack, Map.put(env, func.name, func)}

        %Cairn.Types.TypeDef{} = typedef, {stack, env} ->
          types = Map.get(env, "__types__", %{})
          ctors = Map.get(env, "__constructors__", %{})

          new_ctors =
            Enum.reduce(typedef.variants, ctors, fn {ctor_name, field_types}, acc ->
              Map.put(acc, ctor_name, %{
                type_name: typedef.name,
                type_params: typedef.type_params || [],
                field_types: field_types
              })
            end)

          env =
            env
            |> Map.put("__types__", Map.put(types, typedef.name, typedef))
            |> Map.put("__constructors__", new_ctors)

          {stack, env}

        %TypeAlias{} = type_alias, {stack, env} ->
          type_aliases = Map.get(env, "__type_aliases__", %{})
          {stack, Map.put(env, "__type_aliases__", Map.put(type_aliases, type_alias.name, type_alias))}

        %ProtocolDef{} = protocol, {stack, env} ->
          protocols = Map.get(env, "__protocols__", %{})
          {stack, Map.put(env, "__protocols__", Map.put(protocols, protocol.name, protocol))}

        {:verify, name, count}, {stack, env} ->
          unless skip_assurance?() do
            run_verify(name, count, env)
          end

          {stack, env}

        {:prove, name}, {stack, env} ->
          unless skip_assurance?() do
            run_prove(name, env)
          end

          {stack, env}

        {:test, name, body}, {stack, env} ->
          env =
            if test_mode?(env) do
              run_test_block(name, body, env)
            else
              env
            end

          {stack, env}

        {:import, _path}, {stack, env} ->
          {stack, env}
      end)
    else
      {:error, errors} when is_list(errors) ->
        raise Cairn.StaticError, errors
    end
  end

  defp with_prelude(env) do
    types = Map.get(env, "__types__", %{})
    ctors = Map.get(env, "__constructors__", %{})
    type_aliases = Map.get(env, "__type_aliases__", %{})

    types =
      Map.put_new(types, "result", %TypeDef{
        name: "result",
        type_params: ["T", "E"],
        variants: %{"Ok" => [{:type_var, "T"}], "Err" => [{:type_var, "E"}]}
      })

    ctors =
      ctors
      |> Map.put_new("Ok", %{type_name: "result", type_params: ["T", "E"], field_types: [{:type_var, "T"}]})
      |> Map.put_new("Err", %{type_name: "result", type_params: ["T", "E"], field_types: [{:type_var, "E"}]})

    env
    |> Map.put("__types__", types)
    |> Map.put("__constructors__", ctors)
    |> Map.put("__type_aliases__", type_aliases)
  end

  defp known_type_names_from_env(env) do
    type_names = env |> Map.get("__types__", %{}) |> Map.keys()
    alias_names = env |> Map.get("__type_aliases__", %{}) |> Map.keys()
    MapSet.new(type_names ++ alias_names)
  end

  defp known_type_names_from_items(items) do
    Enum.reduce(items, MapSet.new(), fn
      %TypeDef{name: name}, acc -> MapSet.put(acc, name)
      %TypeAlias{name: name}, acc -> MapSet.put(acc, name)
      _, acc -> acc
    end)
  end

  @doc """
  Evaluates multiple lines of Cairn source, maintaining state between them.
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
