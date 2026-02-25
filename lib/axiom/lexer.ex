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
                ARGV READ_FILE WRITE_FILE READ_LINE
                WORDS LINES CONTAINS
                CHARS SPLIT TRIM STARTS_WITH SLICE TO_INT TO_FLOAT JOIN
                GET PUT DEL KEYS VALUES HAS MLEN MERGE)

  @type_names ~w(int float bool any void str)

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

  # Scan words respecting quoted strings and map types — "hello world" and map[str int] stay as one token
  defp scan_words(source) do
    Regex.scan(~r/map\[(?:[^\[\]]|\[[^\]]*\])*\]|"[^"]*"|[^\s]+/, source)
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
  defp classify("VERIFY"), do: {:ok, {:verify_kw, "VERIFY"}}
  defp classify("PROVE"), do: {:ok, {:prove_kw, "PROVE"}}
  defp classify("TYPE"), do: {:ok, {:type_kw, "TYPE"}}
  defp classify("MATCH"), do: {:ok, {:match_kw, "MATCH"}}
  defp classify("|"), do: {:ok, {:pipe, "|"}}
  defp classify("="), do: {:ok, {:equals, "="}}
  defp classify("T"), do: {:ok, {:bool_lit, true}}
  defp classify("F"), do: {:ok, {:bool_lit, false}}
  defp classify("[]"), do: {:ok, {:list_lit, []}}
  defp classify("M["), do: {:ok, {:map_open, "M["}}
  defp classify("M[]"), do: {:ok, {:map_lit, %{}}}

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

      # map type like map[str int]
      Regex.match?(~r/^map\[.+\s+.+\]$/, word) ->
        inner = String.slice(word, 4..-2)
        [key_str, val_str] = String.split(inner, ~r/\s+/, parts: 2)
        key_type = parse_map_inner_type(key_str)
        val_type = parse_map_inner_type(val_str)
        case {key_type, val_type} do
          {{:ok, k}, {:ok, v}} -> {:ok, {:type, {:map, k, v}}}
          _ -> {:error, "unknown map type: #{word}"}
        end

      # float literal
      Regex.match?(~r/^-?\d+\.\d+$/, word) ->
        {:ok, {:float_lit, String.to_float(word)}}

      # int literal
      Regex.match?(~r/^-?\d+$/, word) ->
        {:ok, {:int_lit, String.to_integer(word)}}

      # variant constructor — starts with uppercase, not already matched as keyword/operator
      Regex.match?(~r/^[A-Z][a-zA-Z0-9_]*$/, word) ->
        {:ok, {:constructor, word}}

      # identifier (short semantic tag)
      Regex.match?(~r/^[a-z_][a-z0-9_]*$/, word) ->
        {:ok, {:ident, word}}

      true ->
        {:error, "unexpected token: #{word}"}
    end
  end

  defp parse_map_inner_type(s) do
    if s in @type_names do
      {:ok, String.to_atom(s)}
    else
      cond do
        Regex.match?(~r/^\[.+\]$/, s) ->
          inner = String.slice(s, 1..-2)
          if inner in @type_names, do: {:ok, {:list, String.to_atom(inner)}}, else: :error

        Regex.match?(~r/^map\[.+\s+.+\]$/, s) ->
          inner = String.slice(s, 4..-2)
          [k, v] = String.split(inner, ~r/\s+/, parts: 2)
          case {parse_map_inner_type(k), parse_map_inner_type(v)} do
            {{:ok, kt}, {:ok, vt}} -> {:ok, {:map, kt, vt}}
            _ -> :error
          end

        true ->
          :error
      end
    end
  end
end
