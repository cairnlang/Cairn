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

  defp parse_top(tokens, acc) do
    {expr_tokens, remaining} = Enum.split_while(tokens, fn {type, _, _} -> type != :fn_def end)

    if expr_tokens == [] do
      {:error, "unexpected token: #{inspect(hd(remaining))}"}
    else
      parse_top(remaining, [{:expr, expr_tokens} | acc])
    end
  end

  defp parse_function(tokens) do
    with {:ok, name, rest} <- expect_ident(tokens),
         {:ok, _colon, rest} <- expect(:colon, rest),
         {:ok, param_types, return_type, rest} <- parse_type_signature(rest),
         {:ok, post_condition, body, rest} <- parse_body(rest) do
      {:ok,
       %Function{
         name: name,
         param_types: param_types,
         return_type: return_type,
         body: body,
         post_condition: post_condition
       }, rest}
    end
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
      {:ok, param_types, return_type} ->
        {:ok, param_types, return_type, rest}

      :error ->
        case type_tokens do
          [{:type, t, _}] -> {:ok, [], t, rest}
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
          [{:type, return_type, _}] -> {:ok, param_types, return_type}
          _ -> :error
        end
    end
  end

  # Collects body tokens until END, splitting on POST if present.
  # Tracks IF nesting depth so inner IF...END blocks don't close the function.
  # Syntax: body... [POST condition...] END
  defp parse_body(tokens) do
    collect_body(tokens, [], nil, 0)
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
