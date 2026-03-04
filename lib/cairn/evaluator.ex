defmodule Cairn.Evaluator do
  @moduledoc """
  Walks a token list and executes it against a stack using Cairn.Runtime.

  Uses an explicit token cursor to handle control flow (IF/ELSE/END).
  """

  alias Cairn.Runtime

  @doc """
  Evaluates a list of tokens against an initial stack.
  Returns the final stack.
  """
  @spec eval_tokens([Cairn.Types.token()], list(), map()) :: list()
  def eval_tokens(tokens, stack \\ [], env \\ %{}) do
    {stack, _env} = run(tokens, stack, env)
    stack
  end

  @doc """
  Evaluates tokens and returns both stack and environment.
  """
  @spec eval_tokens_with_env([Cairn.Types.token()], list(), map()) :: {list(), map()}
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

  # WITH_STATE — explicit, local state threading for one block.
  defp run([{:op, :with_state, pos} | rest], [{:block, block_tokens, block_env}, state_value | stack], env) do
    run_with_state(rest, pos, block_tokens, block_env, state_value, stack, env)
  end

  defp run([{:op, :with_state, pos} | rest], [state_value, {:block, block_tokens, block_env} | stack], env) do
    run_with_state(rest, pos, block_tokens, block_env, state_value, stack, env)
  end

  defp run([{:op, :with_state, pos} | _], [_, other | _], _env) do
    raise Cairn.RuntimeError,
      "WITH_STATE at word #{pos + 1}: requires a block and initial state, got #{inspect(other)}"
  end

  defp run([{:op, :with_state, pos} | _], _stack, _env) do
    raise Cairn.RuntimeError, "WITH_STATE at word #{pos + 1}: stack underflow"
  end

  # REPEAT — bounded iteration that preserves WITH_STATE updates across iterations.
  defp run([{:op, :repeat, pos} | rest], [{:block, block_tokens, block_env}, count | stack], env)
       when is_integer(count) do
    run_repeat(rest, pos, block_tokens, block_env, count, stack, env)
  end

  defp run([{:op, :repeat, pos} | rest], [count, {:block, block_tokens, block_env} | stack], env)
       when is_integer(count) do
    run_repeat(rest, pos, block_tokens, block_env, count, stack, env)
  end

  defp run([{:op, :repeat, pos} | _], [_, other | _], _env) do
    raise Cairn.RuntimeError,
      "REPEAT at word #{pos + 1}: requires a block and integer count, got #{inspect(other)}"
  end

  defp run([{:op, :repeat, pos} | _], _stack, _env) do
    raise Cairn.RuntimeError, "REPEAT at word #{pos + 1}: stack underflow"
  end

  defp run([{:op, :state, pos} | rest], stack, env) do
    case Map.fetch(env, :__cairn_state__) do
      {:ok, state_value} ->
        run(rest, [state_value | stack], env)

      :error ->
        raise Cairn.RuntimeError, "STATE at word #{pos + 1}: only available inside WITH_STATE"
    end
  end

  defp run([{:op, :set_state, pos} | rest], [value | stack], env) do
    if Map.has_key?(env, :__cairn_state__) do
      run(rest, stack, Map.put(env, :__cairn_state__, value))
    else
      raise Cairn.RuntimeError, "SET_STATE at word #{pos + 1}: only available inside WITH_STATE"
    end
  end

  defp run([{:op, :set_state, pos} | _], [], _env) do
    raise Cairn.RuntimeError, "SET_STATE at word #{pos + 1}: empty stack"
  end

  defp run([{:op, :step, pos}, {:ident, name, _} | rest], stack, env) do
    case {Map.fetch(env, :__cairn_state__), Map.get(env, name)} do
      {:error, _} ->
        raise Cairn.RuntimeError, "STEP at word #{pos + 1}: only available inside WITH_STATE"

      {{:ok, state_value}, %Cairn.Types.Function{} = func} ->
        result_stack = eval_function_call(func, [state_value], env)

        case result_stack do
          [next_state] ->
            run(rest, stack, Map.put(env, :__cairn_state__, next_state))

          other ->
            raise Cairn.RuntimeError,
              "STEP at word #{pos + 1}: function '#{name}' must return exactly one state value, got #{inspect(other)}"
        end

      {{:ok, _state_value}, nil} ->
        raise Cairn.RuntimeError, "STEP at word #{pos + 1}: undefined function '#{name}'"

      {{:ok, _state_value}, other} ->
        raise Cairn.RuntimeError,
          "STEP at word #{pos + 1}: expected function name after STEP, got #{inspect(other)}"
    end
  end

  defp run([{:op, :step, pos} | _], _stack, _env) do
    raise Cairn.RuntimeError, "STEP at word #{pos + 1}: requires a function name"
  end

  # HOST_CALL helper_name — narrow, whitelisted host interop v1.
  defp run([{:op, :host_call, _pos}, {:ident, name, _} | rest], [args | stack], env) when is_list(args) do
    result = Runtime.host_call(name, args)
    run(rest, [result | stack], env)
  end

  defp run([{:op, :host_call, pos}, {:ident, _name, _} | _], [other | _], _env) do
    raise Cairn.RuntimeError,
      "HOST_CALL at word #{pos + 1}: requires a list of arguments on the stack, got #{inspect(other)}"
  end

  defp run([{:op, :host_call, pos}, {:ident, _name, _} | _], [], _env) do
    raise Cairn.RuntimeError, "HOST_CALL at word #{pos + 1}: stack underflow"
  end

  defp run([{:op, :host_call, pos} | _], _stack, _env) do
    raise Cairn.RuntimeError, "HOST_CALL at word #{pos + 1}: requires a whitelisted helper name"
  end

  # HTTP_SERVE — bounded host-backed HTTP serving with Cairn-owned request routing.
  # Stack shapes:
  #   8080 { ...path, method, query, form -> status, content_type, body... } HTTP_SERVE
  #   "0.0.0.0" 8080 { ... } HTTP_SERVE
  #   M[ "request_line_max" 4096 "read_timeout_ms" 5000 ] "0.0.0.0" 8080 { ... } HTTP_SERVE
  #   M[ ... ] 8080 { ... } HTTP_SERVE
  defp run(
         [{:op, :http_serve, pos} | rest],
         [{:block, block_tokens, block_env}, port, bind_host, options | stack],
         env
       )
       when is_integer(port) and is_binary(bind_host) and is_map(options) do
    run_http_serve(rest, pos, block_tokens, block_env, bind_host, port, options, stack, env)
  end

  defp run(
         [{:op, :http_serve, pos} | rest],
         [options, bind_host, port, {:block, block_tokens, block_env} | stack],
         env
       )
       when is_integer(port) and is_binary(bind_host) and is_map(options) do
    run_http_serve(rest, pos, block_tokens, block_env, bind_host, port, options, stack, env)
  end

  defp run(
         [{:op, :http_serve, pos} | rest],
         [{:block, block_tokens, block_env}, port, options | stack],
         env
       )
       when is_integer(port) and is_map(options) do
    run_http_serve(rest, pos, block_tokens, block_env, "127.0.0.1", port, options, stack, env)
  end

  defp run(
         [{:op, :http_serve, pos} | rest],
         [options, port, {:block, block_tokens, block_env} | stack],
         env
       )
       when is_integer(port) and is_map(options) do
    run_http_serve(rest, pos, block_tokens, block_env, "127.0.0.1", port, options, stack, env)
  end

  defp run(
         [{:op, :http_serve, pos} | rest],
         [{:block, block_tokens, block_env}, port, bind_host | stack],
         env
       )
       when is_integer(port) and is_binary(bind_host) do
    run_http_serve(rest, pos, block_tokens, block_env, bind_host, port, %{}, stack, env)
  end

  defp run(
         [{:op, :http_serve, pos} | rest],
         [bind_host, port, {:block, block_tokens, block_env} | stack],
         env
       )
       when is_integer(port) and is_binary(bind_host) do
    run_http_serve(rest, pos, block_tokens, block_env, bind_host, port, %{}, stack, env)
  end

  defp run([{:op, :http_serve, pos} | rest], [{:block, block_tokens, block_env}, port | stack], env)
       when is_integer(port) do
    run_http_serve(rest, pos, block_tokens, block_env, "127.0.0.1", port, %{}, stack, env)
  end

  defp run([{:op, :http_serve, pos} | rest], [port, {:block, block_tokens, block_env} | stack], env)
       when is_integer(port) do
    run_http_serve(rest, pos, block_tokens, block_env, "127.0.0.1", port, %{}, stack, env)
  end

  defp run([{:op, :http_serve, pos} | _], [top, under | _], _env) do
    raise Cairn.RuntimeError,
      "HTTP_SERVE at word #{pos + 1}: requires a block handler and integer port (optionally beneath a bind address), got #{inspect(top)} over #{inspect(under)}"
  end

  defp run([{:op, :http_serve, pos} | _], _stack, _env) do
    raise Cairn.RuntimeError, "HTTP_SERVE at word #{pos + 1}: stack underflow"
  end

  # LET — pop top value, bind to the following identifier name
  defp run([{:let_kw, _, _pos}, {:ident, name, _} | rest], [value | stack], env) do
    run(rest, stack, Map.put(env, name, {:let_binding, value}))
  end

  defp run([{:let_kw, _, pos}, {:ident, _name, _} | _rest], [], _env) do
    raise Cairn.RuntimeError, "LET at word #{pos + 1}: empty stack"
  end

  # SPAWN MessageType { ... } — starts the spawned block with its own typed pid on stack.
  defp run([{:spawn_kw, _, pos}, type_token, {:using_kw, _, _}, {:ident, _protocol_name, _}, {:block_open, _, _} | rest], stack, env) do
    spawn_actor(:spawn, pos, type_token, rest, stack, env)
  end

  defp run([{:spawn_kw, _, pos}, type_token, {:block_open, _, _} | rest], stack, env) do
    spawn_actor(:spawn, pos, type_token, rest, stack, env)
  end

  defp run([{:spawn_kw, _, pos} | _], _stack, _env) do
    raise Cairn.RuntimeError, "SPAWN at word #{pos + 1}: requires a message type and block"
  end

  # SPAWN_LINK MessageType { ... } — links actor lifecycle to the current process.
  defp run([{:spawn_link_kw, _, pos}, type_token, {:using_kw, _, _}, {:ident, _protocol_name, _}, {:block_open, _, _} | rest], stack, env) do
    spawn_actor(:spawn_link, pos, type_token, rest, stack, env)
  end

  defp run([{:spawn_link_kw, _, pos}, type_token, {:block_open, _, _} | rest], stack, env) do
    spawn_actor(:spawn_link, pos, type_token, rest, stack, env)
  end

  defp run([{:spawn_link_kw, _, pos} | _], _stack, _env) do
    raise Cairn.RuntimeError, "SPAWN_LINK at word #{pos + 1}: requires a message type and block"
  end

  # SEND: pid[msg] msg SEND
  defp run([{:op, :send, _pos} | rest], [msg, {:pid, _msg_type, pid} | stack], env)
       when is_pid(pid) do
    send(pid, msg)
    run(rest, stack, env)
  end

  defp run([{:op, :send, pos} | _], [_, other | _], _env) do
    raise Cairn.RuntimeError,
      "SEND at word #{pos + 1}: expected pid beneath message, got #{inspect(other)}"
  end

  defp run([{:op, :send, pos} | _], _stack, _env) do
    raise Cairn.RuntimeError, "SEND at word #{pos + 1}: stack underflow"
  end

  # MONITOR — creates a non-blocking monitor handle for a pid.
  defp run([{:op, :monitor, _pos} | rest], [{:pid, msg_type, pid} | stack], env) when is_pid(pid) do
    ref = Process.monitor(pid)
    run(rest, [{:monitor, msg_type, pid, ref} | stack], env)
  end

  defp run([{:op, :monitor, pos} | _], [other | _], _env) do
    raise Cairn.RuntimeError, "MONITOR at word #{pos + 1}: expected pid on stack, got #{inspect(other)}"
  end

  defp run([{:op, :monitor, pos} | _], [], _env) do
    raise Cairn.RuntimeError, "MONITOR at word #{pos + 1}: empty stack"
  end

  # AWAIT — blocks on a monitor handle and returns a normalized string reason.
  defp run([{:op, :await, _pos} | rest], [{:monitor, _msg_type, pid, ref} | stack], env) do
    reason =
      receive do
        {:DOWN, ^ref, :process, ^pid, down_reason} -> normalize_down_reason(down_reason)
      end

    run(rest, [reason | stack], env)
  end

  defp run([{:op, :await, pos} | _], [other | _], _env) do
    raise Cairn.RuntimeError, "AWAIT at word #{pos + 1}: expected monitor on stack, got #{inspect(other)}"
  end

  defp run([{:op, :await, pos} | _], [], _env) do
    raise Cairn.RuntimeError, "AWAIT at word #{pos + 1}: empty stack"
  end

  # SELF — push the current process's typed pid handle
  defp run([{:op, :self, pos} | rest], stack, env) do
    case Process.get(:cairn_self_type) do
      nil ->
        raise Cairn.RuntimeError, "SELF at word #{pos + 1}: only available inside a SPAWN block"

      msg_type ->
        run(rest, [{:pid, msg_type, self()} | stack], env)
    end
  end

  # EXIT — actor-only explicit process termination with a reason.
  defp run([{:op, :exit, pos} | _rest], [reason | _stack], _env) do
    case Process.get(:cairn_self_type) do
      nil ->
        raise Cairn.RuntimeError, "EXIT at word #{pos + 1}: only available inside a SPAWN or SPAWN_LINK block"

      _msg_type ->
        exit(reason)
    end
  end

  defp run([{:op, :exit, pos} | _rest], [], _env) do
    raise Cairn.RuntimeError, "EXIT at word #{pos + 1}: requires a reason on the stack"
  end

  # Operators — delegate to Runtime
  defp run([{:op, op, _} | rest], stack, env), do: run(rest, Runtime.execute(op, stack), env)

  # Constructor — build a variant value: pop fields, push {:variant, type, ctor, fields}
  defp run([{:constructor, name, pos} | rest], stack, env) do
    ctors = Map.get(env, "__constructors__", %{})

    case Map.get(ctors, name) do
      nil ->
        raise Cairn.RuntimeError, "unknown constructor '#{name}' at word #{pos + 1}"

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
            raise Cairn.RuntimeError,
              "MATCH at word #{pos + 1}: no arm for constructor '#{ctor_name}'"
        end
    end
  end

  defp run([{:match_kw, _, pos} | _], [top | _], _env) do
    raise Cairn.RuntimeError,
      "MATCH at word #{pos + 1}: expected a variant on the stack, got #{inspect(top)}"
  end

  defp run([{:match_kw, _, pos} | _], [], _env) do
    raise Cairn.RuntimeError, "MATCH at word #{pos + 1}: empty stack"
  end

  # RECEIVE — blocks for one message and dispatches by constructor.
  defp run([{:receive_kw, _, pos} | rest], stack, env) do
    case Process.get(:cairn_self_type) do
      {:user_type, type_name} ->
        {arms, remaining} = collect_match_arms(rest, [], 0)

        message =
          receive do
            msg -> msg
          end

        {field_stack, branch_tokens} = resolve_receive_branch!(message, type_name, arms, pos)
        {stack, env} = run(branch_tokens, field_stack ++ stack, env)
        run(remaining, stack, env)

      _ ->
        run_receive_explicit(rest, stack, env, pos)
    end
  end

  # Identifiers — look up in environment
  defp run([{:ident, name, pos} | rest], stack, env) do
    case Map.get(env, name) do
      nil ->
        raise Cairn.RuntimeError, "undefined '#{name}' at word #{pos + 1}"

      {:let_binding, value} ->
        run(rest, [value | stack], env)

      %Cairn.Types.Function{} = func ->
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
    raise Cairn.RuntimeError, "IF at word #{pos + 1} requires a boolean on the stack"
  end

  # Block literals: { body } — pushes a block (token list) onto the stack
  defp run([{:block_open, _, _} | rest], stack, env) do
    {block_tokens, remaining} = collect_block(rest, 0, [])
    run(remaining, [{:block, block_tokens, env} | stack], env)
  end

  defp run([{type, val, pos} | _], _stack, _env) do
    raise Cairn.RuntimeError, "unexpected #{type} '#{inspect(val)}' at word #{pos + 1}"
  end

  defp spawn_actor(kind, pos, type_token, rest, stack, env) do
    {block_tokens, remaining} = collect_block(rest, 0, [])
    msg_type = resolve_runtime_type!(type_token, env, pos)

    spawn_fn = fn ->
      self_ref = {:pid, msg_type, self()}
      Process.put(:cairn_self_type, msg_type)

      try do
        {_child_stack, _child_env} = run(block_tokens, [self_ref], env)
      after
        Process.delete(:cairn_self_type)
      end
    end

    pid =
      case kind do
        :spawn -> spawn(spawn_fn)
        :spawn_link -> spawn_link(spawn_fn)
      end

    run(remaining, [{:pid, msg_type, pid} | stack], env)
  end

  defp run_receive_explicit(rest, [{:pid, {:user_type, type_name}, pid_ref} | stack], env, pos) do
    if pid_ref != self() do
      raise Cairn.RuntimeError,
        "RECEIVE at word #{pos + 1}: pid must be the current process mailbox handle"
    end

    {arms, remaining} = collect_match_arms(rest, [], 0)

    message =
      receive do
        msg -> msg
      end

    {field_stack, branch_tokens} = resolve_receive_branch!(message, type_name, arms, pos)
    {stack, env} = run(branch_tokens, field_stack ++ stack, env)
    run(remaining, stack, env)
  end

  defp run_receive_explicit(_rest, [{:pid, other, _} | _], _env, pos) do
    raise Cairn.RuntimeError,
      "RECEIVE at word #{pos + 1}: expected pid[user_type], got #{inspect({:pid, other})}"
  end

  defp run_receive_explicit(_rest, [other | _], _env, pos) do
    raise Cairn.RuntimeError, "RECEIVE at word #{pos + 1}: expected pid on stack, got #{inspect(other)}"
  end

  defp run_receive_explicit(_rest, [], _env, pos) do
    raise Cairn.RuntimeError, "RECEIVE at word #{pos + 1}: empty stack"
  end

  defp normalize_down_reason(:normal), do: "normal"
  defp normalize_down_reason(:noproc), do: "noproc"
  defp normalize_down_reason(reason) when is_binary(reason), do: reason
  defp normalize_down_reason(reason), do: inspect(reason)

  defp run_http_serve(rest, pos, block_tokens, block_env, bind_host, port, options, stack, env) do
    handler_env = Map.merge(block_env, env)

    Cairn.HTTP.serve(bind_host, port, options, fn method, path, query, form, headers, cookies ->
      case eval_tokens(block_tokens, [path, method, query, form, headers, cookies], handler_env) do
        [body, response_headers, status]
            when is_binary(body) and is_map(response_headers) and is_integer(status) ->
          {status, response_headers, body}

        [body, content_type, status] when is_binary(body) and is_binary(content_type) and is_integer(status) ->
          {status, content_type, body}

        other ->
          raise Cairn.RuntimeError,
            "HTTP_SERVE at word #{pos + 1}: handler must leave exactly [body, content_type|headers, status], got #{inspect(other)}"
      end
    end)

    run(rest, stack, env)
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
        raise Cairn.RuntimeError, "unknown constructor '#{name}' at word #{pos + 1}"

      {type_name, field_types} ->
        arity = length(field_types)
        {fields, remaining_items} = Enum.split(items, arity)
        variant = {:variant, type_name, name, fields}
        collect_list_tokens(rest, [variant | remaining_items], env)
    end
  end

  defp collect_list_tokens([], _items, _env) do
    raise Cairn.RuntimeError, "unmatched ["
  end

  # Collect tokens inside M[ ], building key-value pairs
  defp collect_map_tokens([{:list_close, _, _} | rest], items, _env) do
    pairs = items |> Enum.reverse() |> Enum.chunk_every(2)

    map =
      Map.new(pairs, fn
        [k, v] -> {k, v}
        [_] -> raise Cairn.RuntimeError, "M[ requires even number of elements (key-value pairs)"
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
        raise Cairn.RuntimeError, "unknown constructor '#{name}' at word #{pos + 1}"

      {type_name, field_types} ->
        arity = length(field_types)
        {fields, remaining_items} = Enum.split(items, arity)
        variant = {:variant, type_name, name, fields}
        collect_map_tokens(rest, [variant | remaining_items], env)
    end
  end

  defp collect_map_tokens([], _items, _env) do
    raise Cairn.RuntimeError, "unmatched M["
  end

  # Collect tokens inside { }, handling nesting
  defp collect_block([], _depth, _acc) do
    raise Cairn.RuntimeError, "unmatched {"
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
    raise Cairn.RuntimeError, "IF without matching END"
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
    raise Cairn.RuntimeError, "IF/ELSE without matching END"
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
    raise Cairn.RuntimeError, "nested MATCH not supported in MATCH arms"
  end

  defp collect_match_arms([], _arms, _depth) do
    raise Cairn.RuntimeError, "MATCH without matching END"
  end

  defp collect_match_arms([token | _], _arms, _depth) do
    raise Cairn.RuntimeError, "unexpected token in MATCH arm: #{inspect(token)}"
  end

  # --- Function calls ---

  @doc """
  Executes a function call: pops args, evaluates body, checks contract, pushes result.
  """
  def eval_function_call(%Cairn.Types.Function{} = func, stack, env) do
    {args, rest} = pop_args(stack, length(func.param_types))
    param_types = erase_type_vars(func.param_types)
    return_types = erase_type_vars(func.return_types)

    # Check arg types against declared param_types
    check_arg_types(func.name, param_types, args)

    if func.pre_condition do
      check_pre(func, args, env)
    end

    result_stack = eval_tokens(func.body, args, env)

    if func.post_condition do
      check_post(func, result_stack, env)
    end

    check_return_types(func.name, return_types, result_stack)

    result_stack ++ rest
  end

  defp pop_args(stack, 0), do: {[], stack}

  defp pop_args(stack, n) when length(stack) >= n do
    Enum.split(stack, n)
  end

  defp pop_args(stack, n) do
    raise Cairn.RuntimeError, "stack underflow: need #{n} args, have #{length(stack)}"
  end

  defp check_arg_types(func_name, param_types, args) do
    param_types
    |> Enum.zip(args)
    |> Enum.each(fn {type, value} ->
      unless matches_type?(value, type) do
        raise Cairn.RuntimeError,
          "type error in '#{func_name}': expected #{format_type(type)}, got #{inspect(value)}"
      end
    end)
  end

  defp matches_type?(_, :any), do: true
  defp matches_type?(_, {:type_var, _}), do: true
  defp matches_type?(v, :int) when is_integer(v), do: true
  defp matches_type?(v, :float) when is_float(v), do: true
  defp matches_type?(v, :bool) when is_boolean(v), do: true
  defp matches_type?(v, :str) when is_binary(v), do: true
  defp matches_type?(v, {:list, _}) when is_list(v), do: true
  defp matches_type?(v, {:map, _, _}) when is_map(v), do: true
  defp matches_type?({:block, _tokens, _env}, {:block, _}), do: true
  defp matches_type?({:pid, inner, _pid}, {:pid, expected_inner}), do: type_descriptor_matches?(inner, expected_inner)
  defp matches_type?({:pid, inner}, {:pid, expected_inner}), do: type_descriptor_matches?(inner, expected_inner)
  defp matches_type?({:monitor, inner, _pid, _ref}, {:monitor, expected_inner}),
    do: type_descriptor_matches?(inner, expected_inner)
  defp matches_type?({:variant, type_name, _, _}, {:user_type, type_name}), do: true
  defp matches_type?(_, _), do: false

  defp format_type({:list, inner}), do: "[#{inner}]"
  defp format_type({:map, k, v}), do: "map[#{k} #{v}]"
  defp format_type({:pid, inner}), do: "pid[#{format_type(inner)}]"
  defp format_type({:monitor, inner}), do: "monitor[#{format_type(inner)}]"
  defp format_type({:user_type, name}), do: name
  defp format_type({:type_var, name}), do: name
  defp format_type(type), do: to_string(type)

  defp type_descriptor_matches?(:any, _), do: true
  defp type_descriptor_matches?(a, a), do: true
  defp type_descriptor_matches?({:list, a}, {:list, b}), do: type_descriptor_matches?(a, b)

  defp type_descriptor_matches?({:map, ak, av}, {:map, bk, bv}) do
    type_descriptor_matches?(ak, bk) and type_descriptor_matches?(av, bv)
  end

  defp type_descriptor_matches?({:pid, a}, {:pid, b}), do: type_descriptor_matches?(a, b)
  defp type_descriptor_matches?({:monitor, a}, {:monitor, b}), do: type_descriptor_matches?(a, b)
  defp type_descriptor_matches?(_, :any), do: true
  defp type_descriptor_matches?(_, _), do: false

  defp resolve_runtime_type!({:type, type, _}, _env, _pos), do: type

  defp resolve_runtime_type!({:ident, name, _}, env, pos) do
    types = Map.get(env, "__types__", %{})

    if Map.has_key?(types, name) do
      {:user_type, name}
    else
      raise Cairn.RuntimeError, "SPAWN at word #{pos + 1}: unknown message type '#{name}'"
    end
  end

  defp resolve_runtime_type!(_token, _env, pos) do
    raise Cairn.RuntimeError, "SPAWN at word #{pos + 1}: invalid message type"
  end

  defp resolve_receive_branch!({:variant, type_name, ctor_name, fields}, expected_type, arms, pos)
       when type_name == expected_type do
    case Enum.find(arms, fn {arm_ctor, _} -> arm_ctor == ctor_name end) do
      {_ctor, arm_tokens} ->
        {Enum.reverse(fields), arm_tokens}

      nil ->
        case Enum.find(arms, fn {arm_ctor, _} -> arm_ctor == :wildcard end) do
          {:wildcard, arm_tokens} -> {[], arm_tokens}
          nil ->
            raise Cairn.RuntimeError,
              "RECEIVE at word #{pos + 1}: no arm for constructor '#{ctor_name}'"
        end
    end
  end

  defp resolve_receive_branch!({:variant, other_type, _ctor, _fields}, expected_type, _arms, pos) do
    raise Cairn.RuntimeError,
      "RECEIVE at word #{pos + 1}: expected message of type #{expected_type}, got #{other_type}"
  end

  defp resolve_receive_branch!(other, _expected_type, arms, pos) do
    case Enum.find(arms, fn {arm_ctor, _} -> arm_ctor == :wildcard end) do
      {:wildcard, arm_tokens} -> {[], arm_tokens}
      nil ->
        raise Cairn.RuntimeError,
          "RECEIVE at word #{pos + 1}: expected variant message, got #{inspect(other)}"
    end
  end

  defp check_pre(func, args, env) do
    check_stack = eval_tokens(func.pre_condition, args, env)

    case check_stack do
      [true | _] ->
        :ok

      [false | _] ->
        raise Cairn.ContractError,
          message: "PRE condition failed for #{func.name}",
          function_name: func.name,
          stack: args

      other ->
        raise Cairn.ContractError,
          message: "PRE condition for #{func.name} did not return bool, got: #{inspect(other)}",
          function_name: func.name,
          stack: args
    end
  end

  defp check_return_types(func_name, [:void], result_stack) do
    if result_stack != [] do
      raise Cairn.RuntimeError,
        "type error in '#{func_name}': declared -> void but left #{length(result_stack)} value(s) on stack"
    end
  end

  defp check_return_types(func_name, return_types, result_stack) do
    expected = length(return_types)
    actual = length(result_stack)

    if actual != expected do
      raise Cairn.RuntimeError,
        "type error in '#{func_name}': declared -> #{format_return_types(return_types)} " <>
          "(#{expected} value(s)) but got #{actual}"
    end

    return_types
    |> Enum.zip(result_stack)
    |> Enum.each(fn {type, value} ->
      unless matches_type?(value, type) do
        raise Cairn.RuntimeError,
          "type error in '#{func_name}': expected return type #{format_type(type)}, got #{inspect(value)}"
      end
    end)
  end

  defp format_return_types(types), do: Enum.map_join(types, " ", &format_type/1)

  defp erase_type_vars(types) when is_list(types), do: Enum.map(types, &erase_type_vars/1)
  defp erase_type_vars({:type_var, _}), do: :any
  defp erase_type_vars({:list, inner}), do: {:list, erase_type_vars(inner)}
  defp erase_type_vars({:map, key_type, value_type}), do: {:map, erase_type_vars(key_type), erase_type_vars(value_type)}
  defp erase_type_vars({:pid, inner}), do: {:pid, erase_type_vars(inner)}
  defp erase_type_vars({:monitor, inner}), do: {:monitor, erase_type_vars(inner)}
  defp erase_type_vars({:block, {:returns, inner}}), do: {:block, {:returns, erase_type_vars(inner)}}
  defp erase_type_vars(other), do: other

  defp check_post(func, result_stack, env) do
    check_stack = eval_tokens(func.post_condition, result_stack, env)

    case check_stack do
      [true | _] ->
        :ok

      [false | _] ->
        raise Cairn.ContractError,
          message: "POST condition failed for #{func.name}",
          function_name: func.name,
          stack: result_stack

      other ->
        raise Cairn.ContractError,
          message: "POST condition for #{func.name} did not return bool, got: #{inspect(other)}",
          function_name: func.name,
          stack: result_stack
    end
  end

  defp run_with_state(rest, pos, block_tokens, block_env, state_value, stack, env) do
    merged_env =
      block_env
      |> Map.merge(env)
      |> Map.put(:__cairn_state__, state_value)

    {block_stack, block_env_after} = run(block_tokens, [], merged_env)

    if block_stack != [] do
      raise Cairn.RuntimeError,
        "WITH_STATE at word #{pos + 1}: block must leave no visible values, got #{inspect(block_stack)}"
    end

    final_state = Map.fetch!(block_env_after, :__cairn_state__)
    run(rest, [final_state | stack], env)
  end

  defp run_repeat(_rest, pos, _block_tokens, _block_env, count, _stack, _env) when count < 0 do
    raise Cairn.RuntimeError, "REPEAT at word #{pos + 1}: count must be >= 0, got #{count}"
  end

  defp run_repeat(rest, _pos, _block_tokens, _block_env, 0, stack, env) do
    run(rest, stack, env)
  end

  defp run_repeat(rest, _pos, block_tokens, block_env, count, stack, env) do
    merged_env = Map.merge(block_env, env)

    {stack, env} =
      Enum.reduce(1..count, {stack, env}, fn _, {iter_stack, iter_env} ->
        iteration_env = Map.merge(merged_env, iter_env)
        {next_stack, result_env} = run(block_tokens, iter_stack, iteration_env)

        next_env =
          case Map.fetch(result_env, :__cairn_state__) do
            {:ok, state_value} -> Map.put(iter_env, :__cairn_state__, state_value)
            :error -> iter_env
          end

        {next_stack, next_env}
      end)

    run(rest, stack, env)
  end
end
