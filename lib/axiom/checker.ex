defmodule Axiom.Checker do
  @moduledoc """
  Static type checker for Axiom.

  Walks parsed items (function definitions and expression token streams)
  with a symbolic stack, catching type errors before evaluation.
  """

  alias Axiom.Checker.{Error, Stack, Effects, Unify}

  @doc """
  Checks a list of parsed items for static type errors.

  Returns `:ok` if no errors are found, or `{:error, errors}` with a list
  of `Axiom.Checker.Error` structs.

  The `env` parameter provides previously-defined function signatures
  for cross-expression checking (e.g., in the REPL).
  """
  @spec check([Axiom.Types.Function.t() | {:expr, [Axiom.Types.token()]}], map()) ::
          :ok | {:error, [Error.t()]}
  def check(items, env \\ %{}) do
    {type_env, types} = build_checker_env(env)
    actor_required = compute_actor_required_functions(items, type_env)

    # Pre-register all type definitions and function signatures upfront so that
    # mutually recursive functions can see each other regardless of source order.
    {type_env, types} =
      Enum.reduce(items, {type_env, types}, fn
        %Axiom.Types.TypeDef{} = typedef, {te, tys} ->
          te =
            Enum.reduce(typedef.variants, te, fn {ctor_name, field_types}, acc ->
              Map.put(acc, ctor_name, %{
                param_types: field_types,
                return_types: [{:user_type, typedef.name}]
              })
            end)

          {te, Map.put(tys, typedef.name, typedef)}

        %Axiom.Types.Function{} = func, {te, tys} ->
          {Map.put(te, func.name, %{
             param_types: func.param_types,
             return_types: func.return_types,
             actor_required: MapSet.member?(actor_required, func.name)
           }),
           tys}

        _, acc ->
          acc
      end)

    state = %{
      stack: Stack.new(),
      env: type_env,
      errors: [],
      next_tvar: 0,
      types: types,
      current_actor_type: nil,
      actor_required: actor_required
    }

    state = Enum.reduce(items, state, &check_item/2)

    case state.errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  # Build type environment and type map from runtime env
  defp build_checker_env(env) do
    {type_env, types} = prelude_checker_env()

    # Convert Function entries to checker signatures
    type_env =
      env
      |> Enum.filter(fn {_, v} -> match?(%Axiom.Types.Function{}, v) end)
      |> Enum.reduce(type_env, fn {name, func}, acc ->
        {name, %{param_types: func.param_types, return_types: func.return_types}}
        |> then(fn {k, v} -> Map.put(acc, k, v) end)
      end)

    # Register constructors from runtime "__constructors__" map
    ctors = Map.get(env, "__constructors__", %{})

    type_env =
      Enum.reduce(ctors, type_env, fn {ctor_name, {type_name, field_types}}, acc ->
        Map.put(acc, ctor_name, %{
          param_types: field_types,
          return_types: [{:user_type, type_name}]
        })
      end)

    env_types = Map.get(env, "__types__", %{})
    types = Map.merge(types, env_types)
    {type_env, types}
  end

  defp prelude_checker_env do
    type_env = %{
      "Ok" => %{param_types: [:any], return_types: [{:user_type, "result"}]},
      "Err" => %{param_types: [:str], return_types: [{:user_type, "result"}]}
    }

    types = %{
      "result" => %Axiom.Types.TypeDef{
        name: "result",
        variants: %{"Ok" => [:any], "Err" => [:str]}
      }
    }

    {type_env, types}
  end

  defp check_item(%Axiom.Types.Function{} = func, state) do
    # Register function in type env
    state = put_in(state.env[func.name], %{
      param_types: func.param_types,
      return_types: func.return_types,
      actor_required: MapSet.member?(state.actor_required, func.name)
    })

    # Check function body: start with param types on stack
    # param_types[0] is on top (matches runtime's Enum.split behavior)
    body_stack =
      func.param_types
      |> Enum.reverse()
      |> Enum.reduce(Stack.new(), fn type, stack -> Stack.push(stack, type) end)

    body_actor_type = if MapSet.member?(state.actor_required, func.name), do: :any, else: nil
    body_state = %{state | stack: body_stack, current_actor_type: body_actor_type}
    body_state = check_tokens(func.body, body_state)

    # Check return types
    body_state = check_return_shape(func, body_state)

    # Check PRE condition if present
    body_state =
      if func.pre_condition do
        pre_stack =
          func.param_types
          |> Enum.reverse()
          |> Enum.reduce(Stack.new(), fn type, stack -> Stack.push(stack, type) end)

        pre_state = %{body_state | stack: pre_stack, current_actor_type: body_actor_type}
        pre_state = check_tokens(func.pre_condition, pre_state)
        %{pre_state | stack: body_state.stack}
      else
        body_state
      end

    # Check POST condition if present
    body_state =
      if func.post_condition do
        post_stack =
          if func.return_types == [:void] do
            Stack.new()
          else
            func.return_types
            |> Enum.reverse()
            |> Enum.reduce(Stack.new(), fn type, stack -> Stack.push(stack, type) end)
          end

        post_state = %{body_state | stack: post_stack, current_actor_type: body_actor_type}
        post_state = check_tokens(func.post_condition, post_state)
        %{post_state | stack: body_state.stack}
      else
        body_state
      end

    # Restore stack for next item (function defs don't affect expression stack)
    %{body_state | stack: state.stack, current_actor_type: state.current_actor_type}
  end

  defp check_item(%Axiom.Types.TypeDef{} = typedef, state) do
    # Register each constructor as a pseudo-function in the checker env
    state =
      Enum.reduce(typedef.variants, state, fn {ctor_name, field_types}, st ->
        put_in(st.env[ctor_name], %{
          param_types: field_types,
          return_types: [{:user_type, typedef.name}]
        })
      end)

    # Register the type definition for MATCH exhaustiveness checking
    %{state | types: Map.put(state.types, typedef.name, typedef)}
  end

  defp check_item({:expr, tokens}, state) do
    check_tokens(tokens, state)
  end

  # VERIFY items are runtime-only, skip in static checker
  defp check_item({:verify, _name, _count}, state), do: state

  # PROVE items are runtime-only, skip in static checker
  defp check_item({:prove, _name}, state), do: state

  # IMPORT items are resolved before checking in file mode
  defp check_item({:import, _path}, state), do: state

  # Check return shape of a function body
  defp check_return_shape(%{return_types: [:void]} = func, state) do
    depth = Stack.depth(state.stack)

    if depth != 0 do
      add_error(state, nil,
        "function '#{func.name}' declared -> void but body leaves #{depth} value(s) on stack")
    else
      state
    end
  end

  defp check_return_shape(func, state) do
    expected = length(func.return_types)
    actual = Stack.depth(state.stack)

    cond do
      actual != expected ->
        add_error(state, nil,
          "function '#{func.name}' declared #{expected} return value(s) but body produces #{actual}")

      true ->
        # Check types match
        {types, _} = Stack.pop_n(state.stack, expected)

        types
        |> Enum.zip(func.return_types)
        |> Enum.reduce(state, fn {actual_type, expected_type}, st ->
          case Unify.unify(actual_type, expected_type) do
            {:ok, _} -> st
            :error ->
              add_error(st, nil,
                "function '#{func.name}' return type mismatch: expected #{format_type(expected_type)}, got #{format_type(actual_type)}")
          end
        end)
    end
  end

  # --- Token walking ---

  defp check_tokens(tokens, state) do
    walk(tokens, state)
  end

  defp walk([], state), do: state

  # Literals
  defp walk([{:int_lit, _, _} | rest], state) do
    walk(rest, %{state | stack: Stack.push(state.stack, :int)})
  end

  defp walk([{:float_lit, _, _} | rest], state) do
    walk(rest, %{state | stack: Stack.push(state.stack, :float)})
  end

  defp walk([{:bool_lit, _, _} | rest], state) do
    walk(rest, %{state | stack: Stack.push(state.stack, :bool)})
  end

  # FMT with literal format string — count {} placeholders and pop that many values
  defp walk([{:str_lit, text, _}, {:op, :fmt, pos} | rest], state) do
    # Count {} placeholders (excluding {{ and }})
    n = count_fmt_placeholders(text)

    # Pop n values of :any type for the placeholders
    case Stack.pop_n(state.stack, n) do
      {_types, base} ->
        walk(rest, %{state | stack: Stack.push(base, :str)})

      :underflow ->
        walk(rest, add_error(state, pos,
          "FMT format string has #{n} placeholder(s) but not enough values on the stack"))
    end
  end

  defp walk([{:str_lit, _, _} | rest], state) do
    walk(rest, %{state | stack: Stack.push(state.stack, :str)})
  end

  defp walk([{:list_lit, _, _} | rest], state) do
    # Empty list literal []
    {tvar, state} = fresh_tvar(state)
    walk(rest, %{state | stack: Stack.push(state.stack, {:list, tvar})})
  end

  # Empty map literal M[]
  defp walk([{:map_lit, _, _} | rest], state) do
    {k_tvar, state} = fresh_tvar(state)
    {v_tvar, state} = fresh_tvar(state)
    walk(rest, %{state | stack: Stack.push(state.stack, {:map, k_tvar, v_tvar})})
  end

  # Map construction: M[ ... ]
  defp walk([{:map_open, _, _} | rest], state) do
    {elem_tokens, remaining} = collect_map_elements(rest, [], 0)
    {key_type, val_type, state} = infer_map_types(elem_tokens, state)
    walk(remaining, %{state | stack: Stack.push(state.stack, {:map, key_type, val_type})})
  end

  # List construction: [ ... ]
  defp walk([{:list_open, _, _} | rest], state) do
    {elem_tokens, remaining} = collect_list_elements(rest, [], 0)
    {elem_type, state} = infer_list_element_type(elem_tokens, state)
    walk(remaining, %{state | stack: Stack.push(state.stack, {:list, elem_type})})
  end

  # LET — pop top type, bind name in env for subsequent type checking
  defp walk([{:let_kw, _, pos}, {:ident, name, _} | rest], state) do
    case Stack.pop(state.stack) do
      {:ok, type, new_stack} ->
        state = %{state | stack: new_stack}
        state = put_in(state.env[name], %{param_types: [], return_types: [type], let_binding: true})
        walk(rest, state)

      :underflow ->
        walk(rest, add_error(state, pos, "LET requires a value on the stack (stack underflow)"))
    end
  end

  # Block literals: { ... }
  defp walk([{:block_open, _, _} | rest], state) do
    {block_tokens, remaining} = collect_block_tokens(rest, 0, [])
    walk(remaining, %{state | stack: Stack.push(state.stack, {:block, block_tokens})})
  end

  # SPAWN MessageType { ... } — static-only for now
  defp walk([{:spawn_kw, _, pos}, type_token, {:block_open, _, _} | rest], state) do
    case resolve_concurrency_type(type_token, state.types) do
      {:ok, msg_type} ->
        {block_tokens, remaining} = collect_block_tokens(rest, 0, [])
        block_stack = Stack.new() |> Stack.push({:pid, msg_type})
        block_state = walk(block_tokens, %{state | stack: block_stack, current_actor_type: msg_type})

        state = %{
          state
          | errors: merge_error_lists(state.errors, block_state.errors),
            next_tvar: block_state.next_tvar
        }

        state =
          if Stack.depth(block_state.stack) == 0 do
            state
          else
            add_error(state, pos, "SPAWN block must consume its self pid and leave an empty stack")
          end

        walk(remaining, %{state | stack: Stack.push(state.stack, {:pid, msg_type})})

      {:error, msg} ->
        state = add_error(state, pos, msg)
        {_block_tokens, remaining} = collect_block_tokens(rest, 0, [])
        walk(remaining, state)
    end
  end

  defp walk([{:spawn_kw, _, pos} | rest], state) do
    walk(rest, add_error(state, pos, "SPAWN requires a message type and block: SPAWN msg { ... }"))
  end

  # IF/ELSE/END
  defp walk([{:if_kw, _, pos} | rest], state) do
    case Stack.pop(state.stack) do
      {:ok, cond_type, stack_after_pop} ->
        state = %{state | stack: stack_after_pop}

        state =
          case Unify.unify(cond_type, :bool) do
            {:ok, _} -> state
            :error -> add_error(state, pos, "IF condition must be bool, got #{format_type(cond_type)}")
          end

        {then_tokens, else_tokens, remaining} = split_if_branches(rest)

        then_state = walk(then_tokens, state)

        case else_tokens do
          nil ->
            # IF without ELSE: stack must not change depth
            then_depth = Stack.depth(then_state.stack)
            pre_depth = Stack.depth(state.stack)

            state =
              if then_depth != pre_depth do
                add_error(state, pos,
                  "IF-without-ELSE changes stack depth (before: #{pre_depth}, after: #{then_depth})")
              else
                state
              end

            # Use best-effort: merge errors, use original stack shape
            # (since we don't know which branch runs, must be neutral)
            walk(remaining, %{state | errors: then_state.errors})

          else_toks ->
            else_state = walk(else_toks, state)

            then_depth = Stack.depth(then_state.stack)
            else_depth = Stack.depth(else_state.stack)

            merged_errors = merge_error_lists(then_state.errors, else_state.errors)

            if then_depth != else_depth do
              state = %{state | errors: merged_errors}

              state =
                add_error(state, pos,
                  "IF/ELSE branches have different stack depths (then: #{then_depth}, else: #{else_depth})")

              walk(remaining, state)
            else
              # Unify branch result types
              {then_types, _} = Stack.pop_n(then_state.stack, then_depth)
              {else_types, _} = Stack.pop_n(else_state.stack, else_depth)

              {result_stack, state} =
                Enum.zip(then_types, else_types)
                |> Enum.reduce({Stack.new(), %{state | errors: merged_errors}}, fn
                  {t1, t2}, {stack, st} ->
                    case Unify.unify(t1, t2) do
                      {:ok, unified} ->
                        {Stack.push(stack, unified), st}

                      :error ->
                        # Use :any as fallback
                        st = add_error(st, pos,
                          "IF/ELSE branch type mismatch: #{format_type(t1)} vs #{format_type(t2)}")
                        {Stack.push(stack, :any), st}
                    end
                end)

              # Reverse since we built it backwards
              result_stack = Stack.reverse(result_stack)
              walk(remaining, %{state | stack: result_stack})
            end
        end

      :underflow ->
        state = add_error(state, pos, "IF requires a bool on the stack (stack underflow)")
        # Skip past the END to keep going
        {_then, _else, remaining} = split_if_branches(rest)
        walk(remaining, state)
    end
  end

  # Stack manipulation ops - special-cased
  defp walk([{:op, :dup, pos} | rest], state) do
    case Stack.pop(state.stack) do
      {:ok, t, _} ->
        walk(rest, %{state | stack: state.stack |> Stack.push(t)})

      :underflow ->
        walk(rest, add_error(state, pos, "DUP requires 1 value on the stack (stack underflow)"))
    end
  end

  defp walk([{:op, :drop, pos} | rest], state) do
    case Stack.pop(state.stack) do
      {:ok, _, new_stack} ->
        walk(rest, %{state | stack: new_stack})

      :underflow ->
        walk(rest, add_error(state, pos, "DROP requires 1 value on the stack (stack underflow)"))
    end
  end

  defp walk([{:op, :swap, pos} | rest], state) do
    case Stack.pop_n(state.stack, 2) do
      {[a, b], base} ->
        walk(rest, %{state | stack: base |> Stack.push(a) |> Stack.push(b)})

      :underflow ->
        walk(rest, add_error(state, pos, "SWAP requires 2 values on the stack (stack underflow)"))
    end
  end

  defp walk([{:op, :over, pos} | rest], state) do
    case Stack.pop_n(state.stack, 2) do
      {[_a, b], _base} ->
        walk(rest, %{state | stack: state.stack |> Stack.push(b)})

      :underflow ->
        walk(rest, add_error(state, pos, "OVER requires 2 values on the stack (stack underflow)"))
    end
  end

  defp walk([{:op, :rot, pos} | rest], state) do
    case Stack.pop_n(state.stack, 3) do
      {[a, b, c], base} ->
        # ROT: [a, b, c | rest] -> [c, a, b | rest]
        walk(rest, %{state | stack: base |> Stack.push(b) |> Stack.push(a) |> Stack.push(c)})

      :underflow ->
        walk(rest, add_error(state, pos, "ROT requires 3 values on the stack (stack underflow)"))
    end
  end

  defp walk([{:op, :rot4, pos} | rest], state) do
    case Stack.pop_n(state.stack, 4) do
      {[a, b, c, d], base} ->
        # ROT4: [a, b, c, d | rest] -> [d, a, b, c | rest]
        walk(rest, %{state | stack: base |> Stack.push(c) |> Stack.push(b) |> Stack.push(a) |> Stack.push(d)})

      :underflow ->
        walk(rest, add_error(state, pos, "ROT4 requires 4 values on the stack (stack underflow)"))
    end
  end

  # APPLY - execute a block inline
  defp walk([{:op, :apply, pos} | rest], state) do
    case Stack.pop(state.stack) do
      {:ok, {:block, block_tokens}, new_stack} ->
        block_state = %{state | stack: new_stack}
        block_state = walk(block_tokens, block_state)
        walk(rest, block_state)

      {:ok, other, _} ->
        walk(rest, add_error(state, pos, "APPLY requires a block, got #{format_type(other)}"))

      :underflow ->
        walk(rest, add_error(state, pos, "APPLY requires a block on the stack (stack underflow)"))
    end
  end

  # Higher-order ops: FILTER, MAP, REDUCE, TIMES, WHILE
  defp walk([{:op, :filter, pos} | rest], state) do
    check_filter(pos, rest, state)
  end

  defp walk([{:op, :map, pos} | rest], state) do
    check_map(pos, rest, state)
  end

  defp walk([{:op, :reduce, pos} | rest], state) do
    check_reduce(pos, rest, state)
  end

  defp walk([{:op, :times, pos} | rest], state) do
    check_times(pos, rest, state)
  end

  defp walk([{:op, :while, pos} | rest], state) do
    check_while(pos, rest, state)
  end

  # FMT with dynamic (non-literal) format string — just pop :str, push :str
  defp walk([{:op, :fmt, pos} | rest], state) do
    case Stack.pop(state.stack) do
      {:ok, :str, stack_after_pop} ->
        walk(rest, %{state | stack: Stack.push(stack_after_pop, :str)})

      {:ok, other, _} ->
        walk(rest, add_error(state, pos,
          "FMT requires a str format string on top, got #{format_type(other)}"))

      :underflow ->
        walk(rest, add_error(state, pos,
          "FMT requires a format string on the stack (stack underflow)"))
    end
  end

  # SELF — available only while checking a SPAWN block.
  defp walk([{:op, :self, pos} | rest], %{current_actor_type: nil} = state) do
    walk(rest, add_error(state, pos, "SELF is only available inside a SPAWN block"))
  end

  defp walk([{:op, :self, _pos} | rest], %{current_actor_type: msg_type} = state) do
    walk(rest, %{state | stack: Stack.push(state.stack, {:pid, msg_type})})
  end

  # SEND — pid[msg] msg SEND
  defp walk([{:op, :send, pos} | rest], state) do
    case Stack.pop_n(state.stack, 2) do
      {[msg_type, {:pid, expected_msg_type}], base} ->
        state =
          case Unify.unify(msg_type, expected_msg_type) do
            {:ok, _} -> %{state | stack: base}
            :error ->
              add_error(%{state | stack: base}, pos,
                "SEND expected #{format_type(expected_msg_type)}, got #{format_type(msg_type)}")
          end

        walk(rest, state)

      {[msg_type, other], _base} ->
        walk(rest, add_error(state, pos,
          "SEND requires pid[msg] beneath the message, got #{format_type(other)} under #{format_type(msg_type)}"))

      :underflow ->
        walk(rest, add_error(state, pos, "SEND requires a pid and message on the stack (stack underflow)"))
    end
  end

  # General operators - lookup effect
  defp walk([{:op, op, pos} | rest], state) do
    case Effects.lookup(op) do
      {:ok, effect} ->
        state = apply_effect(op, effect, pos, state)
        walk(rest, state)

      :unknown ->
        walk(rest, add_error(state, pos, "unknown operator #{op}"))
    end
  end

  # Function calls and LET bindings (identifiers)
  defp walk([{:ident, name, pos} | rest], state) do
    case Map.get(state.env, name) do
      nil ->
        walk(rest, add_error(state, pos, "undefined function '#{name}'"))

      # LET binding — just push the bound type
      %{let_binding: true, return_types: [type]} ->
        walk(rest, %{state | stack: Stack.push(state.stack, type)})

      %{param_types: param_types, return_types: return_types} = entry ->
        state =
          if Map.get(entry, :actor_required, false) and is_nil(state.current_actor_type) do
            add_error(state, pos, "function '#{name}' requires actor context")
          else
            state
          end

        arity = length(param_types)

        case Stack.pop_n(state.stack, arity) do
          {arg_types, base} ->
            # Check arg types match
            state =
              arg_types
              |> Enum.zip(param_types)
              |> Enum.reduce(%{state | stack: base}, fn {actual, expected}, st ->
                case Unify.unify(actual, expected) do
                  {:ok, _} -> st
                  :error ->
                    add_error(st, pos,
                      "function '#{name}' expected #{format_type(expected)}, got #{format_type(actual)}")
                end
              end)

            # Push return types — reverse so return_types[0] lands on top
            state =
              if return_types == [:void] do
                state
              else
                Enum.reduce(Enum.reverse(return_types), state, fn type, st ->
                  %{st | stack: Stack.push(st.stack, type)}
                end)
              end

            walk(rest, state)

          :underflow ->
            # Push return types as best-effort recovery
            state = add_error(state, pos,
              "function '#{name}' requires #{arity} argument(s) (stack underflow)")

            state =
              if return_types == [:void] do
                state
              else
                Enum.reduce(Enum.reverse(return_types), state, fn type, st ->
                  %{st | stack: Stack.push(st.stack, type)}
                end)
              end

            walk(rest, state)
        end
    end
  end

  # Constructor tokens — behave like function calls
  defp walk([{:constructor, name, pos} | rest], state) do
    case Map.get(state.env, name) do
      nil ->
        walk(rest, add_error(state, pos, "unknown constructor '#{name}'"))

      %{param_types: param_types, return_types: return_types} ->
        arity = length(param_types)

        case Stack.pop_n(state.stack, arity) do
          {arg_types, base} ->
            state =
              arg_types
              |> Enum.zip(param_types)
              |> Enum.reduce(%{state | stack: base}, fn {actual, expected}, st ->
                case Unify.unify(actual, expected) do
                  {:ok, _} -> st
                  :error ->
                    add_error(st, pos,
                      "constructor '#{name}' expected #{format_type(expected)}, got #{format_type(actual)}")
                end
              end)

            state =
              Enum.reduce(Enum.reverse(return_types), state, fn type, st ->
                %{st | stack: Stack.push(st.stack, type)}
              end)

            walk(rest, state)

          :underflow ->
            state =
              add_error(state, pos,
                "constructor '#{name}' requires #{arity} argument(s) (stack underflow)")

            state =
              Enum.reduce(Enum.reverse(return_types), state, fn type, st ->
                %{st | stack: Stack.push(st.stack, type)}
              end)

            walk(rest, state)
        end
    end
  end

  # MATCH/END — pattern dispatch on a variant value
  defp walk([{:match_kw, _, pos} | rest], state) do
    {arms, remaining} = collect_checker_match_arms(rest, [])

    case Stack.pop(state.stack) do
      {:ok, {:user_type, type_name}, base_stack} ->
        state = %{state | stack: base_stack}
        typedef = Map.get(state.types, type_name)
        has_wildcard = Enum.any?(arms, fn {name, _} -> name == :wildcard end)

        # Exhaustiveness check — skip if wildcard catch-all is present
        state =
          if typedef && !has_wildcard do
            arm_names = MapSet.new(arms, fn {name, _} -> name end)
            all_ctors = MapSet.new(Map.keys(typedef.variants))
            missing = MapSet.difference(all_ctors, arm_names)

            if MapSet.size(missing) > 0 do
              add_error(state, pos,
                "MATCH on '#{type_name}' is not exhaustive: missing #{Enum.join(Enum.sort(MapSet.to_list(missing)), ", ")}")
            else
              state
            end
          else
            state
          end

        # Walk each arm
        arm_states =
          Enum.map(arms, fn
            {:wildcard, arm_tokens} ->
              # Wildcard arm: no fields pushed — body starts with base stack
              walk(arm_tokens, %{state | stack: base_stack})

            {ctor_name, arm_tokens} ->
              field_types =
                if typedef, do: Map.get(typedef.variants, ctor_name, []), else: []

              arm_stack =
                field_types
                |> Enum.reverse()
                |> Enum.reduce(base_stack, fn t, s -> Stack.push(s, t) end)

              walk(arm_tokens, %{state | stack: arm_stack})
          end)

        {result_stack, state} = unify_arm_stacks(arm_states, state, pos)
        walk(remaining, %{state | stack: result_stack})

      {:ok, other, _} ->
        state =
          add_error(state, pos,
            "MATCH requires a variant on the stack, got #{format_type(other)}")

        walk(remaining, state)

      :underflow ->
        state = add_error(state, pos, "MATCH requires a value on the stack (stack underflow)")
        walk(remaining, state)
    end
  end

  # RECEIVE/END — pattern dispatch on the message type carried by pid[msg]
  defp walk([{:receive_kw, _, pos} | rest], state) do
    {arms, remaining} = collect_checker_match_arms(rest, [])

    case state.current_actor_type do
      {:user_type, type_name} ->
        {result_stack, state} = check_receive_arms(type_name, state.stack, arms, state, pos)
        walk(remaining, %{state | stack: result_stack})

      _ ->
        check_receive_with_explicit_pid(arms, remaining, state, pos)
    end
  end

  # Catch-all for unhandled token types during checking
  defp walk([_token | rest], state) do
    walk(rest, state)
  end

  # --- Higher-order operation checking ---

  defp check_filter(pos, rest, state) do
    # Two orders: {block} list FILTER or list {block} FILTER
    case Stack.pop_n(state.stack, 2) do
      {[{:block, block_tokens}, {:list, elem_type}], base} ->
        # Check block: receives elem_type, must return bool
        block_stack = Stack.new() |> Stack.push(elem_type)
        block_state = %{state | stack: block_stack}
        block_state = walk(block_tokens, block_state)

        state = %{state | stack: base |> Stack.push({:list, elem_type}), errors: block_state.errors}
        walk(rest, state)

      {[{:list, elem_type}, {:block, block_tokens}], base} ->
        block_stack = Stack.new() |> Stack.push(elem_type)
        block_state = %{state | stack: block_stack}
        block_state = walk(block_tokens, block_state)

        state = %{state | stack: base |> Stack.push({:list, elem_type}), errors: block_state.errors}
        walk(rest, state)

      {_, _} ->
        walk(rest, add_error(state, pos, "FILTER requires a list and a block"))

      :underflow ->
        walk(rest, add_error(state, pos, "FILTER requires 2 values on the stack (stack underflow)"))
    end
  end

  defp check_map(pos, rest, state) do
    case Stack.pop_n(state.stack, 2) do
      {[{:block, block_tokens}, {:list, elem_type}], base} ->
        block_stack = Stack.new() |> Stack.push(elem_type)
        block_state = %{state | stack: block_stack}
        block_state = walk(block_tokens, block_state)

        result_type =
          case Stack.pop(block_state.stack) do
            {:ok, t, _} -> t
            :underflow -> :any
          end

        state = %{state | stack: base |> Stack.push({:list, result_type}), errors: block_state.errors}
        walk(rest, state)

      {[{:list, elem_type}, {:block, block_tokens}], base} ->
        block_stack = Stack.new() |> Stack.push(elem_type)
        block_state = %{state | stack: block_stack}
        block_state = walk(block_tokens, block_state)

        result_type =
          case Stack.pop(block_state.stack) do
            {:ok, t, _} -> t
            :underflow -> :any
          end

        state = %{state | stack: base |> Stack.push({:list, result_type}), errors: block_state.errors}
        walk(rest, state)

      {_, _} ->
        walk(rest, add_error(state, pos, "MAP requires a list and a block"))

      :underflow ->
        walk(rest, add_error(state, pos, "MAP requires 2 values on the stack (stack underflow)"))
    end
  end

  defp check_reduce(pos, rest, state) do
    # Three args: list init block REDUCE or block init list REDUCE
    case Stack.pop_n(state.stack, 3) do
      {[{:block, block_tokens}, init_type, {:list, elem_type}], base} ->
        # Block gets [elem, acc] on stack, must return acc type
        block_stack = Stack.new() |> Stack.push(init_type) |> Stack.push(elem_type)
        block_state = %{state | stack: block_stack}
        block_state = walk(block_tokens, block_state)

        result_type =
          case Stack.pop(block_state.stack) do
            {:ok, t, _} -> t
            :underflow -> init_type
          end

        state = %{state | stack: base |> Stack.push(result_type), errors: block_state.errors}
        walk(rest, state)

      {[{:list, _elem_type}, {:block, block_tokens}, init_type], base} ->
        # Alternate order
        block_state = %{state | stack: Stack.new() |> Stack.push(init_type) |> Stack.push(:any)}
        block_state = walk(block_tokens, block_state)

        result_type =
          case Stack.pop(block_state.stack) do
            {:ok, t, _} -> t
            :underflow -> init_type
          end

        state = %{state | stack: base |> Stack.push(result_type), errors: block_state.errors}
        walk(rest, state)

      {_, _} ->
        state = add_error(state, pos, "REDUCE requires a list, initial value, and block")
        walk(rest, %{state | stack: state.stack |> Stack.push(:any)})

      :underflow ->
        state = add_error(state, pos, "REDUCE requires 3 values on the stack (stack underflow)")
        walk(rest, %{state | stack: state.stack |> Stack.push(:any)})
    end
  end

  defp check_times(pos, rest, state) do
    # N {block} TIMES or {block} N TIMES
    case Stack.pop_n(state.stack, 2) do
      {[{:block, _block_tokens}, :int], base} ->
        # TIMES: block runs N times, stack-preserving
        walk(rest, %{state | stack: base})

      {[:int, {:block, _block_tokens}], base} ->
        walk(rest, %{state | stack: base})

      {[{:block, _}, t], _base} ->
        walk(rest, add_error(state, pos, "TIMES requires an int count, got #{format_type(t)}"))

      {[t, {:block, _}], _base} ->
        walk(rest, add_error(state, pos, "TIMES requires an int count, got #{format_type(t)}"))

      {_, _} ->
        walk(rest, add_error(state, pos, "TIMES requires an int and a block"))

      :underflow ->
        walk(rest, add_error(state, pos, "TIMES requires 2 values on the stack (stack underflow)"))
    end
  end

  defp check_while(pos, rest, state) do
    # {cond} {body} WHILE
    case Stack.pop_n(state.stack, 2) do
      {[{:block, _body}, {:block, _cond}], base} ->
        # WHILE preserves stack shape
        walk(rest, %{state | stack: base})

      {_, _} ->
        walk(rest, add_error(state, pos, "WHILE requires two blocks (condition and body)"))

      :underflow ->
        walk(rest, add_error(state, pos, "WHILE requires 2 values on the stack (stack underflow)"))
    end
  end

  # --- Effect application ---

  defp apply_effect(op, %{pops: pops, pushes: pushes}, pos, state) do
    arity = length(pops)

    case Stack.pop_n(state.stack, arity) do
      {arg_types, base} ->
        # Unify each arg type with expected
        state =
          arg_types
          |> Enum.zip(pops)
          |> Enum.reduce(%{state | stack: base}, fn {actual, expected}, st ->
            case Unify.unify(actual, expected) do
              {:ok, _} -> st
              :error ->
                add_error(st, pos,
                  "#{format_op(op)} expected #{format_type(expected)}, got #{format_type(actual)}")
            end
          end)

        # Push result types — reverse so pushes[0] lands on top
        Enum.reduce(Enum.reverse(pushes), state, fn type, st ->
          # If the push type is :num_result, resolve based on inputs
          resolved =
            case type do
              :num_result -> resolve_num_result(arg_types)
              other -> other
            end

          %{st | stack: Stack.push(st.stack, resolved)}
        end)

      :underflow ->
        state = add_error(state, pos,
          "#{format_op(op)} requires #{arity} value(s) on the stack (stack underflow)")

        # Best-effort: push result types
        Enum.reduce(Enum.reverse(pushes), state, fn type, st ->
          resolved = if type == :num_result, do: :num, else: type
          %{st | stack: Stack.push(st.stack, resolved)}
        end)
    end
  end

  # When both args are int, result is int; if either is float, result is float; else :num
  defp resolve_num_result(arg_types) do
    cond do
      Enum.all?(arg_types, &(&1 == :int)) -> :int
      Enum.any?(arg_types, &(&1 == :float)) -> :float
      true -> :num
    end
  end

  # --- Helpers ---

  # Collect map elements until ]
  defp collect_map_elements([{:list_close, _, _} | rest], acc, _depth) do
    {Enum.reverse(acc), rest}
  end

  defp collect_map_elements([tok | rest], acc, depth) do
    collect_map_elements(rest, [tok | acc], depth)
  end

  defp collect_map_elements([], acc, _depth) do
    {Enum.reverse(acc), []}
  end

  defp infer_map_types([], state) do
    {k_tvar, state} = fresh_tvar(state)
    {v_tvar, state} = fresh_tvar(state)
    {k_tvar, v_tvar, state}
  end

  defp infer_map_types(tokens, state) do
    types =
      Enum.map(tokens, fn
        {:int_lit, _, _} -> :int
        {:float_lit, _, _} -> :float
        {:bool_lit, _, _} -> :bool
        {:str_lit, _, _} -> :str
        _ -> :any
      end)

    # Chunk into pairs: key, value, key, value, ...
    pairs = Enum.chunk_every(types, 2)

    key_types = Enum.map(pairs, fn [k | _] -> k end)
    val_types = Enum.map(pairs, fn
      [_, v] -> v
      [_] -> :any
    end)

    key_type =
      Enum.reduce(key_types, hd(key_types), fn t, acc ->
        case Unify.unify(t, acc) do
          {:ok, u} -> u
          :error -> :any
        end
      end)

    val_type =
      Enum.reduce(val_types, hd(val_types), fn t, acc ->
        case Unify.unify(t, acc) do
          {:ok, u} -> u
          :error -> :any
        end
      end)

    {key_type, val_type, state}
  end

  defp collect_list_elements([{:list_close, _, _} | rest], acc, _depth) do
    {Enum.reverse(acc), rest}
  end

  defp collect_list_elements([{:list_open, _, _} | _rest] = tokens, acc, depth) do
    collect_list_elements(tl(tokens), [hd(tokens) | acc], depth + 1)
  end

  defp collect_list_elements([tok | rest], acc, depth) do
    collect_list_elements(rest, [tok | acc], depth)
  end

  defp collect_list_elements([], acc, _depth) do
    {Enum.reverse(acc), []}
  end

  defp infer_list_element_type([], state) do
    {tvar, state} = fresh_tvar(state)
    {tvar, state}
  end

  defp infer_list_element_type(tokens, state) do
    # Walk body on a fresh stack so constructors and operators are handled correctly.
    # e.g. [ JNull T JBool ] — JBool consumes T, leaving two json values.
    sub_state = walk(tokens, %{state | stack: Stack.new()})
    state = %{state | errors: sub_state.errors, next_tvar: sub_state.next_tvar}
    depth = Stack.depth(sub_state.stack)

    if depth == 0 do
      {tvar, state} = fresh_tvar(state)
      {tvar, state}
    else
      case Stack.pop_n(sub_state.stack, depth) do
        {types, _} ->
          unified =
            Enum.reduce(tl(types), hd(types), fn t, acc ->
              case Unify.unify(t, acc) do
                {:ok, u} -> u
                :error -> :any
              end
            end)

          {unified, state}

        :underflow ->
          {tvar, state} = fresh_tvar(state)
          {tvar, state}
      end
    end
  end

  defp collect_block_tokens([], _depth, acc), do: {Enum.reverse(acc), []}

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

  defp split_if_branches(tokens) do
    do_split_if(tokens, 0, [], nil)
  end

  defp do_split_if([], _depth, then_acc, else_acc) do
    {Enum.reverse(then_acc), else_acc, []}
  end

  defp do_split_if([{:fn_end, _, _} | rest], 0, then_acc, else_acc) do
    {Enum.reverse(then_acc), else_acc, rest}
  end

  defp do_split_if([{:else_kw, _, _} | rest], 0, then_acc, _else_acc) do
    collect_else(rest, 0, Enum.reverse(then_acc), [])
  end

  defp do_split_if([{:if_kw, _, _} = t | rest], depth, then_acc, else_acc) do
    do_split_if(rest, depth + 1, [t | then_acc], else_acc)
  end

  defp do_split_if([{:match_kw, _, _} = t | rest], depth, then_acc, else_acc) do
    do_split_if(rest, depth + 1, [t | then_acc], else_acc)
  end

  defp do_split_if([{:receive_kw, _, _} = t | rest], depth, then_acc, else_acc) do
    do_split_if(rest, depth + 1, [t | then_acc], else_acc)
  end

  defp do_split_if([{:fn_end, _, _} = t | rest], depth, then_acc, else_acc) when depth > 0 do
    do_split_if(rest, depth - 1, [t | then_acc], else_acc)
  end

  defp do_split_if([t | rest], depth, then_acc, else_acc) do
    do_split_if(rest, depth, [t | then_acc], else_acc)
  end

  defp collect_else([], _depth, then_branch, else_acc) do
    {then_branch, Enum.reverse(else_acc), []}
  end

  defp collect_else([{:fn_end, _, _} | rest], 0, then_branch, else_acc) do
    {then_branch, Enum.reverse(else_acc), rest}
  end

  defp collect_else([{:if_kw, _, _} = t | rest], depth, then_branch, else_acc) do
    collect_else(rest, depth + 1, then_branch, [t | else_acc])
  end

  defp collect_else([{:match_kw, _, _} = t | rest], depth, then_branch, else_acc) do
    collect_else(rest, depth + 1, then_branch, [t | else_acc])
  end

  defp collect_else([{:receive_kw, _, _} = t | rest], depth, then_branch, else_acc) do
    collect_else(rest, depth + 1, then_branch, [t | else_acc])
  end

  defp collect_else([{:fn_end, _, _} = t | rest], depth, then_branch, else_acc) when depth > 0 do
    collect_else(rest, depth - 1, then_branch, [t | else_acc])
  end

  defp collect_else([t | rest], depth, then_branch, else_acc) do
    collect_else(rest, depth, then_branch, [t | else_acc])
  end

  # Collect MATCH arms for the static checker: [{ctor_name, block_tokens}, ...]
  defp collect_checker_match_arms([{:fn_end, _, _} | rest], arms) do
    {Enum.reverse(arms), rest}
  end

  defp collect_checker_match_arms(
         [{:constructor, name, _}, {:block_open, _, _} | rest],
         arms
       ) do
    {block_tokens, remaining} = collect_block_tokens(rest, 0, [])
    collect_checker_match_arms(remaining, [{name, block_tokens} | arms])
  end

  defp collect_checker_match_arms(
         [{:wildcard, _, _}, {:block_open, _, _} | rest],
         arms
       ) do
    {block_tokens, remaining} = collect_block_tokens(rest, 0, [])
    collect_checker_match_arms(remaining, [{:wildcard, block_tokens} | arms])
  end

  defp collect_checker_match_arms([], arms) do
    {Enum.reverse(arms), []}
  end

  defp collect_checker_match_arms([_ | rest], arms) do
    collect_checker_match_arms(rest, arms)
  end

  # Unify result stacks from multiple MATCH arms
  defp unify_arm_stacks([], state, _pos) do
    {Stack.new(), state}
  end

  defp unify_arm_stacks([first_state | rest_states], state, pos) do
    first_depth = Stack.depth(first_state.stack)

    # Merge errors from all arm states
    all_arm_errors = Enum.flat_map([first_state | rest_states], fn s -> s.errors end)
    state = %{state | errors: Enum.uniq(state.errors ++ all_arm_errors)}

    # Check all arms have same stack depth
    state =
      Enum.reduce(rest_states, state, fn arm_state, st ->
        arm_depth = Stack.depth(arm_state.stack)

        if arm_depth != first_depth do
          add_error(st, pos,
            "MATCH arms produce different stack depths (expected #{first_depth}, got #{arm_depth})")
        else
          st
        end
      end)

    # Unify result types across arms
    {first_types, _} = Stack.pop_n(first_state.stack, first_depth)

    result_types =
      Enum.reduce(rest_states, first_types, fn arm_state, acc_types ->
        n = min(first_depth, Stack.depth(arm_state.stack))
        {arm_types, _} = Stack.pop_n(arm_state.stack, n)
        padded = arm_types ++ List.duplicate(:any, max(0, length(acc_types) - length(arm_types)))

        acc_types
        |> Enum.zip(padded)
        |> Enum.map(fn {t1, t2} ->
          case Unify.unify(t1, t2) do
            {:ok, unified} -> unified
            :error -> :any
          end
        end)
      end)

    result_stack =
      result_types
      |> Enum.reduce(Stack.new(), &Stack.push(&2, &1))
      |> Stack.reverse()

    {result_stack, state}
  end

  defp fresh_tvar(state) do
    id = state.next_tvar
    {{:tvar, id}, %{state | next_tvar: id + 1}}
  end

  defp add_error(state, pos, message) do
    error = %Error{message: message, position: pos}
    %{state | errors: [error | state.errors]}
  end

  defp merge_error_lists(errors1, errors2) do
    # Combine errors, deduplicating
    (errors1 ++ errors2) |> Enum.uniq()
  end

  defp format_type(:int), do: "int"
  defp format_type(:float), do: "float"
  defp format_type(:bool), do: "bool"
  defp format_type(:str), do: "str"
  defp format_type(:any), do: "any"
  defp format_type(:void), do: "void"
  defp format_type(:num), do: "num"
  defp format_type({:list, inner}), do: "[#{format_type(inner)}]"
  defp format_type({:map, k, v}), do: "map[#{format_type(k)} #{format_type(v)}]"
  defp format_type({:pid, inner}), do: "pid[#{format_type(inner)}]"
  defp format_type({:block, _}), do: "block"
  defp format_type({:tvar, id}), do: "t#{id}"
  defp format_type({:user_type, name}), do: name
  defp format_type(other), do: inspect(other)

  defp format_op(op), do: String.upcase(to_string(op))

  defp resolve_concurrency_type({:type, type, _}, _types), do: {:ok, type}

  defp resolve_concurrency_type({:ident, name, _}, types) do
    if Map.has_key?(types, name) do
      {:ok, {:user_type, name}}
    else
      {:error, "SPAWN requires a known message type, got #{name}"}
    end
  end

  defp resolve_concurrency_type(_token, _types) do
    {:error, "SPAWN requires a valid message type before the block"}
  end

  defp check_receive_with_explicit_pid(arms, remaining, state, pos) do
    case Stack.pop(state.stack) do
      {:ok, {:pid, {:user_type, type_name}}, base_stack} ->
        {result_stack, state} = check_receive_arms(type_name, base_stack, arms, state, pos)
        walk(remaining, %{state | stack: result_stack})

      {:ok, {:pid, other}, _} ->
        state =
          add_error(state, pos,
            "RECEIVE requires pid[user_type], got #{format_type({:pid, other})}")

        walk(remaining, state)

      {:ok, other, _} ->
        state =
          add_error(state, pos,
            "RECEIVE requires a pid on the stack, got #{format_type(other)}")

        walk(remaining, state)

      :underflow ->
        state = add_error(state, pos, "RECEIVE requires a pid on the stack (stack underflow)")
        walk(remaining, state)
    end
  end

  defp check_receive_arms(type_name, base_stack, arms, state, pos) do
    typedef = Map.get(state.types, type_name)
    has_wildcard = Enum.any?(arms, fn {name, _} -> name == :wildcard end)

    state =
      cond do
        is_nil(typedef) ->
          add_error(state, pos, "RECEIVE requires a pid of a known sum type, got #{type_name}")

        has_wildcard ->
          state

        true ->
          arm_names = MapSet.new(arms, fn {name, _} -> name end)
          all_ctors = MapSet.new(Map.keys(typedef.variants))
          missing = MapSet.difference(all_ctors, arm_names)

          if MapSet.size(missing) > 0 do
            add_error(state, pos,
              "RECEIVE on '#{type_name}' is not exhaustive: missing #{Enum.join(Enum.sort(MapSet.to_list(missing)), ", ")}")
          else
            state
          end
      end

    arm_states =
      Enum.map(arms, fn
        {:wildcard, arm_tokens} ->
          walk(arm_tokens, %{state | stack: base_stack})

        {ctor_name, arm_tokens} ->
          field_types =
            if typedef, do: Map.get(typedef.variants, ctor_name, []), else: []

          arm_stack =
            field_types
            |> Enum.reverse()
            |> Enum.reduce(base_stack, fn t, s -> Stack.push(s, t) end)

          walk(arm_tokens, %{state | stack: arm_stack})
      end)

    unify_arm_stacks(arm_states, state, pos)
  end

  defp compute_actor_required_functions(items, type_env) do
    functions =
      Enum.reduce(items, %{}, fn
        %Axiom.Types.Function{} = func, acc -> Map.put(acc, func.name, func)
        _, acc -> acc
      end)

    initial =
      functions
      |> Enum.reduce(MapSet.new(), fn {name, func}, acc ->
        if tokens_require_actor?(func.body) or tokens_require_actor?(func.pre_condition) or
             tokens_require_actor?(func.post_condition) do
          MapSet.put(acc, name)
        else
          acc
        end
      end)

    expand_actor_required(functions, type_env, initial)
  end

  defp expand_actor_required(functions, type_env, required) do
    expanded =
      Enum.reduce(functions, required, fn {name, func}, acc ->
        if MapSet.member?(acc, name) or function_calls_actor_required?(func, acc) do
          MapSet.put(acc, name)
        else
          acc
        end
      end)

    if MapSet.equal?(expanded, required), do: expanded, else: expand_actor_required(functions, type_env, expanded)
  end

  defp function_calls_actor_required?(func, required) do
    referenced_names(func.body)
    |> Enum.concat(referenced_names(func.pre_condition))
    |> Enum.concat(referenced_names(func.post_condition))
    |> Enum.any?(fn name -> MapSet.member?(required, name) end)
  end

  defp tokens_require_actor?(nil), do: false
  defp tokens_require_actor?(tokens), do: Enum.any?(tokens, &match?({:op, :self, _}, &1))

  defp referenced_names(nil), do: []

  defp referenced_names(tokens) do
    tokens
    |> Enum.flat_map(fn
      {:ident, name, _} -> [name]
      _ -> []
    end)
  end

  # Count {} placeholders in a format string, skipping {{ and }}
  defp count_fmt_placeholders(text), do: count_fmt_placeholders_acc(text, 0)
  defp count_fmt_placeholders_acc("", n), do: n
  defp count_fmt_placeholders_acc("{{" <> rest, n), do: count_fmt_placeholders_acc(rest, n)
  defp count_fmt_placeholders_acc("}}" <> rest, n), do: count_fmt_placeholders_acc(rest, n)
  defp count_fmt_placeholders_acc("{}" <> rest, n), do: count_fmt_placeholders_acc(rest, n + 1)
  defp count_fmt_placeholders_acc(<<_, rest::binary>>, n), do: count_fmt_placeholders_acc(rest, n)
end
