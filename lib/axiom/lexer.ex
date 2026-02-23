defmodule Axiom.Lexer do
  @moduledoc """
  Tokenizes Axiom source text into a flat token list.

  Axiom tokens are space-delimited. No whitespace sensitivity.
  """

  @operators ~w(ADD SUB MUL DIV MOD EQ NEQ GT LT GTE LTE AND OR NOT
                DUP DROP SWAP OVER ROT
                FILTER MAP REDUCE SUM LEN HEAD TAIL CONS CONCAT
                SORT REVERSE MIN MAX
                SQ ABS NEG
                TIMES WHILE APPLY
                RANGE PRINT SAY
                ARGV READ_FILE WRITE_FILE READ_LINE)

  @type_names ~w(int float bool)

  @doc """
  Tokenizes a source string into a list of `{type, value, position}` tuples.
  """
  @spec tokenize(String.t()) :: {:ok, [Axiom.Types.token()]} | {:error, String.t()}
  def tokenize(source) do
    source
    |> strip_comments()
    |> scan_words()
    |> Enum.reject(&(&1 == ""))
    |> tokenize_words([], 0)
  end

  # Strip # comments, but not inside quoted strings
  defp strip_comments(source) do
    source
    |> String.split("\n")
    |> Enum.map(fn line -> strip_line_comment(line, false, []) end)
    |> Enum.join("\n")
  end

  defp strip_line_comment(<<>>, _in_str, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()
  defp strip_line_comment(<<?", rest::binary>>, false, acc), do: strip_line_comment(rest, true, [?" | acc])
  defp strip_line_comment(<<?", rest::binary>>, true, acc), do: strip_line_comment(rest, false, [?" | acc])
  defp strip_line_comment(<<?#, _::binary>>, false, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()
  defp strip_line_comment(<<c, rest::binary>>, in_str, acc), do: strip_line_comment(rest, in_str, [c | acc])

  # Scan words respecting quoted strings — "hello world" stays as one token
  defp scan_words(source) do
    Regex.scan(~r/"[^"]*"|[^\s]+/, source)
    |> Enum.map(fn [match] -> match end)
  end

  defp tokenize_words([], acc, _pos), do: {:ok, Enum.reverse(acc)}

  defp tokenize_words([word | rest], acc, pos) do
    case classify(word) do
      {:ok, token} ->
        tokenize_words(rest, [{elem(token, 0), elem(token, 1), pos} | acc], pos + 1)

      {:error, msg} ->
        {:error, "at word #{pos + 1}: #{msg}"}
    end
  end

  defp classify("["), do: {:ok, {:list_open, "["}}
  defp classify("]"), do: {:ok, {:list_close, "]"}}
  defp classify("{"), do: {:ok, {:block_open, "{"}}
  defp classify("}"), do: {:ok, {:block_close, "}"}}
  defp classify(":"), do: {:ok, {:colon, ":"}}
  defp classify("->"), do: {:ok, {:arrow, "->"}}
  defp classify("DEF"), do: {:ok, {:fn_def, "DEF"}}
  defp classify("END"), do: {:ok, {:fn_end, "END"}}
  defp classify("POST"), do: {:ok, {:post, "POST"}}
  defp classify("PRE"), do: {:ok, {:pre, "PRE"}}
  defp classify("IF"), do: {:ok, {:if_kw, "IF"}}
  defp classify("ELSE"), do: {:ok, {:else_kw, "ELSE"}}
  defp classify("T"), do: {:ok, {:bool_lit, true}}
  defp classify("F"), do: {:ok, {:bool_lit, false}}

  defp classify(word) do
    cond do
      # String literal: "..."
      String.starts_with?(word, "\"") and String.ends_with?(word, "\"") ->
        {:ok, {:str_lit, String.slice(word, 1..-2)}}

      word in @operators ->
        {:ok, {:op, String.to_atom(String.downcase(word))}}

      word in @type_names ->
        {:ok, {:type, String.to_atom(word)}}

      # list type like [int] or [float]
      Regex.match?(~r/^\[.+\]$/, word) ->
        inner = String.slice(word, 1..-2)
        if inner in @type_names do
          {:ok, {:type, {:list, String.to_atom(inner)}}}
        else
          {:error, "unknown list type: #{word}"}
        end

      # float literal
      Regex.match?(~r/^-?\d+\.\d+$/, word) ->
        {:ok, {:float_lit, String.to_float(word)}}

      # int literal
      Regex.match?(~r/^-?\d+$/, word) ->
        {:ok, {:int_lit, String.to_integer(word)}}

      # identifier (short semantic tag)
      Regex.match?(~r/^[a-z_][a-z0-9_]*$/i, word) ->
        {:ok, {:ident, word}}

      true ->
        {:error, "unexpected token: #{word}"}
    end
  end
end
