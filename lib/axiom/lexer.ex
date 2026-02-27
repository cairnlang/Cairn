defmodule Axiom.Lexer do
  @moduledoc """
  Tokenizes Axiom source text into a flat token list.

  Axiom tokens are space-delimited. No whitespace sensitivity.
  """

  @operators ~w(ADD SUB MUL DIV MOD EQ NEQ GT LT GTE LTE AND OR NOT
                DUP DROP SWAP OVER ROT ROT4
                FILTER MAP REDUCE SUM LEN HEAD TAIL CONS CONCAT
                SORT REVERSE MIN MAX
                SQ ABS NEG
                TIMES WHILE APPLY
                RANGE PRINT SAY SELF EXIT
                SEND MONITOR AWAIT
                ARGV READ_FILE WRITE_FILE READ_FILE! WRITE_FILE! READ_LINE
                WORDS LINES CONTAINS
                CHARS SPLIT TRIM STARTS_WITH SLICE TO_INT TO_FLOAT TO_INT! TO_FLOAT! NUM_STR JOIN
                GET PUT DEL KEYS VALUES HAS MLEN MERGE PAIRS
                ASK ASK! RANDOM FMT SAID)

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
  # Escaped quote inside a string — not a string boundary
  defp strip_line_comment(<<?\\, ?", rest::binary>>, true, acc), do: strip_line_comment(rest, true, [?", ?\\ | acc])
  defp strip_line_comment(<<?", rest::binary>>, false, acc), do: strip_line_comment(rest, true, [?" | acc])
  defp strip_line_comment(<<?", rest::binary>>, true, acc), do: strip_line_comment(rest, false, [?" | acc])
  defp strip_line_comment(<<?#, _::binary>>, false, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()
  defp strip_line_comment(<<c, rest::binary>>, in_str, acc), do: strip_line_comment(rest, in_str, [c | acc])

  # Scan words respecting quoted strings (with \" escapes) and map types
  defp scan_words(source) do
    Regex.scan(~r/map\[(?:[^\[\]]|\[[^\]]*\])*\]|"(?:[^"\\]|\\.)*"|[^\s]+/, source)
    |> Enum.map(fn [match] -> match end)
  end

  # Resolve backslash escape sequences inside a string literal body
  defp unescape(<<>>), do: <<>>
  defp unescape(<<?\\, ?", rest::binary>>), do: <<?", unescape(rest)::binary>>
  defp unescape(<<?\\, ?\\, rest::binary>>), do: <<?\\, unescape(rest)::binary>>
  defp unescape(<<?\\, ?n, rest::binary>>), do: <<?\n, unescape(rest)::binary>>
  defp unescape(<<?\\, ?t, rest::binary>>), do: <<?\t, unescape(rest)::binary>>
  defp unescape(<<?\\, ?r, rest::binary>>), do: <<?\r, unescape(rest)::binary>>
  defp unescape(<<c, rest::binary>>), do: <<c, unescape(rest)::binary>>

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
  defp classify("IMPORT"), do: {:ok, {:import_kw, "IMPORT"}}
  defp classify("TYPE"), do: {:ok, {:type_kw, "TYPE"}}
  defp classify("MATCH"), do: {:ok, {:match_kw, "MATCH"}}
  defp classify("RECEIVE"), do: {:ok, {:receive_kw, "RECEIVE"}}
  defp classify("SPAWN"), do: {:ok, {:spawn_kw, "SPAWN"}}
  defp classify("SPAWN_LINK"), do: {:ok, {:spawn_link_kw, "SPAWN_LINK"}}
  defp classify("LET"), do: {:ok, {:let_kw, "LET"}}
  defp classify("|"), do: {:ok, {:pipe, "|"}}
  defp classify("="), do: {:ok, {:equals, "="}}
  defp classify("T"), do: {:ok, {:bool_lit, true}}
  defp classify("F"), do: {:ok, {:bool_lit, false}}
  defp classify("block"), do: {:ok, {:type, {:block, :opaque}}}
  defp classify("[]"), do: {:ok, {:list_lit, []}}
  defp classify("M["), do: {:ok, {:map_open, "M["}}
  defp classify("M[]"), do: {:ok, {:map_lit, %{}}}
  defp classify("_"), do: {:ok, {:wildcard, "_"}}

  defp classify(word) do
    cond do
      # String literal: "..." (supports \" \\ \n \t \r escape sequences)
      String.starts_with?(word, "\"") and String.ends_with?(word, "\"") ->
        {:ok, {:str_lit, word |> String.slice(1..-2) |> unescape()}}

      word in @operators ->
        {:ok, {:op, String.to_atom(String.downcase(word))}}

      word in @type_names ->
        {:ok, {:type, String.to_atom(word)}}

      # list type like [int], [str], or [json] (user-defined)
      Regex.match?(~r/^\[.+\]$/, word) ->
        inner = String.slice(word, 1..-2)
        cond do
          inner in @type_names ->
            {:ok, {:type, {:list, String.to_atom(inner)}}}
          Regex.match?(~r/^[a-z_][a-z0-9_]*$/, inner) ->
            {:ok, {:type, {:list, {:user_type, inner}}}}
          true ->
            {:error, "unknown list type: #{word}"}
        end

      # pid type like pid[int], pid[msg], or pid[map[str int]]
      Regex.match?(~r/^pid\[.+\]$/, word) ->
        inner = String.slice(word, 4..-2)

        case parse_map_inner_type(inner) do
          {:ok, t} -> {:ok, {:type, {:pid, t}}}
          :error -> {:error, "unknown pid type: #{word}"}
        end

      # monitor type like monitor[int] or monitor[msg]
      Regex.match?(~r/^monitor\[.+\]$/, word) ->
        inner = String.slice(word, 8..-2)

        case parse_map_inner_type(inner) do
          {:ok, t} -> {:ok, {:type, {:monitor, t}}}
          :error -> {:error, "unknown monitor type: #{word}"}
        end

      # block return type like block[pid[msg]] or block[str]
      Regex.match?(~r/^block\[.+\]$/, word) ->
        inner = String.slice(word, 6..-2)

        case parse_map_inner_type(inner) do
          {:ok, t} -> {:ok, {:type, {:block, {:returns, t}}}}
          :error -> {:error, "unknown block type: #{word}"}
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
          case parse_map_inner_type(inner) do
            {:ok, t} -> {:ok, {:list, t}}
            :error -> :error
          end

        Regex.match?(~r/^map\[.+\s+.+\]$/, s) ->
          inner = String.slice(s, 4..-2)
          [k, v] = String.split(inner, ~r/\s+/, parts: 2)
          case {parse_map_inner_type(k), parse_map_inner_type(v)} do
            {{:ok, kt}, {:ok, vt}} -> {:ok, {:map, kt, vt}}
            _ -> :error
          end

        Regex.match?(~r/^pid\[.+\]$/, s) ->
          inner = String.slice(s, 4..-2)

          case parse_map_inner_type(inner) do
            {:ok, t} -> {:ok, {:pid, t}}
            :error -> :error
          end

        Regex.match?(~r/^monitor\[.+\]$/, s) ->
          inner = String.slice(s, 8..-2)

          case parse_map_inner_type(inner) do
            {:ok, t} -> {:ok, {:monitor, t}}
            :error -> :error
          end

        Regex.match?(~r/^block\[.+\]$/, s) ->
          inner = String.slice(s, 6..-2)

          case parse_map_inner_type(inner) do
            {:ok, t} -> {:ok, {:block, {:returns, t}}}
            :error -> :error
          end

        Regex.match?(~r/^[a-z_][a-z0-9_]*$/, s) ->
          {:ok, {:user_type, s}}

        true ->
          :error
      end
    end
  end
end
