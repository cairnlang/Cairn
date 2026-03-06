defmodule Cairn.Template do
  @moduledoc """
  Bounded template loader and renderer for Cairn template v1.

  T1 scope:
  - text literals
  - escaped placeholders: {{name}}
  """

  @type segment :: {:text, String.t()} | {:esc, String.t()} | {:raw, String.t()}
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
      render_segments(segments, context, [])
    end
  end

  def render(other, _context) do
    {:error, "TPL_RENDER expected a template value, got #{inspect(other)}"}
  end

  @spec parse(String.t()) :: {:ok, template()} | {:error, String.t()}
  def parse(source) when is_binary(source) do
    case parse_segments(source, []) do
      {:ok, segments} -> {:ok, {:template, segments}}
      {:error, _reason} = err -> err
    end
  end

  defp parse_segments("", acc), do: {:ok, Enum.reverse(acc)}

  defp parse_segments(source, acc) do
    case :binary.match(source, "{{") do
      :nomatch ->
        {:ok, Enum.reverse([{:text, source} | acc])}

      {idx, 2} ->
        {prefix, rest} = split_binary(source, idx)
        rest = binary_part(rest, 2, byte_size(rest) - 2)

        if String.starts_with?(rest, "{") do
          rest = binary_part(rest, 1, byte_size(rest) - 1)

          with {:ok, key, tail} <- parse_raw_placeholder(rest),
               {:ok, next} <- parse_segments(tail, [{:raw, key}, {:text, prefix} | acc]) do
            {:ok, next}
          end
        else
          with {:ok, key, tail} <- parse_placeholder(rest),
               {:ok, next} <- parse_segments(tail, [{:esc, key}, {:text, prefix} | acc]) do
            {:ok, next}
          end
        end
    end
  end

  defp parse_placeholder(rest) do
    case :binary.match(rest, "}}") do
      :nomatch ->
        {:error, "unclosed placeholder"}

      {idx, 2} ->
        {raw_name, tail} = split_binary(rest, idx)
        tail = binary_part(tail, 2, byte_size(tail) - 2)
        name = String.trim(raw_name)

        cond do
          name == "" ->
            {:error, "empty placeholder is not allowed"}

          not valid_name?(name) ->
            {:error, "invalid placeholder name '#{name}'"}

          true ->
            {:ok, name, tail}
        end
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

        cond do
          name == "" ->
            {:error, "empty raw placeholder is not allowed"}

          not valid_name?(name) ->
            {:error, "invalid raw placeholder name '#{name}'"}

          true ->
            {:ok, name, tail}
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

  defp validate_context(context) do
    if Enum.all?(context, fn
         {k, v} when is_binary(k) and is_binary(v) -> true
         _ -> false
       end) do
      :ok
    else
      {:error, "TPL_RENDER expected map[str str] context"}
    end
  end

  defp render_segments([], _context, acc) do
    {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}
  end

  defp render_segments([{:text, text} | rest], context, acc) do
    render_segments(rest, context, [text | acc])
  end

  defp render_segments([{:esc, key} | rest], context, acc) do
    case Map.fetch(context, key) do
      {:ok, value} ->
        render_segments(rest, context, [escape_html(value) | acc])

      :error ->
        {:error, "missing placeholder '#{key}'"}
    end
  end

  defp render_segments([{:raw, key} | rest], context, acc) do
    case Map.fetch(context, key) do
      {:ok, value} ->
        render_segments(rest, context, [value | acc])

      :error ->
        {:error, "missing placeholder '#{key}'"}
    end
  end

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
