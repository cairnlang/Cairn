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

  @max_inline_depth 10

  @doc """
  Symbolically execute a list of tokens starting from the given symbolic stack.

  Returns `{:ok, stack}` on success or `{:unsupported, reason}` if the token
  list contains operations we can't handle symbolically.

  The optional `env` parameter provides function definitions for inlining calls.
  """
  @spec execute([Axiom.Types.token()], [Formula.sym_val()], map()) :: result()
  def execute(tokens, stack, env \\ %{}) do
    walk(tokens, stack, env, 0)
  end

  @doc """
  Build an initial symbolic stack for the given param types.

  For `[:int, :int]`, returns `[{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]`
  where p0 is the top of stack (first param).

  Returns `{:ok, stack, vars, base_constraint}`.
  `base_constraint` encodes domain assumptions for symbolic types (e.g. option tags).
  """
  @spec build_initial_stack([Axiom.Types.axiom_type()], map()) ::
          {:ok, [Formula.sym_val()], [String.t()], Formula.constraint()}
          | {:unsupported, String.t()}
  def build_initial_stack(param_types, env \\ %{}) do
    indexed = Enum.with_index(param_types)
    types = Map.get(env, "__types__", %{})

    result =
      Enum.reduce_while(indexed, {:ok, [], [], []}, fn {type, i}, {:ok, stack, vars, constraints} ->
        case type do
          :int ->
            var = "p#{i}"
            {:cont, {:ok, [{:int_expr, {:var, var}} | stack], [var | vars], constraints}}

          {:user_type, "option"} ->
            tag_var = "p#{i}_tag"
            val_var = "p#{i}_val"

            tag_expr = {:var, tag_var}
            val_expr = {:var, val_var}

            option_domain =
              {:or, {:eq, tag_expr, {:const, 0}}, {:eq, tag_expr, {:const, 1}}}

            {:cont,
             {:ok, [{:option_expr, tag_expr, val_expr} | stack], [val_var, tag_var | vars],
              [option_domain | constraints]}}

          {:user_type, "result"} ->
            tag_var = "p#{i}_tag"
            ok_var = "p#{i}_ok"
            err_var = "p#{i}_err"

            tag_expr = {:var, tag_var}
            ok_expr = {:var, ok_var}

            result_domain =
              {:or, {:eq, tag_expr, {:const, 0}}, {:eq, tag_expr, {:const, 1}}}

            {:cont,
             {:ok, [{:result_expr, tag_expr, ok_expr, err_var} | stack], [ok_var, tag_var | vars],
              [result_domain | constraints]}}

          {:user_type, type_name} ->
            case build_user_type_symbolic_param(type_name, i, types) do
              {:ok, sym_val, new_vars, constraint} ->
                {:cont, {:ok, [sym_val | stack], Enum.reverse(new_vars) ++ vars, [constraint | constraints]}}

              {:unsupported, _} = err ->
                {:halt, err}
            end

          _ ->
            {:halt,
             {:unsupported,
              "parameter type #{inspect(type)} is not supported by PROVE (supported: int, option, result, and non-recursive int-field user ADTs)"}}
        end
      end)

    case result do
      {:ok, stack_rev, vars_rev, constraints_rev} ->
        stack = Enum.reverse(stack_rev)
        vars = Enum.reverse(vars_rev)
        base_constraint = join_constraints(Enum.reverse(constraints_rev))
        {:ok, stack, vars, base_constraint}

      {:unsupported, _} = err ->
        err
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
  # env: map of function names to %Function{} structs for inlining
  # depth: recursion depth counter for inlining limit

  defp walk([], stack, _env, _depth), do: {:ok, stack}

  # Integer literal
  defp walk([{:int_lit, n, _} | rest], stack, env, depth) do
    walk(rest, [{:int_expr, {:const, n}} | stack], env, depth)
  end

  # Boolean literal
  defp walk([{:bool_lit, true, _} | rest], stack, env, depth) do
    walk(rest, [{:bool_expr, true} | stack], env, depth)
  end

  defp walk([{:bool_lit, false, _} | rest], stack, env, depth) do
    walk(rest, [{:bool_expr, false} | stack], env, depth)
  end

  # Option constructors (limited support for PROVE option MATCH milestone)
  defp walk([{:constructor, "Some", _} | rest], [{:int_expr, payload} | stack], env, depth) do
    walk(rest, [{:option_expr, {:const, 1}, payload} | stack], env, depth)
  end

  defp walk([{:constructor, "None", _} | rest], stack, env, depth) do
    walk(rest, [{:option_expr, {:const, 0}, {:const, 0}} | stack], env, depth)
  end

  # Result constructors (narrow support for result MATCH proving slice)
  defp walk([{:constructor, "Ok", _} | rest], [{:int_expr, payload} | stack], env, depth) do
    walk(rest, [{:result_expr, {:const, 1}, payload, "__err"} | stack], env, depth)
  end

  defp walk([{:constructor, "Err", _} | rest], [{:opaque_expr, err_id} | stack], env, depth) do
    walk(rest, [{:result_expr, {:const, 0}, {:const, 0}, err_id} | stack], env, depth)
  end

  # Generic constructor support for user ADTs (non-recursive int-field slices)
  defp walk([{:constructor, name, _} | rest], stack, env, depth) do
    ctors = Map.get(env, "__constructors__", %{})
    types = Map.get(env, "__types__", %{})

    case Map.get(ctors, name) do
      nil ->
        {:unsupported, "constructor '#{name}' is not available in PROVE"}

      {type_name, field_types} ->
        with {:ok, typedef} <- fetch_typedef(type_name, types),
             {:ok, field_vals, remaining_stack} <- pop_constructor_fields(stack, field_types) do
          ctor_order = ctor_order(typedef)
          tag = ctor_index(ctor_order, name)
          payload_map = constructor_payload_map(typedef, name, field_vals)
          walk(rest, [{:variant_expr, type_name, {:const, tag}, payload_map} | remaining_stack], env, depth)
        else
          {:unsupported, _} = err -> err
        end
    end
  end

  # Arithmetic: ADD, SUB, MUL, DIV, MOD
  defp walk([{:op, :add, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:int_expr, {:add, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :sub, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:int_expr, {:sub, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :mul, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:int_expr, {:mul, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :div, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:int_expr, {:div, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :mod, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:int_expr, {:mod, b, a}} | stack], env, depth)
  end

  # Unary: NEG
  defp walk([{:op, :neg, _} | rest], [{:int_expr, a} | stack], env, depth) do
    walk(rest, [{:int_expr, {:neg, a}} | stack], env, depth)
  end

  # SQ: a -> a*a
  defp walk([{:op, :sq, _} | rest], [{:int_expr, a} | stack], env, depth) do
    walk(rest, [{:int_expr, {:mul, a, a}} | stack], env, depth)
  end

  # Comparisons: GTE, GT, LTE, LT, EQ, NEQ
  defp walk([{:op, :gte, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:bool_expr, {:gte, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :gt, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:bool_expr, {:gt, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :lte, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:bool_expr, {:lte, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :lt, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:bool_expr, {:lt, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :eq, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:bool_expr, {:eq, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :neq, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    walk(rest, [{:bool_expr, {:neq, b, a}} | stack], env, depth)
  end

  # Boolean EQ/NEQ (compare two booleans)
  defp walk([{:op, :eq, _} | rest], [{:bool_expr, a}, {:bool_expr, b} | stack], env, depth) do
    # a EQ b is equivalent to (a AND b) OR (NOT a AND NOT b)
    equiv = {:or, {:and, b, a}, {:and, {:not, b}, {:not, a}}}
    walk(rest, [{:bool_expr, equiv} | stack], env, depth)
  end

  defp walk([{:op, :neq, _} | rest], [{:bool_expr, a}, {:bool_expr, b} | stack], env, depth) do
    # a NEQ b is NOT (a EQ b)
    equiv = {:not, {:or, {:and, b, a}, {:and, {:not, b}, {:not, a}}}}
    walk(rest, [{:bool_expr, equiv} | stack], env, depth)
  end

  # Logic: AND, OR, NOT
  defp walk([{:op, :and, _} | rest], [{:bool_expr, a}, {:bool_expr, b} | stack], env, depth) do
    walk(rest, [{:bool_expr, {:and, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :or, _} | rest], [{:bool_expr, a}, {:bool_expr, b} | stack], env, depth) do
    walk(rest, [{:bool_expr, {:or, b, a}} | stack], env, depth)
  end

  defp walk([{:op, :not, _} | rest], [{:bool_expr, a} | stack], env, depth) do
    walk(rest, [{:bool_expr, {:not, a}} | stack], env, depth)
  end

  # Stack manipulation: DUP, DROP, SWAP, OVER, ROT
  defp walk([{:op, :dup, _} | rest], [top | _] = stack, env, depth) do
    walk(rest, [top | stack], env, depth)
  end

  defp walk([{:op, :drop, _} | rest], [_ | stack], env, depth) do
    walk(rest, stack, env, depth)
  end

  defp walk([{:op, :swap, _} | rest], [a, b | stack], env, depth) do
    walk(rest, [b, a | stack], env, depth)
  end

  defp walk([{:op, :over, _} | rest], [_a, b | _] = stack, env, depth) do
    walk(rest, [b | stack], env, depth)
  end

  defp walk([{:op, :rot, _} | rest], [a, b, c | stack], env, depth) do
    walk(rest, [c, a, b | stack], env, depth)
  end

  # ROT4: [a, b, c, d | rest] -> [d, a, b, c | rest]
  defp walk([{:op, :rot4, _} | rest], [a, b, c, d | stack], env, depth) do
    walk(rest, [d, a, b, c | stack], env, depth)
  end

  # ABS: ite(a < 0, -a, a)
  defp walk([{:op, :abs, _} | rest], [{:int_expr, a} | stack], env, depth) do
    result = {:int_expr, {:ite, {:lt, a, {:const, 0}}, {:neg, a}, a}}
    walk(rest, [result | stack], env, depth)
  end

  # MIN: ite(b < a, b, a) — b is deeper, a is top
  defp walk([{:op, :min, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    result = {:int_expr, {:ite, {:lt, b, a}, b, a}}
    walk(rest, [result | stack], env, depth)
  end

  # MAX: ite(b > a, b, a) — b is deeper, a is top
  defp walk([{:op, :max, _} | rest], [{:int_expr, a}, {:int_expr, b} | stack], env, depth) do
    result = {:int_expr, {:ite, {:gt, b, a}, b, a}}
    walk(rest, [result | stack], env, depth)
  end

  defp walk([{:op, op, _} | _], _stack, _env, _depth)
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
              :sin,
              :cos,
              :exp,
              :log,
              :sqrt,
              :pow,
              :pi,
              :e,
              :floor,
              :ceil,
              :round,
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
  defp walk([{:float_lit, _, _} | _], _stack, _env, _depth) do
    {:unsupported, "float literals are not supported by PROVE"}
  end

  # String literals are unsupported
  defp walk([{:str_lit, _, _} | _], _stack, _env, _depth) do
    {:unsupported, "string literals are not supported by PROVE"}
  end

  # List/map literals are unsupported
  defp walk([{:list_open, _, _} | _], _stack, _env, _depth) do
    {:unsupported, "list operations are not supported by PROVE — use VERIFY instead"}
  end

  defp walk([{:list_lit, _, _} | _], _stack, _env, _depth) do
    {:unsupported, "list operations are not supported by PROVE — use VERIFY instead"}
  end

  defp walk([{:map_open, _, _} | _], _stack, _env, _depth) do
    {:unsupported, "map operations are not supported by PROVE — use VERIFY instead"}
  end

  defp walk([{:map_lit, _, _} | _], _stack, _env, _depth) do
    {:unsupported, "map operations are not supported by PROVE — use VERIFY instead"}
  end

  # IF/ELSE path-splitting: symbolically execute both branches and merge with ite
  defp walk([{:if_kw, _, _} | rest], [{:bool_expr, cond} | stack], env, depth) do
    {then_tokens, else_tokens, remaining} = split_if_branches(rest)

    with {:ok, then_stack} <- walk(then_tokens, stack, env, depth),
         {:ok, else_stack} <-
           if(else_tokens, do: walk(else_tokens, stack, env, depth), else: {:ok, stack}) do
      case merge_stacks(cond, then_stack, else_stack) do
        {:ok, merged} -> walk(remaining, merged, env, depth)
        {:unsupported, _} = err -> err
      end
    end
  end

  # MATCH support (narrow scope): option
  defp walk([{:match_kw, _, pos} | rest], [{:option_expr, tag, payload} | stack], env, depth) do
    {arms, remaining} = collect_match_arms(rest, [])
    possible = possible_tag_indexes(tag, 2, env)
    candidate_names = option_candidate_names(possible)
    details = match_trace_details("option", tag, env, pos, candidate_names)

    with {:ok, some_tokens, none_tokens} <- resolve_option_arms(arms) do
      case possible do
        [1] ->
          trace_match_decision(env, "option", "Some", ["None"], reason_for_tag_prune(tag, env), details)

          with {:ok, some_stack} <- walk(some_tokens, [{:int_expr, payload} | stack], env, depth) do
            walk(remaining, some_stack, env, depth)
          end

        [0] ->
          trace_match_decision(env, "option", "None", ["Some"], reason_for_tag_prune(tag, env), details)

          with {:ok, none_stack} <- walk(none_tokens, stack, env, depth) do
            walk(remaining, none_stack, env, depth)
          end

        _ ->
          trace_match_decision(env, "option", "Some+None", [], "unknown", details)

          with {:ok, some_stack} <- walk(some_tokens, [{:int_expr, payload} | stack], env, depth),
               {:ok, none_stack} <- walk(none_tokens, stack, env, depth),
               {:ok, merged} <- merge_stacks({:eq, tag, {:const, 1}}, some_stack, none_stack) do
            walk(remaining, merged, env, depth)
          end
      end
    end
  end

  # MATCH support (narrow scope): result
  defp walk([{:match_kw, _, pos} | rest], [{:result_expr, tag, ok_payload, err_id} | stack], env, depth) do
    {arms, remaining} = collect_match_arms(rest, [])
    possible = possible_tag_indexes(tag, 2, env)
    candidate_names = result_candidate_names(possible)
    details = match_trace_details("result", tag, env, pos, candidate_names)

    with {:ok, ok_tokens, err_tokens} <- resolve_result_arms(arms) do
      case possible do
        [1] ->
          trace_match_decision(env, "result", "Ok", ["Err"], reason_for_tag_prune(tag, env), details)

          with {:ok, ok_stack} <- walk(ok_tokens, [{:int_expr, ok_payload} | stack], env, depth) do
            walk(remaining, ok_stack, env, depth)
          end

        [0] ->
          trace_match_decision(env, "result", "Err", ["Ok"], reason_for_tag_prune(tag, env), details)

          with {:ok, err_stack} <- walk(err_tokens, [{:opaque_expr, err_id} | stack], env, depth) do
            walk(remaining, err_stack, env, depth)
          end

        _ ->
          trace_match_decision(env, "result", "Ok+Err", [], "unknown", details)

          with {:ok, ok_stack} <- walk(ok_tokens, [{:int_expr, ok_payload} | stack], env, depth),
               {:ok, err_stack} <- walk(err_tokens, [{:opaque_expr, err_id} | stack], env, depth),
               {:ok, merged} <- merge_stacks({:eq, tag, {:const, 1}}, ok_stack, err_stack) do
            walk(remaining, merged, env, depth)
          end
      end
    end
  end

  # MATCH support (generic non-recursive int-field ADTs)
  defp walk([{:match_kw, _, pos} | rest], [{:variant_expr, type_name, tag, payload_map} | stack], env, depth) do
    {arms, remaining} = collect_match_arms(rest, [])
    types = Map.get(env, "__types__", %{})

    with {:ok, typedef} <- fetch_typedef(type_name, types),
         {:ok, arm_tokens_by_ctor} <- resolve_generic_arms(typedef, arms),
         {:ok, merged_stack} <- execute_and_merge_generic_match(typedef, tag, payload_map, stack, arm_tokens_by_ctor, env, depth, pos) do
      walk(remaining, merged_stack, env, depth)
    end
  end

  defp walk([{:match_kw, _, _} | _], [_ | _], _env, _depth) do
    {:unsupported, "MATCH in PROVE currently supports option/result and non-recursive int-field user ADTs"}
  end

  defp walk([{:match_kw, _, _} | _], [], _env, _depth) do
    {:unsupported, "MATCH in PROVE requires a value on the stack"}
  end

  # Block literals are unsupported
  defp walk([{:block_open, _, _} | _], _stack, _env, _depth) do
    {:unsupported, "block literals are not supported by PROVE — use VERIFY instead"}
  end

  # Function call inlining: look up in env, pop args, execute body, push results
  defp walk([{:ident, name, _} | rest], stack, env, depth) do
    case Map.get(env, name) do
      %Axiom.Types.Function{} = func when depth < @max_inline_depth ->
        arity = length(func.param_types)
        {args, remaining_stack} = Enum.split(stack, arity)

        if length(args) < arity do
          {:unsupported, "function call '#{name}' requires #{arity} args, stack has #{length(args)}"}
        else
          case walk(func.body, args, env, depth + 1) do
            {:ok, result_stack} ->
              walk(rest, result_stack ++ remaining_stack, env, depth)

            {:unsupported, _} = err ->
              err
          end
        end

      %Axiom.Types.Function{} ->
        {:unsupported, "function call '#{name}' exceeds maximum inlining depth (#{@max_inline_depth})"}

      nil ->
        {:unsupported, "function call '#{name}' is not supported by PROVE — use VERIFY instead"}
    end
  end

  # Catch-all: unsupported token
  defp walk([token | _], _stack, _env, _depth) do
    {:unsupported, "unsupported token #{inspect(token)} in PROVE"}
  end

  # --- IF/ELSE branch splitting ---

  defp split_if_branches(tokens), do: split_if_then(tokens, 0, [])

  defp split_if_then([{:fn_end, _, _} | rest], 0, acc) do
    {Enum.reverse(acc), nil, rest}
  end

  defp split_if_then([{:else_kw, _, _} | rest], 0, acc) do
    split_if_else(rest, 0, Enum.reverse(acc), [])
  end

  defp split_if_then([{:if_kw, _, _} = t | rest], depth, acc) do
    split_if_then(rest, depth + 1, [t | acc])
  end

  defp split_if_then([{:fn_end, _, _} = t | rest], depth, acc) when depth > 0 do
    split_if_then(rest, depth - 1, [t | acc])
  end

  defp split_if_then([t | rest], depth, acc) do
    split_if_then(rest, depth, [t | acc])
  end

  defp split_if_else([{:fn_end, _, _} | rest], 0, then_branch, acc) do
    {then_branch, Enum.reverse(acc), rest}
  end

  defp split_if_else([{:if_kw, _, _} = t | rest], depth, then_branch, acc) do
    split_if_else(rest, depth + 1, then_branch, [t | acc])
  end

  defp split_if_else([{:fn_end, _, _} = t | rest], depth, then_branch, acc) when depth > 0 do
    split_if_else(rest, depth - 1, then_branch, [t | acc])
  end

  defp split_if_else([t | rest], depth, then_branch, acc) do
    split_if_else(rest, depth, then_branch, [t | acc])
  end

  # --- MATCH arm parsing (Constructor { ... } ... END) ---

  defp collect_match_arms([{:fn_end, _, _} | rest], arms) do
    {Enum.reverse(arms), rest}
  end

  defp collect_match_arms([{:constructor, name, _}, {:block_open, _, _} | rest], arms) do
    {block_tokens, remaining} = collect_block_tokens(rest, 0, [])
    collect_match_arms(remaining, [{name, block_tokens} | arms])
  end

  defp collect_match_arms([{:wildcard, _, _}, {:block_open, _, _} | rest], arms) do
    {block_tokens, remaining} = collect_block_tokens(rest, 0, [])
    collect_match_arms(remaining, [{:wildcard, block_tokens} | arms])
  end

  defp collect_match_arms([], _arms) do
    raise "MATCH without matching END in symbolic execution"
  end

  defp collect_match_arms([_ | rest], arms) do
    collect_match_arms(rest, arms)
  end

  defp collect_block_tokens([], _depth, _acc) do
    raise "unmatched block in symbolic MATCH arm"
  end

  defp collect_block_tokens([{:block_close, _, _} | rest], 0, acc) do
    {Enum.reverse(acc), rest}
  end

  defp collect_block_tokens([{:block_open, _, _} = t | rest], depth, acc) do
    collect_block_tokens(rest, depth + 1, [t | acc])
  end

  defp collect_block_tokens([{:block_close, _, _} = t | rest], depth, acc) when depth > 0 do
    collect_block_tokens(rest, depth - 1, [t | acc])
  end

  defp collect_block_tokens([t | rest], depth, acc) do
    collect_block_tokens(rest, depth, [t | acc])
  end

  defp resolve_option_arms(arms) do
    invalid =
      Enum.find(arms, fn {name, _} ->
        name not in ["Some", "None", :wildcard]
      end)

    case invalid do
      {name, _} ->
        {:unsupported, "MATCH in PROVE currently supports option arms only (found #{inspect(name)})"}

      nil ->
        wildcard = find_arm(arms, :wildcard)
        some = find_arm(arms, "Some") || wildcard
        none = find_arm(arms, "None") || wildcard

        cond do
          is_nil(some) ->
            {:unsupported, "MATCH on option in PROVE is missing Some arm (or wildcard)"}

          is_nil(none) ->
            {:unsupported, "MATCH on option in PROVE is missing None arm (or wildcard)"}

          true ->
            {:ok, some, none}
        end
    end
  end

  defp resolve_result_arms(arms) do
    invalid =
      Enum.find(arms, fn {name, _} ->
        name not in ["Ok", "Err", :wildcard]
      end)

    case invalid do
      {name, _} ->
        {:unsupported, "MATCH in PROVE currently supports result arms only (found #{inspect(name)})"}

      nil ->
        wildcard = find_arm(arms, :wildcard)
        ok_tokens = find_arm(arms, "Ok") || wildcard
        err_tokens = find_arm(arms, "Err") || wildcard

        cond do
          is_nil(ok_tokens) ->
            {:unsupported, "MATCH on result in PROVE is missing Ok arm (or wildcard)"}

          is_nil(err_tokens) ->
            {:unsupported, "MATCH on result in PROVE is missing Err arm (or wildcard)"}

          true ->
            {:ok, ok_tokens, err_tokens}
        end
    end
  end

  defp fetch_typedef(type_name, types) do
    case Map.get(types, type_name) do
      nil -> {:unsupported, "type '#{type_name}' is not registered for PROVE"}
      typedef -> {:ok, typedef}
    end
  end

  defp pop_constructor_fields(stack, field_types) do
    arity = length(field_types)
    {vals, remaining} = Enum.split(stack, arity)

    if length(vals) < arity do
      {:unsupported, "constructor expects #{arity} field(s), stack has #{length(vals)}"}
    else
      converted =
        Enum.zip(vals, field_types)
        |> Enum.map(fn {v, t} -> convert_field_value(v, t) end)

      if Enum.any?(converted, &match?({:unsupported, _}, &1)) do
        {:unsupported, "constructor field types are not supported by PROVE (supported fields: int)"}
      else
        {:ok, Enum.map(converted, fn {:ok, vv} -> vv end), remaining}
      end
    end
  end

  defp convert_field_value({:int_expr, _} = v, :int), do: {:ok, v}
  defp convert_field_value({:bool_expr, _} = v, :bool), do: {:ok, v}
  defp convert_field_value({:opaque_expr, _} = v, _), do: {:ok, v}
  defp convert_field_value({:variant_expr, _, _, _} = v, _), do: {:ok, v}
  defp convert_field_value(_, _), do: {:unsupported, :field}

  defp constructor_payload_map(typedef, active_ctor, active_vals) do
    ctor_order(typedef)
    |> Enum.reduce(%{}, fn ctor, acc ->
      fields = Map.get(typedef.variants, ctor, [])

      vals =
        if ctor == active_ctor do
          active_vals
        else
          Enum.map(0..(max(length(fields) - 1, 0)), fn i -> {:opaque_expr, "__#{ctor}_#{i}"} end)
        end

      vals =
        if fields == [] do
          []
        else
          vals
        end

      Map.put(acc, ctor, vals)
    end)
  end

  defp resolve_generic_arms(typedef, arms) do
    ctors = ctor_order(typedef)
    wildcard = find_arm(arms, :wildcard)

    invalid =
      Enum.find(arms, fn {name, _} ->
        name != :wildcard and name not in ctors
      end)

    case invalid do
      {name, _} ->
        {:unsupported, "MATCH in PROVE has unknown arm #{inspect(name)} for type '#{typedef.name}'"}

      nil ->
        resolved =
          Enum.map(ctors, fn ctor ->
            case find_arm(arms, ctor) || wildcard do
              nil -> {:missing, ctor}
              tokens -> {ctor, tokens}
            end
          end)

        case Enum.find(resolved, &match?({:missing, _}, &1)) do
          {:missing, ctor} ->
            {:unsupported, "MATCH on '#{typedef.name}' in PROVE is missing #{ctor} arm (or wildcard)"}

          nil ->
            {:ok, Map.new(resolved)}
        end
    end
  end

  defp execute_and_merge_generic_match(typedef, tag, payload_map, base_stack, arm_map, env, depth, pos) do
    ctors = ctor_order(typedef)
    possible = possible_tag_indexes(tag, length(ctors), env)
    possible_ctors = Enum.map(possible, &Enum.at(ctors, &1))
    pruned_ctors = ctors -- possible_ctors
    details = match_trace_details(typedef.name, tag, env, pos, possible_ctors)
    trace_match_decision(env, typedef.name, Enum.join(possible_ctors, "+"), pruned_ctors, reason_for_tag_prune(tag, env), details)

    case possible do
      [idx] when is_integer(idx) and idx >= 0 and idx < length(ctors) ->
        ctor = Enum.at(ctors, idx)
        ctor_payload = Map.get(payload_map, ctor, [])
        arm_tokens = Map.fetch!(arm_map, ctor)
        branch_stack = Enum.reverse(ctor_payload) ++ base_stack
        walk(arm_tokens, branch_stack, env, depth)

      _ ->
        ctors
        |> Enum.with_index()
        |> Enum.filter(fn {_ctor, idx} -> idx in possible end)
        |> Enum.reduce_while({:ok, nil}, fn {ctor, idx}, {:ok, acc_stack} ->
          ctor_payload = Map.get(payload_map, ctor, [])
          arm_tokens = Map.fetch!(arm_map, ctor)
          branch_stack = Enum.reverse(ctor_payload) ++ base_stack

          case walk(arm_tokens, branch_stack, env, depth) do
            {:ok, stack_out} ->
              cond do
                acc_stack == nil ->
                  {:cont, {:ok, stack_out}}

                true ->
                  cond_expr = {:eq, tag, {:const, idx}}

                  case merge_stacks(cond_expr, stack_out, acc_stack) do
                    {:ok, merged} -> {:cont, {:ok, merged}}
                    {:unsupported, _} = err -> {:halt, err}
                  end
              end

            {:unsupported, _} = err ->
              {:halt, err}
          end
        end)
        |> case do
          {:ok, nil} -> {:unsupported, "MATCH in PROVE has no constructor branches to merge"}
          {:ok, merged} -> {:ok, merged}
          {:unsupported, _} = err -> err
        end
    end
  end

  defp ctor_order(typedef) do
    typedef.variants |> Map.keys() |> Enum.sort()
  end

  defp ctor_index(ctors, ctor_name) do
    Enum.find_index(ctors, &(&1 == ctor_name)) || 0
  end

  defp build_user_type_symbolic_param(type_name, i, types) do
    with {:ok, typedef} <- fetch_typedef(type_name, types),
         :ok <- ensure_non_recursive_int_fields(typedef) do
      tag_var = "p#{i}_tag"
      tag_expr = {:var, tag_var}
      ctors = ctor_order(typedef)

      {payload_map, payload_vars} =
        Enum.reduce(ctors, {%{}, []}, fn ctor, {pm, vars} ->
          field_types = Map.get(typedef.variants, ctor, [])

          {vals, field_vars} =
            field_types
            |> Enum.with_index()
            |> Enum.reduce({[], []}, fn {_t, fi}, {acc_vals, acc_vars} ->
              vname = "p#{i}_#{ctor}_#{fi}"
              {[{:int_expr, {:var, vname}} | acc_vals], [vname | acc_vars]}
            end)

          {Map.put(pm, ctor, Enum.reverse(vals)), Enum.reverse(field_vars) ++ vars}
        end)

      domain =
        ctors
        |> Enum.with_index()
        |> Enum.map(fn {_ctor, idx} -> {:eq, tag_expr, {:const, idx}} end)
        |> join_constraints_or()

      {:ok, {:variant_expr, type_name, tag_expr, payload_map}, [tag_var | payload_vars], domain}
    else
      {:unsupported, _} = err -> err
    end
  end

  defp ensure_non_recursive_int_fields(typedef) do
    unsupported =
      typedef.variants
      |> Enum.flat_map(fn {_ctor, fields} -> fields end)
      |> Enum.find(fn t -> t != :int end)

    case unsupported do
      nil ->
        :ok

      _ ->
        {:unsupported,
         "type '#{typedef.name}' is not yet supported by generic PROVE MATCH (only non-recursive int fields)"}
    end
  end

  defp find_arm(arms, name) do
    case Enum.find(arms, fn {arm_name, _} -> arm_name == name end) do
      nil -> nil
      {_, tokens} -> tokens
    end
  end

  # --- Stack merging with ite ---

  defp merge_stacks(_cond, then_stack, else_stack)
       when length(then_stack) != length(else_stack) do
    {:unsupported, "IF/ELSE branches produce different stack depths — cannot merge"}
  end

  defp merge_stacks(cond, then_stack, else_stack) do
    merged =
      Enum.zip(then_stack, else_stack)
      |> Enum.map(fn
        {{:int_expr, t}, {:int_expr, e}} ->
          {:int_expr, {:ite, cond, t, e}}

        {{:bool_expr, t}, {:bool_expr, e}} ->
          {:bool_expr, {:ite_bool, cond, t, e}}

        {{:option_expr, ttag, tval}, {:option_expr, etag, eval}} ->
          {:option_expr, {:ite, cond, ttag, etag}, {:ite, cond, tval, eval}}

        {{:result_expr, ttag, tok, terr}, {:result_expr, etag, eok, eerr}} ->
          merged_err =
            if terr == eerr do
              terr
            else
              "__err_merged"
            end

          {:result_expr, {:ite, cond, ttag, etag}, {:ite, cond, tok, eok}, merged_err}

        {{:opaque_expr, topaque}, {:opaque_expr, eopaque}} ->
          {:opaque_expr, if(opaque_same?(topaque, eopaque), do: topaque, else: "__opaque_merged")}

        {{:variant_expr, tname, ttag, tpayloads}, {:variant_expr, ename, etag, epayloads}} ->
          if tname != ename do
            :unsupported
          else
            merged_payloads = merge_payload_maps(cond, tpayloads, epayloads)

            case merged_payloads do
              {:ok, payloads} ->
                {:variant_expr, tname, {:ite, cond, ttag, etag}, payloads}

              {:unsupported, _} ->
                :unsupported
            end
          end

        _ ->
          :unsupported
      end)

    if Enum.any?(merged, &(&1 == :unsupported)) do
      {:unsupported, "IF/ELSE branches produce incompatible types — cannot merge"}
    else
      {:ok, merged}
    end
  end

  defp join_constraints([]), do: true
  defp join_constraints([single]), do: single

  defp join_constraints([head | tail]) do
    Enum.reduce(tail, head, fn c, acc -> {:and, acc, c} end)
  end

  defp join_constraints_or([]), do: true
  defp join_constraints_or([single]), do: single

  defp join_constraints_or([head | tail]) do
    Enum.reduce(tail, head, fn c, acc -> {:or, acc, c} end)
  end

  defp merge_payload_maps(cond, p1, p2) do
    keys = Map.keys(p1) |> Enum.sort()

    merged =
      Enum.reduce_while(keys, %{}, fn key, acc ->
        v1 = Map.get(p1, key, [])
        v2 = Map.get(p2, key, [])

        case merge_payload_lists(cond, v1, v2) do
          {:ok, vals} -> {:cont, Map.put(acc, key, vals)}
          {:unsupported, _} = err -> {:halt, err}
        end
      end)

    case merged do
      %{} = map -> {:ok, map}
      {:unsupported, _} = err -> err
    end
  end

  defp merge_payload_lists(_cond, l1, l2) when length(l1) != length(l2),
    do: {:unsupported, "payload arity mismatch"}

  defp merge_payload_lists(cond, l1, l2) do
    l1
    |> Enum.zip(l2)
    |> Enum.reduce_while({:ok, []}, fn {a, b}, {:ok, acc} ->
      case merge_symvals(cond, a, b) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        {:unsupported, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, vals} -> {:ok, Enum.reverse(vals)}
      {:unsupported, _} = err -> err
    end
  end

  defp merge_symvals(cond, {:int_expr, a}, {:int_expr, b}), do: {:ok, {:int_expr, {:ite, cond, a, b}}}
  defp merge_symvals(cond, {:bool_expr, a}, {:bool_expr, b}), do: {:ok, {:bool_expr, {:ite_bool, cond, a, b}}}

  defp merge_symvals(_cond, {:opaque_expr, a}, {:opaque_expr, b}) do
    {:ok, {:opaque_expr, if(opaque_same?(a, b), do: a, else: "__opaque_merged")}}
  end

  defp merge_symvals(_cond, _, _), do: {:unsupported, "incompatible payload symvals"}

  defp possible_tag_indexes({:const, value}, arity, _env) when is_integer(value) do
    if value >= 0 and value < arity, do: [value], else: Enum.to_list(0..(arity - 1))
  end

  defp possible_tag_indexes({:var, var_name}, arity, env) do
    assumption = get_tag_assumption(var_name, env)

    candidates =
      Enum.to_list(0..(arity - 1))
      |> Enum.filter(fn idx -> tag_candidate_allowed?(idx, assumption) end)

    if candidates == [], do: Enum.to_list(0..(arity - 1)), else: candidates
  end

  defp possible_tag_indexes(_tag_expr, arity, _env), do: Enum.to_list(0..(arity - 1))

  defp get_tag_assumption(var_name, env) do
    assumptions = Map.get(env, "__prove_tag_assumptions__", %{})

    case Map.get(assumptions, var_name) do
      value when is_integer(value) ->
        %{eq: value, neq: MapSet.new(), min: nil, min_inclusive: true, max: nil, max_inclusive: true, source: MapSet.new()}

      %{eq: eq, neq: neq, min: min, min_inclusive: min_inc, max: max, max_inclusive: max_inc, source: source} ->
        %{eq: eq, neq: neq, min: min, min_inclusive: min_inc, max: max, max_inclusive: max_inc, source: source}

      %{eq: eq, neq: neq, min: min, min_inclusive: min_inc, max: max, max_inclusive: max_inc} ->
        %{eq: eq, neq: neq, min: min, min_inclusive: min_inc, max: max, max_inclusive: max_inc, source: MapSet.new()}

      %{eq: eq, neq: neq} ->
        %{eq: eq, neq: neq, min: nil, min_inclusive: true, max: nil, max_inclusive: true, source: MapSet.new()}

      _ ->
        %{eq: nil, neq: MapSet.new(), min: nil, min_inclusive: true, max: nil, max_inclusive: true, source: MapSet.new()}
    end
  end

  defp reason_for_tag_prune({:const, _}, _env), do: "const"

  defp reason_for_tag_prune({:var, var_name}, env) do
    assumption = get_tag_assumption(var_name, env)

    cond do
      is_integer(assumption.eq) ->
        "eq"

      assumption.min != nil or assumption.max != nil ->
        "bounds"

      MapSet.size(assumption.neq) > 0 ->
        "neq"

      true ->
        "unknown"
    end
  end

  defp reason_for_tag_prune(_, _), do: "unknown"

  defp option_candidate_names(candidates) do
    candidates
    |> Enum.map(fn
      0 -> "None"
      1 -> "Some"
      n -> "tag#{n}"
    end)
  end

  defp result_candidate_names(candidates) do
    candidates
    |> Enum.map(fn
      0 -> "Err"
      1 -> "Ok"
      n -> "tag#{n}"
    end)
  end

  defp match_trace_details(type_name, tag, env, pos, candidates) do
    phase = Map.get(env, "__prove_phase__", "body")
    func = Map.get(env, "__prove_func_name__", "<anon>")
    assumption = assumption_snapshot(tag, env)

    %{
      candidates: candidates,
      tag: inspect(tag),
      phase: phase,
      match_pos: pos,
      match_site_id: "#{func}:#{phase}:#{pos}",
      assumptions: assumption,
      match_type: type_name,
      pre_raw: Map.get(env, "__prove_pre_raw__", nil),
      pre_normalized: Map.get(env, "__prove_pre_normalized__", nil),
      pre_rewrite_summary: Map.get(env, "__prove_pre_rewrite_summary__", %{})
    }
  end

  defp assumption_snapshot({:var, var_name}, env) do
    a = get_tag_assumption(var_name, env)
    %{eq: a.eq, neq: Enum.sort(MapSet.to_list(a.neq)), min: a.min, min_inclusive: a.min_inclusive, max: a.max, max_inclusive: a.max_inclusive, source: Enum.sort(MapSet.to_list(a.source))}
  end

  defp assumption_snapshot(_tag, _env), do: %{eq: nil, neq: [], min: nil, min_inclusive: true, max: nil, max_inclusive: true, source: []}

  defp trace_match_decision(env, type_name, explored, pruned, reason, details) do
    if Map.get(env, "__prove_trace_enabled__", false) do
      event = %{
        event: "match_decision",
        type: to_string(type_name),
        explored: to_string(explored),
        pruned: Enum.map(pruned, &to_string/1),
        reason: to_string(reason),
        candidates: Map.get(details, :candidates, []) |> Enum.map(&to_string/1),
        tag: to_string(Map.get(details, :tag, "?")),
        phase: to_string(Map.get(details, :phase, "body")),
        match_pos: Map.get(details, :match_pos, -1),
        match_site_id: to_string(Map.get(details, :match_site_id, "?")),
        assumptions: Map.get(details, :assumptions, %{eq: nil, neq: []}),
        inference_source: Map.get(details, :assumptions, %{}) |> Map.get(:source, []),
        pre_raw: Map.get(details, :pre_raw, nil),
        pre_normalized: Map.get(details, :pre_normalized, nil),
        pre_rewrite_summary: Map.get(details, :pre_rewrite_summary, %{})
      }

      append_trace_event(event)
    end
  end

  defp tag_candidate_allowed?(idx, assumption) do
    eq_ok =
      case assumption.eq do
        nil -> true
        value -> idx == value
      end

    neq_ok = not MapSet.member?(assumption.neq, idx)

    min_ok =
      case assumption.min do
        nil -> true
        value when assumption.min_inclusive -> idx >= value
        value -> idx > value
      end

    max_ok =
      case assumption.max do
        nil -> true
        value when assumption.max_inclusive -> idx <= value
        value -> idx < value
      end

    eq_ok and neq_ok and min_ok and max_ok
  end

  defp append_trace_event(event) do
    events = Process.get(:axiom_prove_trace_events, [])
    Process.put(:axiom_prove_trace_events, [event | events])
  end

  defp opaque_same?(a, b), do: a == b
end
