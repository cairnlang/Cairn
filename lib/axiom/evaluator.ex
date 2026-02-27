defmodule Axiom.Evaluator do
  @moduledoc """
  Walks a token list and executes it against a stack using Axiom.Runtime.

  Uses an explicit token cursor to handle control flow (IF/ELSE/END).
  """

  alias Axiom.Runtime

  @doc """
  Evaluates a list of tokens against an initial stack.
  Returns the final stack.
  """
  @spec eval_tokens([Axiom.Types.token()], list(), map()) :: list()
  def eval_tokens(tokens, stack \\ [], env \\ %{}) do
    {stack, _env} = run(tokens, stack, env)
    stack
  end

  @doc """
  Evaluates tokens and returns both stack and environment.
  """
  @spec eval_tokens_with_env([Axiom.Types.token()], list(), map()) :: {list(), map()}
  def eval_tokens_with_env(tokens, stack \\ [], env \\ %{}) do
    run(tokens, stack, env)
  end

  # Main execution loop — processes tokens sequentially
  defp run([], stack, env), do: {stack, env}

  # Literals — push onto stack
  defp run([{:int_lit, val, _} | rest], stack, env), do: run(rest, [val | stack], env)
  defp run([{:float_lit, val, _} | rest], stack, env), do: run(rest, [val | stack], env)
  defp run([{:bool_lit, val, _} | rest], stack, env), do: run(rest, [val | stack], env)
  defp run([{:str_lit, val, _} | rest], stack, env), do: run(rest, [val | stack], env)
  defp run([{:list_lit, val, _} | rest], stack, env), do: run(rest, [val | stack], env)
  defp run([{:map_lit, val, _} | rest], stack, env), do: run(rest, [val | stack], env)

  # APPLY — pop a block from the stack and execute it inline
  defp run([{:op, :apply, _} | rest], [{:block, block_tokens, block_env} | stack], env) do
    # Merge the block's captured env with current env (current wins on conflict)
    merged_env = Map.merge(block_env, env)
    {stack, _} = run(block_tokens, stack, merged_env)
    run(rest, stack, env)
  end

  # LET — pop top value, bind to the following identifier name
  defp run([{:let_kw, _, _pos}, {:ident, name, _} | rest], [value | stack], env) do
    run(rest, stack, Map.put(env, name, {:let_binding, value}))
  end

  defp run([{:let_kw, _, pos}, {:ident, _name, _} | _rest], [], _env) do
    raise Axiom.RuntimeError, "LET at word #{pos + 1}: empty stack"
  end

  # SPAWN is parsed and type-checked, but runtime support is deferred.
  defp run([{:spawn_kw, _, pos}, _type_token, {:block_open, _, _} | rest], _stack, _env) do
    {_block_tokens, _remaining} = collect_block(rest, 0, [])
    raise Axiom.RuntimeError, "SPAWN at word #{pos + 1}: not implemented yet"
  end

  defp run([{:spawn_kw, _, pos} | _], _stack, _env) do
    raise Axiom.RuntimeError, "SPAWN at word #{pos + 1}: not implemented yet"
  end

  # SEND is statically checked, but runtime support is deferred.
  defp run([{:op, :send, pos} | _], _stack, _env) do
    raise Axiom.RuntimeError, "SEND at word #{pos + 1}: not implemented yet"
  end

  # Operators — delegate to Runtime
  defp run([{:op, op, _} | rest], stack, env), do: run(rest, Runtime.execute(op, stack), env)

  # Constructor — build a variant value: pop fields, push {:variant, type, ctor, fields}
  defp run([{:constructor, name, pos} | rest], stack, env) do
    ctors = Map.get(env, "__constructors__", %{})

    case Map.get(ctors, name) do
      nil ->
        raise Axiom.RuntimeError, "unknown constructor '#{name}' at word #{pos + 1}"

      {type_name, field_types} ->
        arity = length(field_types)
        {fields, stack} = pop_args(stack, arity)
        variant = {:variant, type_name, name, fields}
        run(rest, [variant | stack], env)
    end
  end

  # MATCH — pop a variant, dispatch to matching arm, push fields onto stack
  defp run([{:match_kw, _, pos} | rest], [{:variant, _type_name, ctor_name, fields} | stack], env) do
    {arms, remaining} = collect_match_arms(rest, [], 0)

    case Enum.find(arms, fn {arm_ctor, _} -> arm_ctor == ctor_name end) do
      {_ctor, arm_tokens} ->
        # Push fields onto stack (last field first so first field is on top)
        field_stack = Enum.reverse(fields) ++ stack
        {stack, env} = run(arm_tokens, field_stack, env)
        run(remaining, stack, env)

      nil ->
        # Try wildcard catch-all arm
        case Enum.find(arms, fn {arm_ctor, _} -> arm_ctor == :wildcard end) do
          {:wildcard, arm_tokens} ->
            # Wildcard discards all fields — body starts with clean stack
            {stack, env} = run(arm_tokens, stack, env)
            run(remaining, stack, env)

          nil ->
            raise Axiom.RuntimeError,
              "MATCH at word #{pos + 1}: no arm for constructor '#{ctor_name}'"
        end
    end
  end

  defp run([{:match_kw, _, pos} | _], [top | _], _env) do
    raise Axiom.RuntimeError,
      "MATCH at word #{pos + 1}: expected a variant on the stack, got #{inspect(top)}"
  end

  defp run([{:match_kw, _, pos} | _], [], _env) do
    raise Axiom.RuntimeError, "MATCH at word #{pos + 1}: empty stack"
  end

  # RECEIVE is parsed and type-checked, but runtime support is deferred.
  defp run([{:receive_kw, _, pos} | _], _stack, _env) do
    raise Axiom.RuntimeError, "RECEIVE at word #{pos + 1}: not implemented yet"
  end

  # Identifiers — look up in environment
  defp run([{:ident, name, pos} | rest], stack, env) do
    case Map.get(env, name) do
      nil ->
        raise Axiom.RuntimeError, "undefined '#{name}' at word #{pos + 1}"

      {:let_binding, value} ->
        run(rest, [value | stack], env)

      %Axiom.Types.Function{} = func ->
        stack = eval_function_call(func, stack, env)
        run(rest, stack, env)
    end
  end

  # Map construction: M[ key val ... ]
  defp run([{:map_open, _, _} | rest], stack, env) do
    {map, remaining} = collect_map_tokens(rest, [], env)
    run(remaining, [map | stack], env)
  end

  # List construction: [ 1 2 3 ]
  defp run([{:list_open, _, _} | rest], stack, env) do
    # Evaluate tokens inside [ ] to build list elements, then collect
    {list_items, remaining} = collect_list_tokens(rest, [], env)
    run(remaining, [list_items | stack], env)
  end

  # IF ... END / IF ... ELSE ... END
  defp run([{:if_kw, _, _} | rest], [condition | stack], env) do
    {then_branch, else_branch, remaining} = split_if_branches(rest, 0, [], nil)

    if condition do
      {stack, env} = run(then_branch, stack, env)
      run(remaining, stack, env)
    else
      case else_branch do
        nil -> run(remaining, stack, env)
        tokens ->
          {stack, env} = run(tokens, stack, env)
          run(remaining, stack, env)
      end
    end
  end

  defp run([{:if_kw, _, pos} | _], [], _env) do
    raise Axiom.RuntimeError, "IF at word #{pos + 1} requires a boolean on the stack"
  end

  # Block literals: { body } — pushes a block (token list) onto the stack
  defp run([{:block_open, _, _} | rest], stack, env) do
    {block_tokens, remaining} = collect_block(rest, 0, [])
    run(remaining, [{:block, block_tokens, env} | stack], env)
  end

  defp run([{type, val, pos} | _], _stack, _env) do
    raise Axiom.RuntimeError, "unexpected #{type} '#{inspect(val)}' at word #{pos + 1}"
  end

  # Collect tokens inside [ ], evaluating them to produce list items
  defp collect_list_tokens([{:list_close, _, _} | rest], items, _env) do
    {Enum.reverse(items), rest}
  end

  defp collect_list_tokens([{:int_lit, val, _} | rest], items, env) do
    collect_list_tokens(rest, [val | items], env)
  end

  defp collect_list_tokens([{:float_lit, val, _} | rest], items, env) do
    collect_list_tokens(rest, [val | items], env)
  end

  defp collect_list_tokens([{:bool_lit, val, _} | rest], items, env) do
    collect_list_tokens(rest, [val | items], env)
  end

  defp collect_list_tokens([{:str_lit, val, _} | rest], items, env) do
    collect_list_tokens(rest, [val | items], env)
  end

  # Constructor inside a list literal — pop its fields from accumulated items, push variant
  defp collect_list_tokens([{:constructor, name, pos} | rest], items, env) do
    ctors = Map.get(env, "__constructors__", %{})

    case Map.get(ctors, name) do
      nil ->
        raise Axiom.RuntimeError, "unknown constructor '#{name}' at word #{pos + 1}"

      {type_name, field_types} ->
        arity = length(field_types)
        {fields, remaining_items} = Enum.split(items, arity)
        variant = {:variant, type_name, name, fields}
        collect_list_tokens(rest, [variant | remaining_items], env)
    end
  end

  defp collect_list_tokens([], _items, _env) do
    raise Axiom.RuntimeError, "unmatched ["
  end

  # Collect tokens inside M[ ], building key-value pairs
  defp collect_map_tokens([{:list_close, _, _} | rest], items, _env) do
    pairs = items |> Enum.reverse() |> Enum.chunk_every(2)

    map =
      Map.new(pairs, fn
        [k, v] -> {k, v}
        [_] -> raise Axiom.RuntimeError, "M[ requires even number of elements (key-value pairs)"
      end)

    {map, rest}
  end

  defp collect_map_tokens([{:int_lit, val, _} | rest], items, env),
    do: collect_map_tokens(rest, [val | items], env)

  defp collect_map_tokens([{:float_lit, val, _} | rest], items, env),
    do: collect_map_tokens(rest, [val | items], env)

  defp collect_map_tokens([{:bool_lit, val, _} | rest], items, env),
    do: collect_map_tokens(rest, [val | items], env)

  defp collect_map_tokens([{:str_lit, val, _} | rest], items, env),
    do: collect_map_tokens(rest, [val | items], env)

  # Constructor inside a map literal — pop its fields from accumulated items, push variant
  defp collect_map_tokens([{:constructor, name, pos} | rest], items, env) do
    ctors = Map.get(env, "__constructors__", %{})

    case Map.get(ctors, name) do
      nil ->
        raise Axiom.RuntimeError, "unknown constructor '#{name}' at word #{pos + 1}"

      {type_name, field_types} ->
        arity = length(field_types)
        {fields, remaining_items} = Enum.split(items, arity)
        variant = {:variant, type_name, name, fields}
        collect_map_tokens(rest, [variant | remaining_items], env)
    end
  end

  defp collect_map_tokens([], _items, _env) do
    raise Axiom.RuntimeError, "unmatched M["
  end

  # Collect tokens inside { }, handling nesting
  defp collect_block([], _depth, _acc) do
    raise Axiom.RuntimeError, "unmatched {"
  end

  defp collect_block([{:block_close, _, _} | rest], 0, acc) do
    {Enum.reverse(acc), rest}
  end

  defp collect_block([{:block_open, _, _} = t | rest], depth, acc) do
    collect_block(rest, depth + 1, [t | acc])
  end

  defp collect_block([{:block_close, _, _} = t | rest], depth, acc) when depth > 0 do
    collect_block(rest, depth - 1, [t | acc])
  end

  defp collect_block([t | rest], depth, acc) do
    collect_block(rest, depth, [t | acc])
  end

  # Split IF tokens into then-branch, optional else-branch, and remaining
  # Handles nested IFs by tracking depth
  defp split_if_branches([], _depth, _then_acc, _else_acc) do
    raise Axiom.RuntimeError, "IF without matching END"
  end

  defp split_if_branches([{:fn_end, _, _} | rest], 0, then_acc, else_acc) do
    {Enum.reverse(then_acc), else_acc, rest}
  end

  defp split_if_branches([{:else_kw, _, _} | rest], 0, then_acc, _else_acc) do
    # Switch from collecting then-branch to collecting else-branch
    collect_else_branch(rest, 0, Enum.reverse(then_acc), [])
  end

  # Nested IF increases depth
  defp split_if_branches([{:if_kw, _, _} = t | rest], depth, then_acc, else_acc) do
    split_if_branches(rest, depth + 1, [t | then_acc], else_acc)
  end

  defp split_if_branches([{:match_kw, _, _} = t | rest], depth, then_acc, else_acc) do
    split_if_branches(rest, depth + 1, [t | then_acc], else_acc)
  end

  defp split_if_branches([{:receive_kw, _, _} = t | rest], depth, then_acc, else_acc) do
    split_if_branches(rest, depth + 1, [t | then_acc], else_acc)
  end

  # Nested END decreases depth
  defp split_if_branches([{:fn_end, _, _} = t | rest], depth, then_acc, else_acc) when depth > 0 do
    split_if_branches(rest, depth - 1, [t | then_acc], else_acc)
  end

  defp split_if_branches([t | rest], depth, then_acc, else_acc) do
    split_if_branches(rest, depth, [t | then_acc], else_acc)
  end

  defp collect_else_branch([], _depth, _then, _else_acc) do
    raise Axiom.RuntimeError, "IF/ELSE without matching END"
  end

  defp collect_else_branch([{:fn_end, _, _} | rest], 0, then_branch, else_acc) do
    {then_branch, Enum.reverse(else_acc), rest}
  end

  defp collect_else_branch([{:if_kw, _, _} = t | rest], depth, then_branch, else_acc) do
    collect_else_branch(rest, depth + 1, then_branch, [t | else_acc])
  end

  defp collect_else_branch([{:match_kw, _, _} = t | rest], depth, then_branch, else_acc) do
    collect_else_branch(rest, depth + 1, then_branch, [t | else_acc])
  end

  defp collect_else_branch([{:receive_kw, _, _} = t | rest], depth, then_branch, else_acc) do
    collect_else_branch(rest, depth + 1, then_branch, [t | else_acc])
  end

  defp collect_else_branch([{:fn_end, _, _} = t | rest], depth, then_branch, else_acc) when depth > 0 do
    collect_else_branch(rest, depth - 1, then_branch, [t | else_acc])
  end

  defp collect_else_branch([t | rest], depth, then_branch, else_acc) do
    collect_else_branch(rest, depth, then_branch, [t | else_acc])
  end

  # Collect MATCH arms: [{ctor_name, block_tokens}, ...]
  # Arms are: Constructor { body } pairs, terminated by END at depth 0
  defp collect_match_arms([{:fn_end, _, _} | rest], arms, 0) do
    {Enum.reverse(arms), rest}
  end

  defp collect_match_arms([{:constructor, name, _}, {:block_open, _, _} | rest], arms, depth) do
    {block_tokens, remaining} = collect_block(rest, 0, [])
    collect_match_arms(remaining, [{name, block_tokens} | arms], depth)
  end

  defp collect_match_arms([{:wildcard, _, _}, {:block_open, _, _} | rest], arms, depth) do
    {block_tokens, remaining} = collect_block(rest, 0, [])
    collect_match_arms(remaining, [{:wildcard, block_tokens} | arms], depth)
  end

  defp collect_match_arms([{:match_kw, _, _} | _rest], _arms, _depth) do
    raise Axiom.RuntimeError, "nested MATCH not supported in MATCH arms"
  end

  defp collect_match_arms([], _arms, _depth) do
    raise Axiom.RuntimeError, "MATCH without matching END"
  end

  defp collect_match_arms([token | _], _arms, _depth) do
    raise Axiom.RuntimeError, "unexpected token in MATCH arm: #{inspect(token)}"
  end

  # --- Function calls ---

  @doc """
  Executes a function call: pops args, evaluates body, checks contract, pushes result.
  """
  def eval_function_call(%Axiom.Types.Function{} = func, stack, env) do
    {args, rest} = pop_args(stack, length(func.param_types))

    # Check arg types against declared param_types
    check_arg_types(func, args)

    if func.pre_condition do
      check_pre(func, args, env)
    end

    result_stack = eval_tokens(func.body, args, env)

    if func.post_condition do
      check_post(func, result_stack, env)
    end

    check_return_types(func, result_stack)

    result_stack ++ rest
  end

  defp pop_args(stack, 0), do: {[], stack}

  defp pop_args(stack, n) when length(stack) >= n do
    Enum.split(stack, n)
  end

  defp pop_args(stack, n) do
    raise Axiom.RuntimeError, "stack underflow: need #{n} args, have #{length(stack)}"
  end

  defp check_arg_types(func, args) do
    func.param_types
    |> Enum.zip(args)
    |> Enum.each(fn {type, value} ->
      unless matches_type?(value, type) do
        raise Axiom.RuntimeError,
          "type error in '#{func.name}': expected #{format_type(type)}, got #{inspect(value)}"
      end
    end)
  end

  defp matches_type?(_, :any), do: true
  defp matches_type?(v, :int) when is_integer(v), do: true
  defp matches_type?(v, :float) when is_float(v), do: true
  defp matches_type?(v, :bool) when is_boolean(v), do: true
  defp matches_type?(v, :str) when is_binary(v), do: true
  defp matches_type?(v, {:list, _}) when is_list(v), do: true
  defp matches_type?(v, {:map, _, _}) when is_map(v), do: true
  defp matches_type?({:pid, inner}, {:pid, expected_inner}), do: matches_type?(inner, expected_inner)
  defp matches_type?({:variant, type_name, _, _}, {:user_type, type_name}), do: true
  defp matches_type?(_, _), do: false

  defp format_type({:list, inner}), do: "[#{inner}]"
  defp format_type({:map, k, v}), do: "map[#{k} #{v}]"
  defp format_type({:pid, inner}), do: "pid[#{format_type(inner)}]"
  defp format_type({:user_type, name}), do: name
  defp format_type(type), do: to_string(type)

  defp check_pre(func, args, env) do
    check_stack = eval_tokens(func.pre_condition, args, env)

    case check_stack do
      [true | _] ->
        :ok

      [false | _] ->
        raise Axiom.ContractError,
          message: "PRE condition failed for #{func.name}",
          function_name: func.name,
          stack: args

      other ->
        raise Axiom.ContractError,
          message: "PRE condition for #{func.name} did not return bool, got: #{inspect(other)}",
          function_name: func.name,
          stack: args
    end
  end

  defp check_return_types(%{return_types: [:void]} = func, result_stack) do
    if result_stack != [] do
      raise Axiom.RuntimeError,
        "type error in '#{func.name}': declared -> void but left #{length(result_stack)} value(s) on stack"
    end
  end

  defp check_return_types(func, result_stack) do
    expected = length(func.return_types)
    actual = length(result_stack)

    if actual != expected do
      raise Axiom.RuntimeError,
        "type error in '#{func.name}': declared -> #{format_return_types(func.return_types)} " <>
          "(#{expected} value(s)) but got #{actual}"
    end

    func.return_types
    |> Enum.zip(result_stack)
    |> Enum.each(fn {type, value} ->
      unless matches_type?(value, type) do
        raise Axiom.RuntimeError,
          "type error in '#{func.name}': expected return type #{format_type(type)}, got #{inspect(value)}"
      end
    end)
  end

  defp format_return_types(types), do: Enum.map_join(types, " ", &format_type/1)

  defp check_post(func, result_stack, env) do
    check_stack = eval_tokens(func.post_condition, result_stack, env)

    case check_stack do
      [true | _] ->
        :ok

      [false | _] ->
        raise Axiom.ContractError,
          message: "POST condition failed for #{func.name}",
          function_name: func.name,
          stack: result_stack

      other ->
        raise Axiom.ContractError,
          message: "POST condition for #{func.name} did not return bool, got: #{inspect(other)}",
          function_name: func.name,
          stack: result_stack
    end
  end
end
