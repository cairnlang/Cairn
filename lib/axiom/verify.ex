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
    types = Map.get(env, "__types__", %{})
    generator = build_generator(func.param_types, types)

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

  defp build_generator(param_types, types) do
    Enum.map(param_types, &type_generator(&1, types))
  end

  defp type_generator(:int, _types) do
    StreamData.integer(-1000..1000)
  end

  defp type_generator(:float, _types) do
    # StreamData doesn't have a direct float generator with range,
    # so we map integers to floats with some decimal variation
    StreamData.bind(StreamData.integer(-1000..1000), fn n ->
      StreamData.bind(StreamData.integer(0..99), fn frac ->
        StreamData.constant(n + frac / 100)
      end)
    end)
  end

  defp type_generator(:bool, _types) do
    StreamData.boolean()
  end

  defp type_generator(:str, _types) do
    StreamData.string(:alphanumeric, min_length: 0, max_length: 20)
  end

  defp type_generator({:list, elem_type}, types) do
    StreamData.list_of(type_generator(elem_type, types), min_length: 0, max_length: 10)
  end

  defp type_generator({:map, key_type, value_type}, types) do
    StreamData.map_of(
      type_generator(key_type, types),
      type_generator(value_type, types),
      min_length: 0,
      max_length: 5
    )
  end

  defp type_generator(:any, _types) do
    StreamData.one_of([
      StreamData.integer(-100..100),
      StreamData.boolean(),
      StreamData.string(:alphanumeric, min_length: 0, max_length: 10)
    ])
  end

  # User-defined sum types: depth-limited via StreamData.tree.
  # StreamData.tree(leaf_gen, subtree_fn) automatically shrinks depth toward
  # the leaf generator as size decreases, preventing infinite recursion.
  defp type_generator({:user_type, name}, types) do
    typedef = Map.get(types, name)

    unless typedef do
      StreamData.integer(-100..100)
    else
      # Leaf variants have no fields that (transitively) reference a user_type.
      # They form the base case for StreamData.tree.
      leaf_variants =
        Enum.filter(typedef.variants, fn {_ctor, fields} ->
          Enum.all?(fields, &(not field_has_user_type?(&1)))
        end)

      # Fall back to all variants if somehow all are recursive (shouldn't happen
      # for well-formed types, but avoids an empty one_of).
      base_variants = if Enum.empty?(leaf_variants), do: typedef.variants, else: leaf_variants
      leaf_gen = variant_picker(name, base_variants, nil, types)

      has_recursive = Enum.any?(typedef.variants, fn {_ctor, fields} ->
        Enum.any?(fields, &field_has_user_type?/1)
      end)

      if has_recursive do
        StreamData.tree(leaf_gen, fn inner ->
          variant_picker(name, typedef.variants, inner, types)
        end)
      else
        leaf_gen
      end
    end
  end

  defp type_generator(_, _types) do
    # Fallback for unknown types
    StreamData.integer(-100..100)
  end

  # Build a generator that picks one variant from `variants` at random.
  # `inner_gen` is the sub-generator to use for recursive {:user_type, _} fields;
  # nil means use the regular type_generator (leaf / non-recursive context).
  defp variant_picker(type_name, variants, inner_gen, types) do
    StreamData.one_of(
      Enum.map(variants, fn {ctor, fields} ->
        if Enum.empty?(fields) do
          StreamData.constant({:variant, type_name, ctor, []})
        else
          field_gens = Enum.map(fields, &gen_for_field(&1, inner_gen, types))
          # Build a generator of a list from a list of generators.
          fields_gen =
            Enum.reduce(field_gens, StreamData.constant([]), fn gen, acc ->
              StreamData.bind(acc, fn list ->
                StreamData.map(gen, fn val -> list ++ [val] end)
              end)
            end)
          StreamData.map(fields_gen, fn fs -> {:variant, type_name, ctor, fs} end)
        end
      end)
    )
  end

  # For a field whose type directly or shallowly references a user_type, use
  # `inner_gen` (the depth-reduced sub-generator) instead of recursing fully.
  defp gen_for_field({:user_type, _}, inner, _types) when not is_nil(inner), do: inner
  defp gen_for_field({:list, {:user_type, _}}, inner, _types) when not is_nil(inner),
    do: StreamData.list_of(inner, min_length: 0, max_length: 3)
  defp gen_for_field({:map, k_type, {:user_type, _}}, inner, types) when not is_nil(inner),
    do: StreamData.map_of(type_generator(k_type, types), inner, min_length: 0, max_length: 3)
  defp gen_for_field(field_type, _inner, types),
    do: type_generator(field_type, types)

  # Returns true if `type` references a user_type anywhere in its structure.
  defp field_has_user_type?({:user_type, _}), do: true
  defp field_has_user_type?({:list, inner}), do: field_has_user_type?(inner)
  defp field_has_user_type?({:map, k, v}), do: field_has_user_type?(k) or field_has_user_type?(v)
  defp field_has_user_type?(_), do: false

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
  defp format_type({:map, k, v}), do: "map[#{format_type(k)} #{format_type(v)}]"
  defp format_type({:user_type, name}), do: name
  defp format_type(other), do: inspect(other)
end
