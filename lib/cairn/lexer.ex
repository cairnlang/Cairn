defmodule Cairn.Lexer do
  @moduledoc """
  Tokenizes Cairn source text into a flat token list.

  Cairn tokens are space-delimited. No whitespace sensitivity.
  """

  @operators ~w(ADD SUB MUL DIV MOD EQ NEQ GT LT GTE LTE AND OR NOT
                ASSERT_EQ ASSERT_TRUE ASSERT_FALSE
                DUP DROP SWAP OVER ROT ROT4
                FST SND TRD
                FILTER MAP FLAT_MAP REDUCE FIND GROUP_BY SUM LEN HEAD TAIL CONS CONCAT ZIP ENUMERATE TAKE
                SORT REVERSE MIN MAX
                SQ ABS NEG SIN COS EXP LOG SQRT POW PI E FLOOR CEIL ROUND
                TIMES REPEAT WHILE APPLY WITH_STATE STATE SET_STATE STEP
                RANGE PRINT SAY SELF EXIT
                SEND MONITOR AWAIT
                HOST_CALL HTTP_SERVE TPL_LOAD TPL_RENDER DB_PUT DB_GET DB_DEL DB_PAIRS DB_REFRESH AUTH_CHECK
                ARGV READ_FILE WRITE_FILE READ_FILE! WRITE_FILE! READ_LINE
                WORDS LINES CONTAINS
                CHARS SPLIT TRIM LOWER UPPER STARTS_WITH ENDS_WITH REPLACE REVERSE_STR SLICE TO_INT TO_FLOAT TO_INT! TO_FLOAT! NUM_STR JOIN
                GET PUT DEL KEYS VALUES HAS MLEN MERGE PAIRS
                ASK ASK! RANDOM FMT SAID)

  @type_names ~w(int float bool any void str template)

  @doc """
  Tokenizes a source string into a list of `{type, value, position}` tuples.
  """
  @spec tokenize(String.t()) :: {:ok, [Cairn.Types.token()]} | {:error, String.t()}
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
  defp strip_line_comment(<<?\\, ?", rest::binary>>, true, acc),
    do: strip_line_comment(rest, true, [?", ?\\ | acc])

  defp strip_line_comment(<<?", rest::binary>>, false, acc),
    do: strip_line_comment(rest, true, [?" | acc])

  defp strip_line_comment(<<?", rest::binary>>, true, acc),
    do: strip_line_comment(rest, false, [?" | acc])

  defp strip_line_comment(<<?#, ?(, rest::binary>>, false, acc),
    do: strip_line_comment(rest, false, [?(, ?# | acc])

  defp strip_line_comment(<<?#, _::binary>>, false, acc),
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp strip_line_comment(<<c, rest::binary>>, in_str, acc),
    do: strip_line_comment(rest, in_str, [c | acc])

  # Scan words respecting quoted strings (with \" escapes) and map types
  defp scan_words(source) do
    Regex.scan(
      ~r/#\(|\)|tuple\[(?:[^\[\]]|\[[^\]]*\])*\]|map\[(?:[^\[\]]|\[[^\]]*\])*\]|[a-z_][a-z0-9_]*\[(?:[^\[\]]|\[[^\]]*\])*\]|"(?:[^"\\]|\\.)*"|[^\s]+/,
      source
    )
    |> Enum.map(fn [match] -> match end)
    |> merge_bracketed_words([])
  end

  # The regex scanner handles one-level bracket nesting, but nested generic types like
  # result[tuple[str map[str str] int] str] can still be split across spaces inside the
  # outer brackets. Merge only word-like bracketed tokens, not list/map literal opens.
  defp merge_bracketed_words([], acc), do: Enum.reverse(acc)

  defp merge_bracketed_words([word | rest], acc) do
    if mergeable_bracket_word?(word) and bracket_balance(word) > 0 do
      {merged, remaining} = consume_bracket_word(rest, word)
      merge_bracketed_words(remaining, [merged | acc])
    else
      merge_bracketed_words(rest, [word | acc])
    end
  end

  defp mergeable_bracket_word?(word) do
    not (String.starts_with?(word, "\"") and String.ends_with?(word, "\"")) and
      String.contains?(word, "[") and
      word not in ["[", "M["]
  end

  defp bracket_balance(word) do
    String.graphemes(word)
    |> Enum.reduce(0, fn
      "[", acc -> acc + 1
      "]", acc -> acc - 1
      _, acc -> acc
    end)
  end

  defp consume_bracket_word([], current), do: {current, []}

  defp consume_bracket_word([next | rest], current) do
    merged = current <> " " <> next

    if bracket_balance(merged) > 0 do
      consume_bracket_word(rest, merged)
    else
      {merged, rest}
    end
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
  defp classify("#("), do: {:ok, {:tuple_open, "#("}}
  defp classify(")"), do: {:ok, {:tuple_close, ")"}}
  defp classify("{"), do: {:ok, {:block_open, "{"}}
  defp classify("}"), do: {:ok, {:block_close, "}"}}
  defp classify(":"), do: {:ok, {:colon, ":"}}
  defp classify("->"), do: {:ok, {:arrow, "->"}}
  defp classify("DEF"), do: {:ok, {:fn_def, "DEF"}}
  defp classify("END"), do: {:ok, {:fn_end, "END"}}
  defp classify("POST"), do: {:ok, {:post, "POST"}}
  defp classify("PRE"), do: {:ok, {:pre, "PRE"}}
  defp classify("EFFECT"), do: {:ok, {:effect_kw, "EFFECT"}}
  defp classify("PROTOCOL"), do: {:ok, {:protocol_kw, "PROTOCOL"}}
  defp classify("USING"), do: {:ok, {:using_kw, "USING"}}
  defp classify("RECV"), do: {:ok, {:recv_kw, "RECV"}}
  defp classify("IF"), do: {:ok, {:if_kw, "IF"}}
  defp classify("ELSE"), do: {:ok, {:else_kw, "ELSE"}}
  defp classify("VERIFY"), do: {:ok, {:verify_kw, "VERIFY"}}
  defp classify("PROVE"), do: {:ok, {:prove_kw, "PROVE"}}
  defp classify("TEST"), do: {:ok, {:test_kw, "TEST"}}
  defp classify("IMPORT"), do: {:ok, {:import_kw, "IMPORT"}}
  defp classify("TYPE"), do: {:ok, {:type_kw, "TYPE"}}
  defp classify("TYPEALIAS"), do: {:ok, {:type_alias_kw, "TYPEALIAS"}}
  defp classify("MATCH"), do: {:ok, {:match_kw, "MATCH"}}
  defp classify("RECEIVE"), do: {:ok, {:receive_kw, "RECEIVE"}}
  defp classify("SPAWN"), do: {:ok, {:spawn_kw, "SPAWN"}}
  defp classify("SPAWN_LINK"), do: {:ok, {:spawn_link_kw, "SPAWN_LINK"}}
  defp classify("LET"), do: {:ok, {:let_kw, "LET"}}
  defp classify("|"), do: {:ok, {:pipe, "|"}}
  defp classify("="), do: {:ok, {:equals, "="}}
  defp classify("TRUE"), do: {:ok, {:bool_lit, true}}
  defp classify("FALSE"), do: {:ok, {:bool_lit, false}}
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

      # list type like [int], [str], [msg], or [T]
      Regex.match?(~r/^\[.+\]$/, word) ->
        inner = String.slice(word, 1..-2)

        case parse_map_inner_type(inner) do
          {:ok, t} -> {:ok, {:type, {:list, t}}}
          :error -> {:error, "unknown list type: #{word}"}
        end

      # tuple type like tuple[int str] or tuple[T U]
      Regex.match?(~r/^tuple\[.+\]$/, word) ->
        inner = String.slice(word, 6..-2)
        parts = split_top_level_type_parts(inner)

        parsed = Enum.map(parts, &parse_map_inner_type/1)

        if parsed != [] and Enum.all?(parsed, &match?({:ok, _}, &1)) do
          {:ok, {:type, {:tuple, Enum.map(parsed, fn {:ok, t} -> t end)}}}
        else
          {:error, "unknown tuple type: #{word}"}
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

        case split_top_level_type_parts(inner) do
          [key_str, val_str] ->
            key_type = parse_map_inner_type(key_str)
            val_type = parse_map_inner_type(val_str)

            case {key_type, val_type} do
              {{:ok, k}, {:ok, v}} -> {:ok, {:type, {:map, k, v}}}
              _ -> {:error, "unknown map type: #{word}"}
            end

          _ ->
            {:error, "unknown map type: #{word}"}
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

      # generic function name like fn_name[T U]
      Regex.match?(~r/^[a-z_][a-z0-9_]*\[.+\]$/, word) ->
        [name, params_str] = String.split(word, "[", parts: 2)
        params_str = String.trim_trailing(params_str, "]")

        params =
          params_str
          |> scan_type_args()

        {:ok, {:generic_ident, {name, params}}}

      # identifier (short semantic tag)
      Regex.match?(~r/^[a-z_][a-z0-9_]*$/, word) ->
        {:ok, {:ident, word}}

      true ->
        {:error, "unexpected token: #{word}"}
    end
  end

  defp scan_type_args(source) do
    split_top_level_type_parts(source)
  end

  defp parse_map_inner_type(s) do
    s = String.trim(s)

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

        Regex.match?(~r/^tuple\[.+\]$/, s) ->
          inner = String.slice(s, 6..-2)
          parts = split_top_level_type_parts(inner)

          parsed = Enum.map(parts, &parse_map_inner_type/1)

          if parsed != [] and Enum.all?(parsed, &match?({:ok, _}, &1)) do
            {:ok, {:tuple, Enum.map(parsed, fn {:ok, t} -> t end)}}
          else
            :error
          end

        Regex.match?(~r/^map\[.+\s+.+\]$/, s) ->
          inner = String.slice(s, 4..-2)

          case split_top_level_type_parts(inner) do
            [k, v] ->
              case {parse_map_inner_type(k), parse_map_inner_type(v)} do
                {{:ok, kt}, {:ok, vt}} -> {:ok, {:map, kt, vt}}
                _ -> :error
              end

            _ ->
              :error
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

        Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*\[.+\]$/, s) ->
          [name, args_str] = String.split(s, "[", parts: 2)
          inner = String.trim_trailing(args_str, "]")
          parts = split_top_level_type_parts(inner)

          parsed = Enum.map(parts, &parse_map_inner_type/1)

          if parsed != [] and Enum.all?(parsed, &match?({:ok, _}, &1)) do
            {:ok, {:user_type, name, Enum.map(parsed, fn {:ok, t} -> t end)}}
          else
            :error
          end

        Regex.match?(~r/^[A-Za-z_][A-Za-z0-9_]*$/, s) ->
          {:ok, {:user_type, s}}

        true ->
          :error
      end
    end
  end

  defp split_top_level_type_parts(source) do
    source
    |> String.trim()
    |> String.graphemes()
    |> Enum.reduce({[], "", 0}, fn ch, {parts, current, depth} ->
      cond do
        ch == "[" ->
          {parts, current <> ch, depth + 1}

        ch == "]" ->
          {parts, current <> ch, depth - 1}

        Regex.match?(~r/\s/, ch) and depth == 0 ->
          if current == "" do
            {parts, current, depth}
          else
            {[current | parts], "", depth}
          end

        true ->
          {parts, current <> ch, depth}
      end
    end)
    |> finalize_type_parts()
  end

  defp finalize_type_parts({parts, "", _depth}), do: Enum.reverse(parts)
  defp finalize_type_parts({parts, current, _depth}), do: Enum.reverse([current | parts])
end
