defmodule Axiom.Verify do
  @moduledoc """
  Property-based testing for Axiom functions.

  Given a function with typed parameters and PRE/POST contracts,
  generates random inputs satisfying PRE, runs the function, and
  checks that POST holds across many runs.
  """

  alias Axiom.Evaluator

  @doc """
  Runs property-based verification on a function.

  Generates `count` valid inputs (matching param_types and passing PRE),
  executes the function, and verifies no contract violations occur.

  Returns:
    - `{:ok, %{passed: n, skipped: n}}` if all tests pass
    - `{:error, %{counterexample: args, error: exception, passed: n}}` on failure
  """
  def run(%Axiom.Types.Function{} = func, count, env) do
    generator = build_generator(func.param_types)

    # We need more candidates than count because PRE may reject some
    max_attempts = count * 10

    do_verify(func, env, generator, count, max_attempts, 0, 0)
  end

  defp do_verify(_func, _env, _gen, target, _max, passed, skipped) when passed >= target do
    {:ok, %{passed: passed, skipped: skipped}}
  end

  defp do_verify(_func, _env, _gen, _target, max, passed, skipped)
       when passed + skipped >= max do
    if passed > 0 do
      {:ok, %{passed: passed, skipped: skipped}}
    else
      {:error, %{counterexample: nil, error: "could not generate valid inputs (all rejected by PRE)", passed: 0}}
    end
  end

  defp do_verify(func, env, generator, target, max, passed, skipped) do
    # Generate one set of random args
    args = generate_args(generator)

    # Check PRE condition if present
    if passes_pre?(func, args, env) do
      # Run the function and check for contract violations
      case run_function(func, args, env) do
        :ok ->
          do_verify(func, env, generator, target, max, passed + 1, skipped)

        {:error, error_info} ->
          {:error, %{counterexample: format_args(args, func.param_types), error: error_info, passed: passed}}
      end
    else
      do_verify(func, env, generator, target, max, passed, skipped + 1)
    end
  end

  defp passes_pre?(%{pre_condition: nil}, _args, _env), do: true

  defp passes_pre?(%{pre_condition: pre_tokens}, args, env) do
    try do
      result = Evaluator.eval_tokens(pre_tokens, args, env)

      case result do
        [true | _] -> true
        _ -> false
      end
    rescue
      _ -> false
    end
  end

  defp run_function(func, args, env) do
    try do
      Evaluator.eval_function_call(func, args, env)
      :ok
    rescue
      e in Axiom.ContractError ->
        {:error, "CONTRACT: #{e.message}"}

      e in Axiom.RuntimeError ->
        {:error, "RUNTIME: #{e.message}"}
    end
  end

  # --- Argument generation using StreamData ---

  defp build_generator(param_types) do
    Enum.map(param_types, &type_generator/1)
  end

  defp type_generator(:int) do
    StreamData.integer(-1000..1000)
  end

  defp type_generator(:float) do
    # StreamData doesn't have a direct float generator with range,
    # so we map integers to floats with some decimal variation
    StreamData.bind(StreamData.integer(-1000..1000), fn n ->
      StreamData.bind(StreamData.integer(0..99), fn frac ->
        StreamData.constant(n + frac / 100)
      end)
    end)
  end

  defp type_generator(:bool) do
    StreamData.boolean()
  end

  defp type_generator(:str) do
    StreamData.string(:alphanumeric, min_length: 0, max_length: 20)
  end

  defp type_generator({:list, elem_type}) do
    StreamData.list_of(type_generator(elem_type), min_length: 0, max_length: 10)
  end

  defp type_generator(:any) do
    StreamData.one_of([
      StreamData.integer(-100..100),
      StreamData.boolean(),
      StreamData.string(:alphanumeric, min_length: 0, max_length: 10)
    ])
  end

  defp type_generator(_) do
    # Fallback for unknown types
    StreamData.integer(-100..100)
  end

  defp generate_args(generators) do
    # Generate one value from each generator and return as a list
    # (top of stack = first element)
    Enum.map(generators, fn gen ->
      # Pick one value from the stream
      gen
      |> StreamData.resize(30)
      |> Enum.take(1)
      |> hd()
    end)
  end

  defp format_args(args, param_types) do
    args
    |> Enum.zip(param_types)
    |> Enum.map(fn {val, type} -> "#{inspect(val)} (#{format_type(type)})" end)
    |> Enum.join(", ")
  end

  defp format_type(:int), do: "int"
  defp format_type(:float), do: "float"
  defp format_type(:bool), do: "bool"
  defp format_type(:str), do: "str"
  defp format_type(:any), do: "any"
  defp format_type({:list, inner}), do: "[#{format_type(inner)}]"
  defp format_type(other), do: inspect(other)
end
