defmodule Cairn.Diagnostic do
  @moduledoc """
  Consistent diagnostic formatting for CLI surfaces.
  """

  alias Cairn.Checker.Error

  @type t :: %{
          kind: String.t(),
          message: String.t(),
          word: integer() | nil,
          location: %{path: String.t(), line: integer(), snippet: String.t()} | nil,
          hint: String.t() | nil
        }

  @spec from_exception(Exception.t(), String.t() | nil) :: t()
  def from_exception(%Cairn.StaticError{} = e, path) do
    primary = List.first(e.errors)

    base = %{
      kind: "static",
      message: static_message(primary, e.message),
      word: error_word(primary),
      location: source_location(path, error_word(primary)),
      hint: "Check operand types and function signatures near the reported word."
    }

    case e.errors do
      [] -> base
      errors -> Map.put(base, :details, Enum.map(errors, &format_static_detail/1))
    end
  end

  def from_exception(%Cairn.RuntimeError{message: message}, path) do
    word = extract_word(message)

    %{
      kind: "runtime",
      message: message,
      word: word,
      location: source_location(path, word),
      hint: runtime_hint(message)
    }
  end

  def from_exception(%Cairn.ContractError{message: message}, path) do
    word = extract_word(message)

    %{
      kind: "contract",
      message: message,
      word: word,
      location: source_location(path, word),
      hint: "Re-check PRE/POST logic or run VERIFY with more cases to localize the failing path."
    }
  end

  def from_exception(e, path) do
    message = Exception.message(e)
    word = extract_word(message)

    %{
      kind: "error",
      message: message,
      word: word,
      location: source_location(path, word),
      hint: nil
    }
  end

  @spec format_text(t()) :: [String.t()]
  def format_text(diag) do
    [
      "ERROR kind=#{diag.kind}",
      "  message: #{diag.message}"
    ]
    |> maybe_add_location(diag)
    |> maybe_add_hint(diag)
    |> maybe_add_details(diag)
  end

  @spec format_json(t()) :: String.t()
  def format_json(diag) do
    diag
    |> Map.take([:kind, :message, :word, :location, :hint, :details])
    |> json_encode()
  end

  defp static_message(%Error{message: m}, _fallback), do: m
  defp static_message(_, fallback), do: fallback

  defp error_word(%Error{position: pos}) when is_integer(pos), do: pos + 1
  defp error_word(_), do: nil

  defp format_static_detail(%Error{position: nil, message: m}), do: m
  defp format_static_detail(%Error{position: pos, message: m}), do: "at word #{pos + 1}: #{m}"

  defp maybe_add_location(lines, %{location: nil}), do: lines

  defp maybe_add_location(lines, %{word: word, location: %{path: path, line: line, snippet: snippet}}) do
    lines ++
      [
        "  location: #{path}:#{line} (word #{word})",
        "  snippet: #{snippet}"
      ]
  end

  defp maybe_add_hint(lines, %{hint: nil}), do: lines
  defp maybe_add_hint(lines, %{hint: hint}), do: lines ++ ["  hint: #{hint}"]

  defp maybe_add_details(lines, %{details: details}) when is_list(details) and details != [] do
    lines ++ ["  details: #{Enum.join(details, " | ")}"]
  end

  defp maybe_add_details(lines, _), do: lines

  defp runtime_hint(message) do
    cond do
      String.contains?(message, "undefined '") ->
        "Define the missing identifier/function, or IMPORT the module that provides it."

      String.contains?(message, "stack underflow") ->
        "Ensure enough values are on the stack before this operation."

      String.contains?(message, "PROVE") and String.contains?(message, "z3 not found") ->
        "Install Z3 and ensure `z3` is available on PATH."

      String.contains?(message, "PROVE") and String.contains?(message, "failed to open file") ->
        "Check temp-file write permissions and retry."

      true ->
        "Inspect the reported location and surrounding stack effects."
    end
  end

  defp extract_word(message) do
    case Regex.run(~r/at word\s+(\d+)/, message) do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  defp source_location(nil, _word), do: nil
  defp source_location(_path, nil), do: nil

  defp source_location(path, word) do
    with {:ok, source} <- File.read(path),
         rows when is_list(rows) <- token_rows(source),
         {line, snippet} when is_integer(line) <- row_for_word(rows, word) do
      %{path: path, line: line, snippet: snippet}
    else
      _ -> nil
    end
  end

  defp token_rows(source) do
    source
    |> strip_comments()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.map(fn {line, idx} ->
      words =
        Regex.scan(~r/map\[(?:[^\[\]]|\[[^\]]*\])*\]|"(?:[^"\\]|\\.)*"|[^\s]+/, line)
        |> Enum.map(fn [m] -> m end)
        |> Enum.reject(&(&1 == ""))

      {idx, String.trim(line), length(words)}
    end)
  end

  defp row_for_word(rows, word) do
    {_count, found} =
      Enum.reduce_while(rows, {0, nil}, fn {line, text, n}, {count, _} ->
        if word <= count + n do
          {:halt, {count + n, {line, text}}}
        else
          {:cont, {count + n, nil}}
        end
      end)

    case found do
      nil -> nil
      {line, text} -> {line, text}
    end
  end

  # Strip # comments while preserving quoted strings.
  defp strip_comments(source) do
    source
    |> String.split("\n")
    |> Enum.map(&strip_line_comment(&1, false, []))
    |> Enum.join("\n")
  end

  defp strip_line_comment(<<>>, _in_str, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp strip_line_comment(<<?\\, ?", rest::binary>>, true, acc),
    do: strip_line_comment(rest, true, [?", ?\\ | acc])

  defp strip_line_comment(<<?", rest::binary>>, false, acc),
    do: strip_line_comment(rest, true, [?" | acc])

  defp strip_line_comment(<<?", rest::binary>>, true, acc),
    do: strip_line_comment(rest, false, [?" | acc])

  defp strip_line_comment(<<?#, _::binary>>, false, acc),
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp strip_line_comment(<<c, rest::binary>>, in_str, acc),
    do: strip_line_comment(rest, in_str, [c | acc])

  defp json_encode(nil), do: "null"
  defp json_encode(true), do: "true"
  defp json_encode(false), do: "false"
  defp json_encode(n) when is_integer(n) or is_float(n), do: to_string(n)

  defp json_encode(s) when is_binary(s) do
    escaped =
      s
      |> String.replace("\\", "\\\\")
      |> String.replace("\"", "\\\"")
      |> String.replace("\n", "\\n")
      |> String.replace("\r", "\\r")
      |> String.replace("\t", "\\t")

    "\"#{escaped}\""
  end

  defp json_encode(list) when is_list(list) do
    "[" <> Enum.map_join(list, ",", &json_encode/1) <> "]"
  end

  defp json_encode(map) when is_map(map) do
    body =
      map
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map_join(",", fn {k, v} ->
        json_encode(to_string(k)) <> ":" <> json_encode(v)
      end)

    "{" <> body <> "}"
  end
end
