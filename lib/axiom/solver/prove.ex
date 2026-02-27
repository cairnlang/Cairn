defmodule Axiom.Solver.Prove do
  @moduledoc """
  Orchestrates the PROVE pipeline: symbolic execution → proof obligation assembly →
  SMT-LIB generation → Z3 query → result formatting.
  """

  alias Axiom.Solver.{Symbolic, SmtLib, Z3}
  alias Axiom.Types.Function

  @type prove_result ::
          {:proven, String.t()}
          | {:disproven, String.t(), %{String.t() => integer()}}
          | {:unknown, String.t()}
          | {:error, String.t()}

  @doc """
  Prove that a function's POST condition holds for all inputs satisfying PRE.

  Steps:
  1. Build initial symbolic stack from param types
  2. Symbolically execute PRE → extract PRE constraint
  3. Symbolically execute body on initial stack
  4. Symbolically execute POST on result stack → extract POST constraint
  5. Assemble proof obligation: PRE ∧ ¬POST
  6. Generate SMT-LIB script and query Z3
  7. Return result
  """
  @spec prove(Function.t(), map()) :: prove_result()
  def prove(%Function{} = func, env \\ %{}) do
    trace_enabled = trace_enabled?(env)
    clear_trace_events()

    with :ok <- check_z3_available(),
         prove_env <- with_trace_flag(env, trace_enabled),
         {:ok, initial_stack, vars, base_constraint} <- Symbolic.build_initial_stack(func.param_types, prove_env),
         {:ok, pre_constraint, body_stack} <- execute_pre(func, initial_stack, prove_env),
         prove_env <- enrich_env_with_pre_assumptions(prove_env, pre_constraint),
         {:ok, result_stack} <- execute_body(func, body_stack, prove_env),
         {:ok, post_constraint} <- execute_post(func, result_stack, prove_env) do
      result = query_z3(vars, combine_constraints(base_constraint, pre_constraint), post_constraint, func, env)
      maybe_emit_trace(func.name, result, trace_enabled)
      result
    else
      {:unsupported, reason} ->
        result = {:unknown, reason}
        maybe_emit_trace(func.name, result, trace_enabled)
        result

      {:error, reason} ->
        result = {:error, reason}
        maybe_emit_trace(func.name, result, trace_enabled)
        result
    end
  end

  defp check_z3_available do
    if Z3.available?(), do: :ok, else: {:error, z3_missing_message()}
  end

  defp z3_missing_message do
    "z3 not found on PATH. Install Z3 (https://github.com/Z3Prover/z3) to use PROVE."
  end

  # Execute PRE condition symbolically. If no PRE, use `true`.
  defp execute_pre(%Function{pre_condition: nil}, initial_stack, _env) do
    {:ok, true, initial_stack}
  end

  defp execute_pre(%Function{pre_condition: pre_tokens}, initial_stack, env) do
    case Symbolic.execute(pre_tokens, initial_stack, env) do
      {:ok, pre_stack} ->
        case Symbolic.extract_bool_constraint(pre_stack) do
          {:ok, constraint} -> {:ok, constraint, initial_stack}
          {:error, msg} -> {:error, "PRE: #{msg}"}
        end

      {:unsupported, reason} ->
        {:unsupported, reason}
    end
  end

  # Execute body symbolically
  defp execute_body(%Function{body: body}, stack, env) do
    case Symbolic.execute(body, stack, env) do
      {:ok, _} = result -> result
      {:unsupported, _} = result -> result
    end
  end

  # Execute POST condition symbolically. If no POST, use `true` (vacuously true).
  defp execute_post(%Function{post_condition: nil}, _result_stack, _env) do
    {:ok, true}
  end

  defp execute_post(%Function{post_condition: post_tokens}, result_stack, env) do
    case Symbolic.execute(post_tokens, result_stack, env) do
      {:ok, post_stack} ->
        case Symbolic.extract_bool_constraint(post_stack) do
          {:ok, constraint} -> {:ok, constraint}
          {:error, msg} -> {:error, "POST: #{msg}"}
        end

      {:unsupported, reason} ->
        {:unsupported, reason}
    end
  end

  # Generate SMT-LIB, query Z3, interpret result
  defp query_z3(vars, pre_constraint, post_constraint, func, env) do
    script = SmtLib.build_script(vars, pre_constraint, post_constraint)

    case Z3.query(script) do
      :unsat ->
        {:proven, "POST holds for all inputs satisfying PRE"}

      {:sat, model} ->
        {:disproven, format_counterexample(model, func, env), model}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Format a counterexample model into a human-readable string.

  Maps variable names (p0, p1, ...) back to parameter positions.
  """
  @spec format_counterexample(%{String.t() => integer()}, Function.t(), map()) :: String.t()
  def format_counterexample(model, %Function{param_types: param_types}, env \\ %{}) do
    param_types
    |> Enum.with_index()
    |> Enum.map(fn {type, i} ->
      "p#{i} = #{format_param_value(type, i, model, env)}"
    end)
    |> Enum.join(", ")
  end

  defp format_param_value(:int, i, model, _env) do
    Map.get(model, "p#{i}", "?")
  end

  defp format_param_value({:user_type, "option"}, i, model, _env) do
    case Map.get(model, "p#{i}_tag", 0) do
      1 -> "Some(#{Map.get(model, "p#{i}_val", "?")})"
      _ -> "None"
    end
  end

  defp format_param_value({:user_type, "result"}, i, model, _env) do
    case Map.get(model, "p#{i}_tag", 0) do
      1 -> "Ok(#{Map.get(model, "p#{i}_ok", "?")})"
      _ -> "Err(_)"
    end
  end

  defp format_param_value({:user_type, type_name}, i, model, env) do
    types = Map.get(env, "__types__", %{})

    case Map.get(types, type_name) do
      %Axiom.Types.TypeDef{} = typedef ->
        ctors = typedef.variants |> Map.keys() |> Enum.sort()
        tag = Map.get(model, "p#{i}_tag", 0)

        case Enum.at(ctors, tag) do
          nil ->
            "#{type_name}(tag=#{tag})"

          ctor ->
            fields = Map.get(typedef.variants, ctor, [])

            values =
              fields
              |> Enum.with_index()
              |> Enum.map(fn {_field_type, field_i} ->
                Map.get(model, "p#{i}_#{ctor}_#{field_i}", "?")
              end)
              |> Enum.join(", ")

            if values == "", do: ctor, else: "#{ctor}(#{values})"
        end

      _ ->
        "#{type_name}(?)"
    end
  end

  defp format_param_value(_type, _i, _model, _env), do: "?"

  defp enrich_env_with_pre_assumptions(env, pre_constraint) do
    assumptions = assumption_map_from_constraint(pre_constraint)

    if map_size(assumptions) == 0 do
      env
    else
      Map.put(env, "__prove_tag_assumptions__", assumptions)
    end
  end

  defp assumption_map_from_constraint({:and, a, b}) do
    merge_assumption_maps(assumption_map_from_constraint(a), assumption_map_from_constraint(b), :and)
  end

  defp assumption_map_from_constraint({:or, a, b}) do
    merge_assumption_maps(assumption_map_from_constraint(a), assumption_map_from_constraint(b), :or)
  end

  defp assumption_map_from_constraint({:eq, {:var, var}, {:const, value}}) when is_integer(value) do
    %{var => %{eq: value, neq: MapSet.new()}}
  end

  defp assumption_map_from_constraint({:eq, {:const, value}, {:var, var}}) when is_integer(value) do
    %{var => %{eq: value, neq: MapSet.new()}}
  end

  defp assumption_map_from_constraint({:neq, {:var, var}, {:const, value}}) when is_integer(value) do
    %{var => %{eq: nil, neq: MapSet.new([value])}}
  end

  defp assumption_map_from_constraint({:neq, {:const, value}, {:var, var}}) when is_integer(value) do
    %{var => %{eq: nil, neq: MapSet.new([value])}}
  end

  defp assumption_map_from_constraint({:not, {:eq, {:var, var}, {:const, value}}}) when is_integer(value) do
    %{var => %{eq: nil, neq: MapSet.new([value])}}
  end

  defp assumption_map_from_constraint({:not, {:eq, {:const, value}, {:var, var}}}) when is_integer(value) do
    %{var => %{eq: nil, neq: MapSet.new([value])}}
  end

  defp assumption_map_from_constraint({:not, {:neq, {:var, var}, {:const, value}}}) when is_integer(value) do
    %{var => %{eq: value, neq: MapSet.new()}}
  end

  defp assumption_map_from_constraint({:not, {:neq, {:const, value}, {:var, var}}}) when is_integer(value) do
    %{var => %{eq: value, neq: MapSet.new()}}
  end

  defp assumption_map_from_constraint({:not, {:not, inner}}) do
    assumption_map_from_constraint(inner)
  end

  defp assumption_map_from_constraint({:not, {:ite_bool, cond, true, false}}) do
    assumption_map_from_constraint({:not, cond})
  end

  defp assumption_map_from_constraint({:not, {:ite_bool, cond, false, true}}) do
    assumption_map_from_constraint(cond)
  end

  defp assumption_map_from_constraint({:ite_bool, cond, true, false}) do
    assumption_map_from_constraint(cond)
  end

  defp assumption_map_from_constraint({:ite_bool, cond, false, true}) do
    assumption_map_from_constraint({:not, cond})
  end

  defp assumption_map_from_constraint(_constraint), do: %{}

  defp merge_assumption_maps(left, right, mode) do
    keys = Map.keys(left) ++ Map.keys(right)

    keys
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn key, acc ->
      la = Map.get(left, key, %{eq: nil, neq: MapSet.new()})
      ra = Map.get(right, key, %{eq: nil, neq: MapSet.new()})
      merged = merge_tag_assumption(la, ra, mode)

      if merged.eq == nil and MapSet.size(merged.neq) == 0 do
        acc
      else
        Map.put(acc, key, merged)
      end
    end)
  end

  defp merge_tag_assumption(left, right, :and) do
    eq =
      case {left.eq, right.eq} do
        {nil, nil} -> nil
        {v, nil} -> v
        {nil, v} -> v
        {v, v} -> v
        {_v1, _v2} -> :conflict
      end

    neq = MapSet.union(left.neq, right.neq)

    cond do
      eq == :conflict ->
        %{eq: nil, neq: MapSet.new()}

      is_integer(eq) and MapSet.member?(neq, eq) ->
        %{eq: nil, neq: MapSet.new()}

      true ->
        %{eq: eq, neq: neq}
    end
  end

  defp merge_tag_assumption(left, right, :or) do
    eq =
      case {left.eq, right.eq} do
        {v, v} when is_integer(v) -> v
        _ -> nil
      end

    neq = MapSet.intersection(left.neq, right.neq)

    if is_integer(eq) and MapSet.member?(neq, eq) do
      %{eq: nil, neq: neq}
    else
      %{eq: eq, neq: neq}
    end
  end

  defp trace_enabled?(env) do
    Map.get(env, "__prove_trace__", false) or System.get_env("AXIOM_PROVE_TRACE") == "1"
  end

  defp with_trace_flag(env, true), do: Map.put(env, "__prove_trace_enabled__", true)
  defp with_trace_flag(env, false), do: env

  defp maybe_emit_trace(_func_name, _result, false), do: :ok

  defp maybe_emit_trace(func_name, result, true) do
    status =
      case result do
        {:proven, _} -> "PROVEN"
        {:disproven, _, _} -> "DISPROVEN"
        {:unknown, _} -> "UNKNOWN"
        {:error, _} -> "ERROR"
      end

    events = get_trace_events()

    if events == [] do
      IO.puts("PROVE TRACE #{func_name} (#{status}): no MATCH branch events")
    else
      IO.puts("PROVE TRACE #{func_name} (#{status}):")
      Enum.each(events, &IO.puts("  - " <> &1))
    end

    :ok
  end

  defp clear_trace_events do
    Process.put(:axiom_prove_trace_events, [])
  end

  defp get_trace_events do
    (Process.get(:axiom_prove_trace_events) || [])
    |> Enum.reverse()
  end

  defp combine_constraints(true, c), do: c
  defp combine_constraints(c, true), do: c
  defp combine_constraints(a, b), do: {:and, a, b}
end
