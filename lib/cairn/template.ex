defmodule Cairn.Template do
  @moduledoc """
  Bounded template loader and renderer for Cairn template v1.

  Supported constructs:
  - text literals
  - escaped placeholders: {{name}}
  - raw placeholders: {{{name}}}
  - if sections: {{#if cond}}...{{/if}}
  - each sections: {{#each items as item}}...{{/each}}
  """

  @type segment ::
          {:text, String.t()}
          | {:esc, String.t()}
          | {:raw, String.t()}
          | {:if, String.t(), [segment]}
          | {:each, String.t(), String.t(), [segment]}
  @type template :: {:template, [segment]}

  @spec load(String.t()) :: {:ok, template()} | {:error, String.t()}
  def load(path) when is_binary(path) do
    case File.read(path) do
      {:ok, source} ->
        case parse(source) do
          {:ok, template} -> {:ok, template}
          {:error, reason} -> {:error, "template parse error in '#{path}': #{reason}"}
        end

      {:error, reason} ->
        {:error, "cannot read template '#{path}': #{inspect(reason)}"}
    end
  end

  @spec render(template(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def render({:template, segments}, context) when is_list(segments) and is_map(context) do
    with :ok <- validate_context(context) do
      with {:ok, chunks} <- render_segments(segments, context, %{}) do
        {:ok, IO.iodata_to_binary(chunks)}
      end
    end
  end

  def render(other, _context) do
    {:error, "TPL_RENDER expected a template value, got #{inspect(other)}"}
  end

  @spec parse(String.t()) :: {:ok, template()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    case parse_segments(source, nil, []) do
      {:ok, segments, ""} ->
        {:ok, {:template, segments}}

      {:error, _reason} = err -> err
    end
  end

  defp parse_segments("", nil, acc), do: {:ok, Enum.reverse(acc), ""}

  defp parse_segments("", stop_tag, _acc), do: {:error, "unclosed section '#{stop_tag}'"}

  defp parse_segments(source, stop_tag, acc) do
    case :binary.match(source, "{{") do
      :nomatch ->
        if stop_tag == nil do
          {:ok, Enum.reverse(add_text(acc, source)), ""}
        else
          {:error, "unclosed section '#{stop_tag}'"}
        end

      {idx, 2} ->
        {prefix, rest} = split_binary(source, idx)
        rest = binary_part(rest, 2, byte_size(rest) - 2)
        acc = add_text(acc, prefix)

        if String.starts_with?(rest, "{") do
          rest = binary_part(rest, 1, byte_size(rest) - 1)

          with {:ok, key, tail} <- parse_raw_placeholder(rest),
               {:ok, next, tail} <- parse_segments(tail, stop_tag, [{:raw, key} | acc]) do
            {:ok, next, tail}
          end
        else
          parse_regular_tag(rest, stop_tag, acc)
        end
    end
  end

  defp parse_regular_tag(rest, stop_tag, acc) do
    case :binary.match(rest, "}}") do
      :nomatch ->
        {:error, "unclosed tag"}

      {idx, 2} ->
        {raw_tag, tail} = split_binary(rest, idx)
        tail = binary_part(tail, 2, byte_size(tail) - 2)
        tag = String.trim(raw_tag)

        cond do
          tag == "" ->
            {:error, "empty tag is not allowed"}

          String.starts_with?(tag, "/") ->
            close_tag = String.trim_leading(tag, "/")
            parse_close_tag(close_tag, stop_tag, acc, tail)

          String.starts_with?(tag, "#if ") ->
            key = String.trim_leading(tag, "#if ")

            with {:ok, normalized_key} <- parse_name(key, "if condition name"),
                 {:ok, inner, inner_tail} <- parse_segments(tail, "if", []),
                 {:ok, next, tail} <-
                   parse_segments(inner_tail, stop_tag, [{:if, normalized_key, inner} | acc]) do
              {:ok, next, tail}
            end

          String.starts_with?(tag, "#each ") ->
            parse_each_tag(tag, tail, stop_tag, acc)

          String.starts_with?(tag, "#") ->
            {:error, "unknown section tag '#{tag}'"}

          true ->
            with {:ok, key} <- parse_name(tag, "placeholder name"),
                 {:ok, next, tail} <- parse_segments(tail, stop_tag, [{:esc, key} | acc]) do
              {:ok, next, tail}
            end
        end
    end
  end

  defp parse_each_tag(tag, tail, stop_tag, acc) do
    case Regex.run(~r/^#each\s+([a-z_][a-z0-9_]*)\s+as\s+([a-z_][a-z0-9_]*)$/, tag) do
      [_, list_key, item_name] ->
        with {:ok, inner, inner_tail} <- parse_segments(tail, "each", []),
             {:ok, next, tail} <-
               parse_segments(
                 inner_tail,
                 stop_tag,
                 [{:each, list_key, item_name, inner} | acc]
               ) do
          {:ok, next, tail}
        end

      _ ->
        {:error, "invalid each tag '#{tag}' (expected '#each items as item')"}
    end
  end

  defp parse_close_tag(close_tag, stop_tag, acc, tail) do
    cond do
      stop_tag == nil ->
        {:error, "unexpected closing tag '/#{close_tag}'"}

      close_tag == stop_tag ->
        {:ok, Enum.reverse(acc), tail}

      true ->
        {:error, "mismatched closing tag '/#{close_tag}' for section '#{stop_tag}'"}
    end
  end

  defp parse_raw_placeholder(rest) do
    case :binary.match(rest, "}}}") do
      :nomatch ->
        {:error, "unclosed raw placeholder"}

      {idx, 3} ->
        {raw_name, tail} = split_binary(rest, idx)
        tail = binary_part(tail, 3, byte_size(tail) - 3)
        name = String.trim(raw_name)

        with {:ok, normalized} <- parse_name(name, "raw placeholder name") do
          {:ok, normalized, tail}
        end
    end
  end

  defp split_binary(binary, idx) do
    {
      binary_part(binary, 0, idx),
      binary_part(binary, idx, byte_size(binary) - idx)
    }
  end

  defp valid_name?(name) do
    Regex.match?(~r/^[a-z_][a-z0-9_]*$/, name)
  end

  defp parse_name(name, context) do
    cond do
      name == "" ->
        {:error, "empty #{context} is not allowed"}

      not valid_name?(name) ->
        {:error, "invalid #{context} '#{name}'"}

      true ->
        {:ok, name}
    end
  end

  defp add_text(acc, ""), do: acc
  defp add_text(acc, text), do: [{:text, text} | acc]

  defp validate_context(context) do
    if Enum.all?(context, fn
         {k, _v} when is_binary(k) -> true
         _ -> false
       end) do
      :ok
    else
      {:error, "TPL_RENDER expected map with string keys"}
    end
  end

  defp render_segments(segments, context, locals) do
    segments
    |> Enum.reduce_while({:ok, []}, fn segment, {:ok, acc} ->
      case render_segment(segment, context, locals) do
        {:ok, chunk} -> {:cont, {:ok, [chunk | acc]}}
        {:error, _reason} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, chunks} -> {:ok, Enum.reverse(chunks)}
      {:error, _reason} = err -> err
    end
  end

  defp render_segment({:text, text}, _context, _locals), do: {:ok, text}

  defp render_segment({:esc, key}, context, locals) do
    with {:ok, value} <- resolve_value(key, context, locals) do
      {:ok, escape_html(to_template_text(value))}
    end
  end

  defp render_segment({:raw, key}, context, locals) do
    with {:ok, value} <- resolve_value(key, context, locals) do
      {:ok, to_template_text(value)}
    end
  end

  defp render_segment({:if, key, inner}, context, locals) do
    with {:ok, value} <- resolve_value(key, context, locals) do
      if is_boolean(value) do
        if value do
          render_segments(inner, context, locals)
        else
          {:ok, []}
        end
      else
        {:error, "if section '#{key}' expects bool, got #{inspect(value)}"}
      end
    end
  end

  defp render_segment({:each, list_key, item_name, inner}, context, locals) do
    with {:ok, value} <- resolve_value(list_key, context, locals) do
      if is_list(value) do
        Enum.reduce_while(value, {:ok, []}, fn item, {:ok, acc} ->
          case render_segments(inner, context, Map.put(locals, item_name, item)) do
            {:ok, chunks} -> {:cont, {:ok, [chunks | acc]}}
            {:error, _reason} = err -> {:halt, err}
          end
        end)
        |> case do
          {:ok, chunks} -> {:ok, Enum.reverse(chunks)}
          {:error, _reason} = err -> err
        end
      else
        {:error, "each section '#{list_key}' expects list, got #{inspect(value)}"}
      end
    end
  end

  defp resolve_value(key, context, locals) do
    cond do
      Map.has_key?(locals, key) ->
        {:ok, Map.fetch!(locals, key)}

      Map.has_key?(context, key) ->
        {:ok, Map.fetch!(context, key)}

      true ->
        {:error, "missing placeholder '#{key}'"}
    end
  end

  defp to_template_text(value) when is_binary(value), do: value
  defp to_template_text(value) when is_integer(value), do: Integer.to_string(value)
  defp to_template_text(value) when is_float(value), do: Float.to_string(value)
  defp to_template_text(true), do: "TRUE"
  defp to_template_text(false), do: "FALSE"
  defp to_template_text(value), do: inspect(value)

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
