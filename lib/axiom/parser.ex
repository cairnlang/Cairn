defmodule Axiom.Parser do
  @moduledoc """
  Parses a token list into Axiom function definitions and expressions.

  Two top-level constructs:
  1. Expressions — postfix sequences of literals, identifiers, and operators.
  2. Function definitions — `DEF name : type -> type body [POST condition] END`

  POST comes after the body, before END.
  """

  alias Axiom.Types.Function

  @doc """
  Parses a token list into a list of parsed items.
  Returns `{:ok, items}` where each item is a `%Function{}` or `{:expr, tokens}`.
  """
  @spec parse([Axiom.Types.token()]) :: {:ok, [Function.t() | {:expr, [Axiom.Types.token()]}]} | {:error, String.t()}
  def parse(tokens) do
    parse_top(tokens, [])
  end

  defp parse_top([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_top([{:fn_def, _, _} | rest], acc) do
    case parse_function(rest) do
      {:ok, func, remaining} -> parse_top(remaining, [func | acc])
      {:error, _} = err -> err
    end
  end

  defp parse_top([{:verify_kw, _, _} | rest], acc) do
    case parse_verify(rest) do
      {:ok, verify_item, remaining} -> parse_top(remaining, [verify_item | acc])
      {:error, _} = err -> err
    end
  end

  defp parse_top(tokens, acc) do
    {expr_tokens, remaining} = Enum.split_while(tokens, fn {type, _, _} -> type not in [:fn_def, :verify_kw] end)

    if expr_tokens == [] do
      {:error, "unexpected token: #{inspect(hd(remaining))}"}
    else
      parse_top(remaining, [{:expr, expr_tokens} | acc])
    end
  end

  defp parse_function(tokens) do
    with {:ok, name, rest} <- expect_ident(tokens),
         {:ok, _colon, rest} <- expect(:colon, rest),
         {:ok, param_types, return_types, rest} <- parse_type_signature(rest),
         {:ok, pre_condition, post_condition, body, rest} <- parse_body(rest) do
      {:ok,
       %Function{
         name: name,
         param_types: param_types,
         return_types: return_types,
         body: body,
         pre_condition: pre_condition,
         post_condition: post_condition
       }, rest}
    end
  end

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

  defp expect_ident([{:ident, name, _} | rest]), do: {:ok, name, rest}
  defp expect_ident([{_, val, _} | _]), do: {:error, "expected identifier, got #{inspect(val)}"}
  defp expect_ident([]), do: {:error, "expected identifier, got end of input"}

  defp expect(type, [{token_type, val, _} | rest]) do
    if token_type == type do
      {:ok, val, rest}
    else
      {:error, "expected #{type}, got #{inspect(val)}"}
    end
  end

  defp expect(type, []), do: {:error, "expected #{type}, got end of input"}

  defp parse_type_signature(tokens) do
    {type_tokens, rest} = collect_type_tokens(tokens, [])

    case split_on_last_arrow(type_tokens) do
      {:ok, param_types, return_types} ->
        {:ok, param_types, return_types, rest}

      :error ->
        case type_tokens do
          [{:type, t, _}] -> {:ok, [], [t], rest}
          _ -> {:error, "invalid type signature"}
        end
    end
  end

  defp collect_type_tokens([{:type, _, _} = t | rest], acc),
    do: collect_type_tokens(rest, [t | acc])

  defp collect_type_tokens([{:arrow, _, _} = t | rest], acc),
    do: collect_type_tokens(rest, [t | acc])

  defp collect_type_tokens(rest, acc), do: {Enum.reverse(acc), rest}

  defp split_on_last_arrow(type_tokens) do
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
          |> Enum.filter(fn {type, _, _} -> type == :type end)
          |> Enum.map(fn {:type, val, _} -> val end)

        case after_arrow do
          [] ->
            :error

          types ->
            return_types =
              Enum.map(types, fn
                {:type, val, _} -> val
                other -> throw({:bad_return_type, other})
              end)

            {:ok, param_types, return_types}
        end
    end
  end

  # Collects body tokens until END, splitting on PRE/POST if present.
  # Tracks IF nesting depth so inner IF...END blocks don't close the function.
  # Syntax: [PRE cond] body [POST cond] END
  defp parse_body([{:pre, _, _} | rest]) do
    # PRE comes first — collect until body starts
    collect_pre(rest, [], 0)
  end

  defp parse_body(tokens) do
    case collect_body(tokens, [], nil, 0) do
      {:ok, post, body, rest} -> {:ok, nil, post, body, rest}
      {:error, _} = err -> err
    end
  end

  # Collect PRE condition tokens until we hit the body.
  # PRE ends at the first token that isn't part of it — but since PRE
  # and body use the same token types, we need a delimiter.
  # Solution: PRE runs until we see POST, END, or a non-PRE section.
  # Simplest: PRE ends at ENDPRE... no. Let's use the same strategy as POST:
  # PRE is everything between PRE keyword and the body. We know the body
  # starts when PRE "ends" — but how?
  #
  # Pragmatic: PRE { cond_block } body POST cond END
  # If PRE is followed by a block { ... }, that's the pre condition.
  # Otherwise, collect tokens until we see a body-starting construct.
  #
  # Actually simplest: require PRE to use a block.
  # PRE { condition } body POST condition END
  defp collect_pre([{:block_open, _, _} | _] = tokens, _acc, _depth) do
    # Collect the block tokens for PRE condition
    {block_tokens, remaining} = collect_block_tokens(tokens)
    # Now parse the rest as normal body (which may have POST)
    case collect_body(remaining, [], nil, 0) do
      {:ok, post, body, rest} -> {:ok, block_tokens, post, body, rest}
      {:error, _} = err -> err
    end
  end

  defp collect_pre(tokens, _acc, _depth) do
    {:error, "PRE must be followed by a block { ... }, got: #{inspect(hd(tokens))}"}
  end

  # Collect a { ... } block, returning the inner tokens and the remaining tokens
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
    raise Axiom.RuntimeError, "unmatched { in PRE condition"
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

  # END at depth > 0 = belongs to an inner IF, keep it in body
  defp collect_body([{:fn_end, _, _} = t | rest], body_acc, post_acc, depth) do
    collect_body(rest, [t | body_acc], post_acc, depth - 1)
  end

  # IF increases nesting depth
  defp collect_body([{:if_kw, _, _} = t | rest], body_acc, post_acc, depth) do
    collect_body(rest, [t | body_acc], post_acc, depth + 1)
  end

  # POST at depth 0 = start of postcondition
  defp collect_body([{:post, _, _} | rest], body_acc, _post_acc, 0) do
    collect_post(rest, Enum.reverse(body_acc), [], 0)
  end

  defp collect_body([token | rest], body_acc, post_acc, depth) do
    collect_body(rest, [token | body_acc], post_acc, depth)
  end

  # When called without PRE, wrap result to include nil pre_condition
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

  defp collect_post([token | rest], body, post_acc, depth) do
    collect_post(rest, body, [token | post_acc], depth)
  end
end
