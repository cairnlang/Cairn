defmodule Cairn.Parser do
  @moduledoc """
  Parses a token list into Cairn function definitions and expressions.

  Top-level constructs:
  1. Expressions — postfix sequences of literals, identifiers, and operators.
  2. Function definitions — `DEF name : type -> type [EFFECT kind] body [POST condition] END`
  3. TYPE declarations — `TYPE name = Ctor1 [types...] | Ctor2 [types...] ...`
  4. VERIFY/PROVE statements
  5. TEST blocks — `TEST "name" ... END`

  POST comes after the body, before END.
  """

  alias Cairn.Types.{Function, ProtocolDef, TypeDef}

  @doc """
  Parses a token list into a list of parsed items.
  Returns `{:ok, items}` where each item is a `%Function{}`, `%TypeDef{}`, or `{:expr, tokens}`.
  """
  @spec parse([Cairn.Types.token()], MapSet.t(String.t())) ::
          {:ok, [Function.t() | TypeDef.t() | ProtocolDef.t() | {:expr, [Cairn.Types.token()]} | {:test, String.t(), [Cairn.Types.token()]}]}
          | {:error, String.t()}
  def parse(tokens, external_known_types \\ MapSet.new()) do
    known_types =
      external_known_types
      |> MapSet.union(collect_declared_type_names(tokens))

    parse_top(tokens, [], known_types)
  end

  defp parse_top([], acc, _known_types), do: {:ok, Enum.reverse(acc)}

  defp parse_top([{:fn_def, _, _} | rest], acc, known_types) do
    case parse_function(rest, known_types) do
      {:ok, func, remaining} -> parse_top(remaining, [func | acc], known_types)
      {:error, _} = err -> err
    end
  end

  defp parse_top([{:verify_kw, _, _} | rest], acc, known_types) do
    case parse_verify(rest) do
      {:ok, verify_item, remaining} -> parse_top(remaining, [verify_item | acc], known_types)
      {:error, _} = err -> err
    end
  end

  defp parse_top([{:prove_kw, _, _} | rest], acc, known_types) do
    case parse_prove(rest) do
      {:ok, prove_item, remaining} -> parse_top(remaining, [prove_item | acc], known_types)
      {:error, _} = err -> err
    end
  end

  defp parse_top([{:test_kw, _, _} | rest], acc, known_types) do
    case parse_test(rest) do
      {:ok, test_item, remaining} -> parse_top(remaining, [test_item | acc], known_types)
      {:error, _} = err -> err
    end
  end

  defp parse_top([{:import_kw, _, _} | rest], acc, known_types) do
    case parse_import(rest) do
      {:ok, import_item, remaining} -> parse_top(remaining, [import_item | acc], known_types)
      {:error, _} = err -> err
    end
  end

  defp parse_top([{:type_kw, _, _} | rest], acc, known_types) do
    case parse_type_def(rest) do
      {:ok, typedef, remaining} -> parse_top(remaining, [typedef | acc], known_types)
      {:error, _} = err -> err
    end
  end

  defp parse_top([{:protocol_kw, _, _} | rest], acc, known_types) do
    case parse_protocol_def(rest) do
      {:ok, protocol, remaining} -> parse_top(remaining, [protocol | acc], known_types)
      {:error, _} = err -> err
    end
  end

  defp parse_top(tokens, acc, known_types) do
    {expr_tokens, remaining} = Enum.split_while(tokens, fn {type, _, _} ->
      type not in [:fn_def, :verify_kw, :prove_kw, :test_kw, :import_kw, :type_kw, :protocol_kw]
    end)

    if expr_tokens == [] do
      {:error, "unexpected token: #{inspect(hd(remaining))}"}
    else
      parse_top(remaining, [{:expr, expr_tokens} | acc], known_types)
    end
  end

  defp parse_function(tokens, known_types) do
    with {:ok, name, type_params, rest} <- parse_function_name(tokens),
         {:ok, _colon, rest} <- expect(:colon, rest),
         {:ok, param_types, return_types, rest} <- parse_type_signature(rest, known_types, MapSet.new(type_params)),
         {:ok, effect, rest} <- parse_effect(rest),
         {:ok, pre_condition, post_condition, body, rest} <- parse_body(rest) do
      {:ok,
       %Function{
         name: name,
         type_params: type_params,
         param_types: param_types,
         return_types: return_types,
         effect: effect,
         body: body,
         pre_condition: pre_condition,
         post_condition: post_condition
       }, rest}
    end
  end

  defp parse_function_name([{:ident, name, _} | rest]), do: {:ok, name, [], rest}
  defp parse_function_name([{:generic_ident, {name, type_params}, _} | rest]), do: {:ok, name, type_params, rest}
  defp parse_function_name(_), do: {:error, "expected function name after DEF"}

  defp parse_effect([{:effect_kw, _, _}, {:ident, name, _} | rest]) do
    case name do
      "pure" -> {:ok, :pure, rest}
      "io" -> {:ok, :io, rest}
      "db" -> {:ok, :db, rest}
      "http" -> {:ok, :http, rest}
      _ -> {:error, "invalid EFFECT #{name}; expected pure, io, db, or http"}
    end
  end

  defp parse_effect([{:effect_kw, _, _} | _]) do
    {:error, "EFFECT requires one of: pure, io, db, http"}
  end

  defp parse_effect(tokens), do: {:ok, :io, tokens}

  # TYPE name = Ctor1 type1 type2 | Ctor2 type3 | Ctor3
  defp parse_type_def([type_name_tok, {:equals, _, _} | rest])
       when elem(type_name_tok, 0) in [:ident, :generic_ident] do
    {name, type_params} =
      case type_name_tok do
        {:ident, name, _} -> {name, []}
        {:generic_ident, {name, type_params}, _} -> {name, type_params}
      end

    case collect_variants(rest, %{}, nil, [], MapSet.new(type_params)) do
      {:ok, variants, remaining} ->
        {:ok, %TypeDef{name: name, type_params: type_params, variants: variants}, remaining}
      {:error, _} = err -> err
    end
  end

  defp parse_type_def(_) do
    {:error, "TYPE requires: TYPE name = Constructor [types...] | ..."}
  end

  # PROTOCOL name = SEND Ctor RECV Ctor ... END
  defp parse_protocol_def([{:ident, name, _}, {:equals, _, _} | rest]) do
    case collect_protocol_steps(rest, []) do
      {:ok, steps, remaining} ->
        {:ok, %ProtocolDef{name: name, steps: steps}, remaining}

      {:error, _} = err ->
        err
    end
  end

  defp parse_protocol_def(_) do
    {:error, "PROTOCOL requires: PROTOCOL name = SEND Ctor RECV Ctor ... END"}
  end

  defp collect_protocol_steps([{:fn_end, _, _} | rest], acc) do
    {:ok, Enum.reverse(acc), rest}
  end

  defp collect_protocol_steps([{:op, :send, _}, {:constructor, ctor_name, _} | rest], acc) do
    collect_protocol_steps(rest, [{:send, ctor_name} | acc])
  end

  defp collect_protocol_steps([{:recv_kw, _, _}, {:constructor, ctor_name, _} | rest], acc) do
    collect_protocol_steps(rest, [{:recv, ctor_name} | acc])
  end

  defp collect_protocol_steps([], _acc) do
    {:error, "PROTOCOL requires END"}
  end

  defp collect_protocol_steps([token | _], _acc) do
    {:error, "invalid PROTOCOL step near #{inspect(token)}"}
  end

  # Collect variant declarations: Ctor1 type... | Ctor2 type... | ...
  # Terminates when we see a top-level keyword or end of tokens
  defp collect_variants([], variants, current_ctor, current_types, _type_params) do
    variants = finish_variant(variants, current_ctor, current_types)
    {:ok, variants, []}
  end

  defp collect_variants([{:pipe, _, _} | rest], variants, current_ctor, current_types, type_params) do
    variants = finish_variant(variants, current_ctor, current_types)
    collect_variants(rest, variants, nil, [], type_params)
  end

  defp collect_variants([{:constructor, ctor_name, _} | rest], variants, current_ctor, current_types, type_params) do
    cond do
      not is_nil(current_ctor) and MapSet.member?(type_params, ctor_name) ->
        collect_variants(rest, variants, current_ctor, current_types ++ [{:type_var, ctor_name}], type_params)

      true ->
        # If we already have a current constructor without a pipe, it was a nullary ctor
        variants = finish_variant(variants, current_ctor, current_types)
        collect_variants(rest, variants, ctor_name, [], type_params)
    end
  end

  defp collect_variants([{:type, type_val, _} | rest], variants, current_ctor, current_types, type_params)
       when not is_nil(current_ctor) do
    collect_variants(rest, variants, current_ctor, current_types ++ [type_val], type_params)
  end

  # User-defined type names as variant field types (e.g. `Node tree tree`, `JArr [json]` uses lexer,
  # but bare user types like `Wrap json` arrive here as :ident tokens)
  defp collect_variants([{:ident, name, _} | rest], variants, current_ctor, current_types, type_params)
       when not is_nil(current_ctor) do
    field_type =
      if MapSet.member?(type_params, name), do: {:type_var, name}, else: {:user_type, name}

    collect_variants(rest, variants, current_ctor, current_types ++ [field_type], type_params)
  end

  defp collect_variants([{:generic_ident, {name, type_args}, _} | rest], variants, current_ctor, current_types, type_params)
       when not is_nil(current_ctor) do
    collect_variants(rest, variants, current_ctor, current_types ++ [{:user_type, name, type_args}], type_params)
  end

  # Stop at any top-level boundary token
  defp collect_variants([{type, _, _} | _] = rest, variants, current_ctor, current_types, _type_params)
       when type in [:fn_def, :verify_kw, :prove_kw, :test_kw, :type_kw, :protocol_kw] do
    variants = finish_variant(variants, current_ctor, current_types)
    {:ok, variants, rest}
  end

  # Any other token terminates the TYPE declaration — start of next expression
  defp collect_variants(tokens, variants, current_ctor, current_types, _type_params) do
    variants = finish_variant(variants, current_ctor, current_types)
    {:ok, variants, tokens}
  end

  defp finish_variant(variants, nil, _types), do: variants
  defp finish_variant(variants, ctor_name, types), do: Map.put(variants, ctor_name, types)

  # VERIFY name count
  defp parse_verify([{:ident, name, _}, {:int_lit, count, _} | rest]) when count > 0 do
    {:ok, {:verify, name, count}, rest}
  end

  defp parse_verify([{:ident, _name, _} | _]) do
    {:error, "VERIFY requires a function name and positive integer count"}
  end

  defp parse_verify(_) do
    {:error, "VERIFY requires a function name and positive integer count"}
  end

  # PROVE name
  defp parse_prove([{:ident, name, _} | rest]) do
    {:ok, {:prove, name}, rest}
  end

  defp parse_prove(_) do
    {:error, "PROVE requires a function name"}
  end

  # TEST "name" ... END
  defp parse_test([{:str_lit, name, _} | rest]) do
    collect_test_body(rest, [], 0, name)
  end

  defp parse_test(_) do
    {:error, "TEST requires a quoted name string"}
  end

  defp collect_test_body([], _acc, _depth, _name) do
    {:error, "expected END after TEST, got end of input"}
  end

  defp collect_test_body([{:fn_end, _, _} | rest], acc, 0, name) do
    {:ok, {:test, name, Enum.reverse(acc)}, rest}
  end

  defp collect_test_body([{:fn_end, _, _} = t | rest], acc, depth, name) do
    collect_test_body(rest, [t | acc], depth - 1, name)
  end

  defp collect_test_body([{:if_kw, _, _} = t | rest], acc, depth, name) do
    collect_test_body(rest, [t | acc], depth + 1, name)
  end

  defp collect_test_body([{:match_kw, _, _} = t | rest], acc, depth, name) do
    collect_test_body(rest, [t | acc], depth + 1, name)
  end

  defp collect_test_body([{:receive_kw, _, _} = t | rest], acc, depth, name) do
    collect_test_body(rest, [t | acc], depth + 1, name)
  end

  defp collect_test_body([token | rest], acc, depth, name) do
    collect_test_body(rest, [token | acc], depth, name)
  end

  # IMPORT "path.crn"
  defp parse_import([{:str_lit, path, _} | rest]) do
    {:ok, {:import, path}, rest}
  end

  defp parse_import(_) do
    {:error, "IMPORT requires a quoted path string, e.g. IMPORT \"lib.crn\""}
  end

  defp expect(type, [{token_type, val, _} | rest]) do
    if token_type == type do
      {:ok, val, rest}
    else
      {:error, "expected #{type}, got #{inspect(val)}"}
    end
  end

  defp expect(type, []), do: {:error, "expected #{type}, got end of input"}

  defp parse_type_signature(tokens, known_types, type_params) do
    {type_tokens, rest} = collect_type_tokens(tokens, [], known_types, type_params)

    case split_on_last_arrow(type_tokens, type_params) do
      {:ok, param_types, return_types} ->
        param_types = Enum.map(param_types, &normalize_signature_type(&1, type_params))
        return_types = Enum.map(return_types, &normalize_signature_type(&1, type_params))
        {:ok, param_types, return_types, rest}

      :error ->
        case type_tokens do
          [{:type, t, _}] ->
            {:ok, [], [t], rest}

          [{:user_type_tok, name, _}] ->
            {:ok, [], [name], rest}

          [{:type_var_tok, name, _}] ->
            {:ok, [], [{:type_var, name}], rest}

          _ ->
            {:error, "invalid type signature"}
        end
    end
  end

  defp collect_type_tokens([{:type, _, _} = t | rest], acc, known_types, type_params),
    do: collect_type_tokens(rest, [t | acc], known_types, type_params)

  defp collect_type_tokens([{:arrow, _, _} = t | rest], acc, known_types, type_params),
    do: collect_type_tokens(rest, [t | acc], known_types, type_params)

  defp collect_type_tokens([{:ident, name, pos} | rest], acc, known_types, type_params) do
    cond do
      MapSet.member?(type_params, name) ->
        collect_type_tokens(rest, [{:type_var_tok, name, pos} | acc], known_types, type_params)

      MapSet.member?(known_types, name) ->
        collect_type_tokens(rest, [{:user_type_tok, name, pos} | acc], known_types, type_params)

      true ->
        {Enum.reverse(acc), [{:ident, name, pos} | rest]}
    end
  end

  defp collect_type_tokens([{:constructor, name, pos} | rest], acc, known_types, type_params) do
    if MapSet.member?(type_params, name) do
      collect_type_tokens(rest, [{:type_var_tok, name, pos} | acc], known_types, type_params)
    else
      {Enum.reverse(acc), [{:constructor, name, pos} | rest]}
    end
  end

  defp collect_type_tokens([{:generic_ident, {name, type_args}, pos} | rest], acc, known_types, type_params) do
    cond do
      MapSet.member?(known_types, name) ->
        normalized_args = Enum.map(type_args, &normalize_signature_type(&1, type_params))
        collect_type_tokens(rest, [{:type, {:user_type, name, normalized_args}, pos} | acc], known_types, type_params)

      true ->
        {Enum.reverse(acc), [{:generic_ident, {name, type_args}, pos} | rest]}
    end
  end

  defp collect_type_tokens(rest, acc, _known_types, _type_params), do: {Enum.reverse(acc), rest}

  defp split_on_last_arrow(type_tokens, type_params) do
    indices =
      type_tokens
      |> Enum.with_index()
      |> Enum.filter(fn {{type, _, _}, _} -> type == :arrow end)
      |> Enum.map(fn {_, idx} -> idx end)

    case indices do
      [] ->
        :error

      _ ->
        last_arrow = List.last(indices)
        before = Enum.take(type_tokens, last_arrow)
        after_arrow = Enum.drop(type_tokens, last_arrow + 1)

        param_types =
          before
          |> Enum.filter(fn {type, _, _} -> type in [:type, :user_type_tok, :type_var_tok] end)
          |> Enum.map(fn
            {:type, val, _} -> normalize_signature_type(val, type_params)
            {:user_type_tok, name, _} -> normalize_signature_type({:user_type, name}, type_params)
            {:type_var_tok, name, _} -> {:type_var, name}
          end)

        case after_arrow do
          [] ->
            :error

          types ->
            return_types =
              Enum.map(types, fn
                {:type, val, _} -> val
                {:user_type_tok, name, _} -> normalize_signature_type({:user_type, name}, type_params)
                {:type_var_tok, name, _} -> {:type_var, name}
                other -> throw({:bad_return_type, other})
              end)

            {:ok, param_types, return_types}
        end
    end
  end

  defp normalize_signature_type(name, type_params) when is_binary(name) do
    cond do
      name in ["int", "float", "bool", "str", "any", "void"] ->
        String.to_atom(name)

      MapSet.member?(type_params, name) ->
        {:type_var, name}

      true ->
        name
    end
  end

  defp normalize_signature_type({:user_type, name}, type_params) do
    if MapSet.member?(type_params, name) do
      {:type_var, name}
    else
      name
    end
  end

  defp normalize_signature_type({:user_type, name, args}, type_params) do
    {:user_type, name, Enum.map(args, &normalize_signature_type(&1, type_params))}
  end

  defp normalize_signature_type({:list, inner}, type_params),
    do: {:list, normalize_signature_type(inner, type_params)}

  defp normalize_signature_type({:tuple, elems}, type_params),
    do: {:tuple, Enum.map(elems, &normalize_signature_type(&1, type_params))}

  defp normalize_signature_type({:map, key_type, value_type}, type_params) do
    {:map, normalize_signature_type(key_type, type_params), normalize_signature_type(value_type, type_params)}
  end

  defp normalize_signature_type({:pid, inner}, type_params),
    do: {:pid, normalize_signature_type(inner, type_params)}

  defp normalize_signature_type({:monitor, inner}, type_params),
    do: {:monitor, normalize_signature_type(inner, type_params)}

  defp normalize_signature_type({:block, {:returns, inner}}, type_params),
    do: {:block, {:returns, normalize_signature_type(inner, type_params)}}

  defp normalize_signature_type(other, _type_params), do: other

  # Collects body tokens until END, splitting on PRE/POST if present.
  # Tracks IF and MATCH nesting depth so inner IF...END / MATCH...END
  # blocks don't prematurely close the function.
  # Syntax: [PRE cond] body [POST cond] END
  defp parse_body([{:pre, _, _} | rest]) do
    collect_pre(rest, [], 0)
  end

  defp parse_body(tokens) do
    case collect_body(tokens, [], nil, 0) do
      {:ok, post, body, rest} -> {:ok, nil, post, body, rest}
      {:error, _} = err -> err
    end
  end

  defp collect_pre([{:block_open, _, _} | _] = tokens, _acc, _depth) do
    {block_tokens, remaining} = collect_block_tokens(tokens)
    case collect_body(remaining, [], nil, 0) do
      {:ok, post, body, rest} -> {:ok, block_tokens, post, body, rest}
      {:error, _} = err -> err
    end
  end

  defp collect_pre(tokens, _acc, _depth) do
    {:error, "PRE must be followed by a block { ... }, got: #{inspect(hd(tokens))}"}
  end

  defp collect_block_tokens([{:block_open, _, _} | rest]) do
    do_collect_block(rest, 0, [])
  end

  defp do_collect_block([{:block_close, _, _} | rest], 0, acc) do
    {Enum.reverse(acc), rest}
  end

  defp do_collect_block([{:block_open, _, _} = t | rest], depth, acc) do
    do_collect_block(rest, depth + 1, [t | acc])
  end

  defp do_collect_block([{:block_close, _, _} = t | rest], depth, acc) when depth > 0 do
    do_collect_block(rest, depth - 1, [t | acc])
  end

  defp do_collect_block([t | rest], depth, acc) do
    do_collect_block(rest, depth, [t | acc])
  end

  defp do_collect_block([], _depth, _acc) do
    raise Cairn.RuntimeError, "unmatched { in PRE condition"
  end

  defp collect_body([], _body_acc, _post_acc, _depth) do
    {:error, "expected END, got end of input"}
  end

  # END at depth 0 = function end
  defp collect_body([{:fn_end, _, _} | rest], body_acc, post_acc, 0) do
    body = Enum.reverse(body_acc)
    post = if post_acc, do: Enum.reverse(post_acc), else: nil
    {:ok, post, body, rest}
  end

  # END at depth > 0 = belongs to an inner IF or MATCH
  defp collect_body([{:fn_end, _, _} = t | rest], body_acc, post_acc, depth) do
    collect_body(rest, [t | body_acc], post_acc, depth - 1)
  end

  # IF increases nesting depth
  defp collect_body([{:if_kw, _, _} = t | rest], body_acc, post_acc, depth) do
    collect_body(rest, [t | body_acc], post_acc, depth + 1)
  end

  # MATCH increases nesting depth
  defp collect_body([{:match_kw, _, _} = t | rest], body_acc, post_acc, depth) do
    collect_body(rest, [t | body_acc], post_acc, depth + 1)
  end

  # RECEIVE increases nesting depth
  defp collect_body([{:receive_kw, _, _} = t | rest], body_acc, post_acc, depth) do
    collect_body(rest, [t | body_acc], post_acc, depth + 1)
  end

  # POST at depth 0 = start of postcondition
  defp collect_body([{:post, _, _} | rest], body_acc, _post_acc, 0) do
    collect_post(rest, Enum.reverse(body_acc), [], 0)
  end

  defp collect_body([token | rest], body_acc, post_acc, depth) do
    collect_body(rest, [token | body_acc], post_acc, depth)
  end

  defp collect_post([], _body, _post_acc, _depth) do
    {:error, "expected END after POST condition, got end of input"}
  end

  defp collect_post([{:fn_end, _, _} | rest], body, post_acc, 0) do
    {:ok, Enum.reverse(post_acc), body, rest}
  end

  defp collect_post([{:fn_end, _, _} = t | rest], body, post_acc, depth) do
    collect_post(rest, body, [t | post_acc], depth - 1)
  end

  defp collect_post([{:if_kw, _, _} = t | rest], body, post_acc, depth) do
    collect_post(rest, body, [t | post_acc], depth + 1)
  end

  defp collect_post([{:match_kw, _, _} = t | rest], body, post_acc, depth) do
    collect_post(rest, body, [t | post_acc], depth + 1)
  end

  defp collect_post([{:receive_kw, _, _} = t | rest], body, post_acc, depth) do
    collect_post(rest, body, [t | post_acc], depth + 1)
  end

  defp collect_post([token | rest], body, post_acc, depth) do
    collect_post(rest, body, [token | post_acc], depth)
  end

  # Pre-scan the file for local TYPE declarations so function signatures can
  # reference types before their declaration order.
  defp collect_declared_type_names(tokens) do
    tokens
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce(MapSet.new(["result"]), fn
      [{:type_kw, _, _}, {:ident, name, _}], acc -> MapSet.put(acc, name)
      [{:type_kw, _, _}, {:generic_ident, {name, _}, _}], acc -> MapSet.put(acc, name)
      _, acc -> acc
    end)
  end
end
