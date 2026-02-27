defmodule Axiom.Solver.Prove do
  @moduledoc """
  Orchestrates the PROVE pipeline: symbolic execution → proof obligation assembly →
  SMT-LIB generation → Z3 query → result formatting.
  """

  alias Axiom.Solver.{PreNormalize, Symbolic, SmtLib, Z3}
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
    trace_level = trace_level(env)
    clear_trace_events()
    trace_started_at_ms = System.monotonic_time(:millisecond)
    prove_env = with_trace_flag(env, trace_level, func.name)
    base_meta = %{has_pre: not is_nil(func.pre_condition), has_post: not is_nil(func.post_condition), body_stack_depth: nil}

    result_and_meta =
      with :ok <- check_z3_available(),
           {:ok, initial_stack, vars, base_constraint} <- Symbolic.build_initial_stack(func.param_types, prove_env),
           {:ok, pre_constraint, body_stack} <- execute_pre_traced(func, initial_stack, with_phase(prove_env, "pre")),
           prove_env <- enrich_env_with_pre_assumptions(prove_env, pre_constraint),
           {:ok, result_stack} <- execute_body_traced(func, body_stack, with_phase(prove_env, "body")),
           {:ok, post_constraint} <- execute_post_traced(func, result_stack, with_phase(prove_env, "post")),
           {result, _z3_meta} <- query_z3_traced(vars, combine_constraints(base_constraint, pre_constraint), post_constraint, func, env) do
        {result, Map.put(base_meta, :body_stack_depth, length(result_stack))}
      else
        {:unsupported, reason} ->
          {{:unknown, reason}, base_meta}

        {:error, reason} ->
          {{:error, reason}, base_meta}
      end

    {result, run_meta} = result_and_meta
    maybe_emit_trace(func.name, result, trace_level, trace_started_at_ms, run_meta)
    result
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

  defp execute_pre_traced(func, initial_stack, env) do
    case execute_pre(func, initial_stack, env) do
      {:ok, _constraint, body_stack} = ok ->
        append_trace_event(%{
          event: "pre_executed",
          phase: "pre",
          status: "ok",
          has_pre: not is_nil(func.pre_condition),
          stack_depth: length(body_stack)
        })

        ok

      {:unsupported, reason} = err ->
        append_trace_event(%{
          event: "pre_executed",
          phase: "pre",
          status: "unsupported",
          has_pre: not is_nil(func.pre_condition),
          reason: reason
        })

        err

      {:error, reason} = err ->
        append_trace_event(%{
          event: "pre_executed",
          phase: "pre",
          status: "error",
          has_pre: not is_nil(func.pre_condition),
          reason: reason
        })

        err
    end
  end

  # Execute body symbolically
  defp execute_body(%Function{body: body}, stack, env) do
    case Symbolic.execute(body, stack, env) do
      {:ok, _} = result -> result
      {:unsupported, _} = result -> result
    end
  end

  defp execute_body_traced(func, stack, env) do
    case execute_body(func, stack, env) do
      {:ok, result_stack} = ok ->
        append_trace_event(%{
          event: "body_executed",
          phase: "body",
          status: "ok",
          stack_depth: length(result_stack)
        })

        ok

      {:unsupported, reason} = err ->
        append_trace_event(%{
          event: "body_executed",
          phase: "body",
          status: "unsupported",
          reason: reason
        })

        err
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

  defp execute_post_traced(func, result_stack, env) do
    case execute_post(func, result_stack, env) do
      {:ok, _constraint} = ok ->
        append_trace_event(%{
          event: "post_executed",
          phase: "post",
          status: "ok",
          has_post: not is_nil(func.post_condition),
          stack_depth: length(result_stack)
        })

        ok

      {:unsupported, reason} = err ->
        append_trace_event(%{
          event: "post_executed",
          phase: "post",
          status: "unsupported",
          has_post: not is_nil(func.post_condition),
          reason: reason
        })

        err

      {:error, reason} = err ->
        append_trace_event(%{
          event: "post_executed",
          phase: "post",
          status: "error",
          has_post: not is_nil(func.post_condition),
          reason: reason
        })

        err
    end
  end

  # Generate SMT-LIB, query Z3, interpret result
  defp query_z3_traced(vars, pre_constraint, post_constraint, func, env) do
    script = SmtLib.build_script(vars, pre_constraint, post_constraint)
    z3_raw = Z3.query(script)

    z3_result =
      case z3_raw do
        :unsat -> "unsat"
        {:sat, _model} -> "sat"
        {:error, _reason} -> "error"
      end

    append_trace_event(%{
      event: "z3_query",
      phase: "solve",
      status: "ok",
      var_count: length(vars),
      z3_result: z3_result
    })

    case z3_raw do
      :unsat ->
        {{:proven, "POST holds for all inputs satisfying PRE"}, %{z3_result: "unsat"}}

      {:sat, model} ->
        {{:disproven, format_counterexample(model, func, env), model}, %{z3_result: "sat"}}

      {:error, reason} ->
        {{:error, reason}, %{z3_result: "error"}}
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

  defp assumption_map_from_constraint(constraint) do
    constraint
    |> PreNormalize.normalize()
    |> do_assumption_map_from_constraint()
  end

  defp do_assumption_map_from_constraint({:and, a, b}) do
    merge_assumption_maps(do_assumption_map_from_constraint(a), do_assumption_map_from_constraint(b), :and)
  end

  defp do_assumption_map_from_constraint({:or, a, b}) do
    merge_assumption_maps(do_assumption_map_from_constraint(a), do_assumption_map_from_constraint(b), :or)
  end

  defp do_assumption_map_from_constraint({:eq, {:var, var}, {:const, value}}) when is_integer(value) do
    %{var => %{eq: value, neq: MapSet.new()}}
  end

  defp do_assumption_map_from_constraint({:eq, {:const, value}, {:var, var}}) when is_integer(value) do
    %{var => %{eq: value, neq: MapSet.new()}}
  end

  defp do_assumption_map_from_constraint({:neq, {:var, var}, {:const, value}}) when is_integer(value) do
    %{var => %{eq: nil, neq: MapSet.new([value])}}
  end

  defp do_assumption_map_from_constraint({:neq, {:const, value}, {:var, var}}) when is_integer(value) do
    %{var => %{eq: nil, neq: MapSet.new([value])}}
  end

  defp do_assumption_map_from_constraint({:not, {:eq, {:var, var}, {:const, value}}}) when is_integer(value) do
    %{var => %{eq: nil, neq: MapSet.new([value])}}
  end

  defp do_assumption_map_from_constraint({:not, {:eq, {:const, value}, {:var, var}}}) when is_integer(value) do
    %{var => %{eq: nil, neq: MapSet.new([value])}}
  end

  defp do_assumption_map_from_constraint({:not, {:neq, {:var, var}, {:const, value}}}) when is_integer(value) do
    %{var => %{eq: value, neq: MapSet.new()}}
  end

  defp do_assumption_map_from_constraint({:not, {:neq, {:const, value}, {:var, var}}}) when is_integer(value) do
    %{var => %{eq: value, neq: MapSet.new()}}
  end

  defp do_assumption_map_from_constraint({:not, {:not, inner}}) do
    do_assumption_map_from_constraint(inner)
  end

  defp do_assumption_map_from_constraint({:not, {:ite_bool, cond, true, false}}) do
    do_assumption_map_from_constraint({:not, cond})
  end

  defp do_assumption_map_from_constraint({:not, {:ite_bool, cond, false, true}}) do
    do_assumption_map_from_constraint(cond)
  end

  defp do_assumption_map_from_constraint({:ite_bool, cond, true, false}) do
    do_assumption_map_from_constraint(cond)
  end

  defp do_assumption_map_from_constraint({:ite_bool, cond, false, true}) do
    do_assumption_map_from_constraint({:not, cond})
  end

  defp do_assumption_map_from_constraint(_constraint), do: %{}

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

  defp trace_level(env) do
    env_value = Map.get(env, "__prove_trace__", :unset)
    sys_value = System.get_env("AXIOM_PROVE_TRACE")

    case normalize_trace_value(env_value) do
      :off ->
        :off

      :summary ->
        :summary

      :verbose ->
        :verbose

      :json ->
        :json

      :unset ->
        normalize_trace_value(sys_value)
    end
  end

  defp normalize_trace_value(:unset), do: :unset
  defp normalize_trace_value(nil), do: :off
  defp normalize_trace_value(false), do: :off
  defp normalize_trace_value(true), do: :summary
  defp normalize_trace_value(:off), do: :off
  defp normalize_trace_value(:summary), do: :summary
  defp normalize_trace_value(:verbose), do: :verbose
  defp normalize_trace_value(:json), do: :json
  defp normalize_trace_value("0"), do: :off
  defp normalize_trace_value("false"), do: :off
  defp normalize_trace_value("off"), do: :off
  defp normalize_trace_value("1"), do: :summary
  defp normalize_trace_value("true"), do: :summary
  defp normalize_trace_value("summary"), do: :summary
  defp normalize_trace_value("verbose"), do: :verbose
  defp normalize_trace_value("json"), do: :json
  defp normalize_trace_value(_), do: :off

  defp with_trace_flag(env, :off, func_name), do: Map.put(env, "__prove_func_name__", func_name)

  defp with_trace_flag(env, level, func_name) when level in [:summary, :verbose, :json] do
    env
    |> Map.put("__prove_trace_enabled__", true)
    |> Map.put("__prove_trace_level__", level)
    |> Map.put("__prove_func_name__", func_name)
  end

  defp maybe_emit_trace(_func_name, _result, :off, _started_at_ms, _run_meta), do: :ok

  defp maybe_emit_trace(func_name, result, :json, started_at_ms, run_meta) do
    status =
      case result do
        {:proven, _} -> "PROVEN"
        {:disproven, _, _} -> "DISPROVEN"
        {:unknown, _} -> "UNKNOWN"
        {:error, _} -> "ERROR"
      end

    events = get_trace_events()
    elapsed_ms = max(System.monotonic_time(:millisecond) - started_at_ms, 0)
    match_events = Enum.filter(events, fn e -> Map.get(e, :event) == "match_decision" end)
    pruned_total = Enum.reduce(match_events, 0, fn e, acc -> acc + length(Map.get(e, :pruned, [])) end)
    match_count = length(match_events)
    {unknown_reason, error_reason} = result_reasons(result)

    run_start = %{
      event: "prove_run_start",
      function: func_name,
      status: status,
      trace_level: "json",
      has_pre: Map.get(run_meta, :has_pre, false),
      has_post: Map.get(run_meta, :has_post, false)
    }

    run_end = %{
      event: "prove_run_end",
      function: func_name,
      status: status,
      trace_level: "json",
      match_event_count: match_count,
      pruned_branch_count: pruned_total,
      elapsed_ms: elapsed_ms,
      body_stack_depth: Map.get(run_meta, :body_stack_depth, nil),
      has_pre: Map.get(run_meta, :has_pre, false),
      has_post: Map.get(run_meta, :has_post, false),
      unknown_reason: unknown_reason,
      error_reason: error_reason
    }

    all_events = [run_start | events] ++ [run_end]

    all_events
    |> Enum.with_index()
    |> Enum.each(fn {event, idx} ->
      payload =
        event
        |> Map.put_new(:function, func_name)
        |> Map.put_new(:status, status)
        |> Map.put_new(:trace_level, "json")
        |> Map.put(:event_index, idx)

      IO.puts(:stderr, json_encode(payload))
    end)

    :ok
  end

  defp maybe_emit_trace(func_name, result, trace_level, _started_at_ms, _run_meta) when trace_level in [:summary, :verbose] do
    status =
      case result do
        {:proven, _} -> "PROVEN"
        {:disproven, _, _} -> "DISPROVEN"
        {:unknown, _} -> "UNKNOWN"
        {:error, _} -> "ERROR"
      end

    events = get_trace_events()

    if events == [] do
      IO.puts(:stderr, "PROVE TRACE #{func_name} (#{status}): no MATCH branch events")
    else
      IO.puts(:stderr, "PROVE TRACE #{func_name} (#{status}, #{trace_level}):")
      Enum.each(events, fn event ->
        IO.puts(:stderr, "  - " <> human_trace_line(event, trace_level))
      end)
    end

    :ok
  end

  defp clear_trace_events do
    Process.put(:axiom_prove_trace_events, [])
  end

  defp append_trace_event(event) when is_map(event) do
    events = Process.get(:axiom_prove_trace_events, [])
    Process.put(:axiom_prove_trace_events, [event | events])
  end

  defp get_trace_events do
    (Process.get(:axiom_prove_trace_events) || [])
    |> Enum.reverse()
  end

  defp with_phase(env, phase), do: Map.put(env, "__prove_phase__", phase)

  defp result_reasons({:unknown, reason}), do: {reason, nil}
  defp result_reasons({:error, reason}), do: {nil, reason}
  defp result_reasons(_), do: {nil, nil}

  defp human_trace_line(event, :summary) do
    pruned_txt =
      case Map.get(event, :pruned, []) do
        [] -> "none"
        values -> Enum.join(values, ",")
      end

    "MATCH #{Map.get(event, :type, "?")}: explored=#{Map.get(event, :explored, "?")} pruned=#{pruned_txt} reason=#{Map.get(event, :reason, "unknown")}"
  end

  defp human_trace_line(event, :verbose) do
    base = human_trace_line(event, :summary)
    candidates = Map.get(event, :candidates, []) |> Enum.join(",")
    "#{base} candidates=#{candidates} tag=#{Map.get(event, :tag, "?")}"
  end

  defp json_encode(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map(fn {k, v} -> "\"#{json_escape(k)}\":#{json_encode(v)}" end)
    |> Enum.join(",")
    |> then(&("{#{&1}}"))
  end

  defp json_encode(list) when is_list(list) do
    list
    |> Enum.map(&json_encode/1)
    |> Enum.join(",")
    |> then(&("[#{&1}]"))
  end

  defp json_encode(v) when is_binary(v), do: "\"#{json_escape(v)}\""
  defp json_encode(v) when is_integer(v), do: Integer.to_string(v)
  defp json_encode(true), do: "true"
  defp json_encode(false), do: "false"
  defp json_encode(nil), do: "null"
  defp json_encode(v), do: "\"#{json_escape(to_string(v))}\""

  defp json_escape(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end

  defp combine_constraints(true, c), do: c
  defp combine_constraints(c, true), do: c
  defp combine_constraints(a, b), do: {:and, a, b}
end
