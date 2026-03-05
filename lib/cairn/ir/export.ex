defmodule Cairn.IR.Export do
  @moduledoc """
  Read-only exporter for Cairn's parsed program graph shape.

  This module does not change evaluation behavior. It serializes parsed items
  into a deterministic JSON graph for inspection/debug tooling.
  """

  alias Cairn.Types.Function

  @type export_opt :: {:source, String.t()} | {:fn, String.t() | nil}

  @spec from_items(list(), [export_opt()]) :: {:ok, map()} | {:error, String.t()}
  def from_items(items, opts \\ []) do
    source = Keyword.get(opts, :source, "<memory>")
    fn_filter = Keyword.get(opts, :fn)

    function_entries =
      items
      |> collect_entries()
      |> Enum.with_index(1)

    selected =
      case fn_filter do
        nil ->
          function_entries

        name ->
          filtered = Enum.filter(function_entries, fn {entry, _index} -> entry.name == name end)

          if filtered == [] do
            available =
              function_entries
              |> Enum.map(fn {entry, _index} -> entry.name end)
              |> Enum.sort()
              |> Enum.join(", ")

            {:error, "IR export: unknown function '#{name}' (available: #{available})"}
          else
            filtered
          end
      end

    case selected do
      {:error, _} = err ->
        err

      entries ->
        function_names =
          MapSet.new(Enum.map(function_entries, fn {entry, _index} -> entry.name end))

        functions =
          Enum.map(entries, fn {entry, index} ->
            build_function_graph(entry, index, function_names)
          end)

        {:ok,
         %{
           version: "cairn-ir-json-v1",
           source: source,
           functions: functions
         }}
    end
  end

  @spec encode_json(map()) :: String.t()
  def encode_json(map), do: json_encode(map)

  defp collect_entries(items) do
    {entries, _expr_index} =
      Enum.reduce(items, {[], 1}, fn
        %Function{} = func, {acc, expr_index} ->
          entry = %{
            kind: "function",
            name: func.name,
            type_params: func.type_params || [],
            effect: Atom.to_string(func.effect || :io),
            param_types: func.param_types || [],
            return_types: func.return_types || [],
            tokens: func.body || []
          }

          {[entry | acc], expr_index}

        {:expr, tokens}, {acc, expr_index} ->
          entry = %{
            kind: "expr",
            name: "__expr_#{expr_index}",
            type_params: [],
            effect: "io",
            param_types: [],
            return_types: [],
            tokens: tokens || []
          }

          {[entry | acc], expr_index + 1}

        _, state ->
          state
      end)

    Enum.reverse(entries)
  end

  defp build_function_graph(entry, index, function_names) do
    base = "f#{index}"
    entry_id = "#{base}:entry"
    exit_id = "#{base}:exit"
    tokens = entry.tokens
    token_count = length(tokens)

    token_nodes =
      tokens
      |> Enum.with_index(1)
      |> Enum.map(fn {token, token_index} ->
        token_node("#{base}:t#{token_index}", token)
      end)

    call_targets =
      token_nodes
      |> Enum.reduce(MapSet.new(), fn node, acc ->
        case node do
          %{kind: "call", callee: callee} when is_binary(callee) ->
            if MapSet.member?(function_names, callee) do
              MapSet.put(acc, callee)
            else
              acc
            end

          _ ->
            acc
        end
      end)
      |> Enum.sort()

    call_target_nodes =
      Enum.map(call_targets, fn callee ->
        %{id: "#{base}:call:#{callee}", kind: "call_target", function: callee}
      end)

    control_edges =
      if token_count == 0 do
        [%{from: entry_id, to: exit_id, kind: "control"}]
      else
        ([{entry_id, "#{base}:t1"} | sequential_token_edges(base, token_count)] ++
           [{"#{base}:t#{token_count}", exit_id}])
        |> Enum.map(fn {from, to} -> %{from: from, to: to, kind: "control"} end)
      end

    call_edges =
      Enum.flat_map(token_nodes, fn
        %{id: token_id, kind: "call", callee: callee} ->
          if callee in call_targets do
            [%{from: token_id, to: "#{base}:call:#{callee}", kind: "call"}]
          else
            []
          end

        _ ->
          []
      end)

    %{
      name: entry.name,
      kind: entry.kind,
      effect: entry.effect,
      signature: %{
        type_params: entry.type_params,
        params: Enum.map(entry.param_types, &format_type/1),
        returns: Enum.map(entry.return_types, &format_type/1)
      },
      entry_node: entry_id,
      exit_nodes: [exit_id],
      nodes:
        [%{id: entry_id, kind: "entry"}] ++
          token_nodes ++ call_target_nodes ++ [%{id: exit_id, kind: "exit"}],
      edges: control_edges ++ call_edges
    }
  end

  defp sequential_token_edges(_base, token_count) when token_count <= 1, do: []

  defp sequential_token_edges(base, token_count) do
    Enum.map(1..(token_count - 1), fn i ->
      {"#{base}:t#{i}", "#{base}:t#{i + 1}"}
    end)
  end

  defp token_node(id, token) do
    case token do
      {:op, op, pos} ->
        %{id: id, kind: "op", op: Atom.to_string(op), span: %{word: pos}}

      {:ident, name, pos} ->
        %{id: id, kind: "call", callee: name, span: %{word: pos}}

      {:int_lit, value, pos} ->
        %{id: id, kind: "literal", literal_type: "int", value: value, span: %{word: pos}}

      {:float_lit, value, pos} ->
        %{id: id, kind: "literal", literal_type: "float", value: value, span: %{word: pos}}

      {:bool_lit, value, pos} ->
        %{id: id, kind: "literal", literal_type: "bool", value: value, span: %{word: pos}}

      {:str_lit, value, pos} ->
        %{id: id, kind: "literal", literal_type: "str", value: value, span: %{word: pos}}

      {:constructor, name, pos} ->
        %{id: id, kind: "constructor", name: name, span: %{word: pos}}

      {type, value, pos} when is_atom(type) ->
        %{
          id: id,
          kind: "token",
          token_type: Atom.to_string(type),
          value: inspect(value),
          span: %{word: pos}
        }

      other ->
        %{id: id, kind: "token", token_type: "unknown", value: inspect(other)}
    end
  end

  defp format_type(:int), do: "int"
  defp format_type(:float), do: "float"
  defp format_type(:bool), do: "bool"
  defp format_type(:str), do: "str"
  defp format_type(:any), do: "any"
  defp format_type(:void), do: "void"
  defp format_type({:type_var, name}), do: name
  defp format_type({:list, inner}), do: "[#{format_type(inner)}]"
  defp format_type({:map, key, value}), do: "map[#{format_type(key)} #{format_type(value)}]"
  defp format_type({:pid, inner}), do: "pid[#{format_type(inner)}]"
  defp format_type({:monitor, inner}), do: "monitor[#{format_type(inner)}]"
  defp format_type({:tuple, elems}), do: "#(" <> Enum.map_join(elems, " ", &format_type/1) <> ")"
  defp format_type({:block, :opaque}), do: "block"
  defp format_type({:block, {:returns, inner}}), do: "block[#{format_type(inner)}]"
  defp format_type({:user_type, name}), do: name
  defp format_type({:user_type, name, []}), do: name

  defp format_type({:user_type, name, args}),
    do: "#{name}[#{Enum.map_join(args, " ", &format_type/1)}]"

  defp format_type(other) when is_binary(other), do: other
  defp format_type(other), do: inspect(other)

  defp json_encode(nil), do: "null"
  defp json_encode(true), do: "true"
  defp json_encode(false), do: "false"
  defp json_encode(value) when is_integer(value) or is_float(value), do: to_string(value)

  defp json_encode(value) when is_binary(value) do
    "\"" <> escape_json(value) <> "\""
  end

  defp json_encode(list) when is_list(list) do
    "[" <> Enum.map_join(list, ",", &json_encode/1) <> "]"
  end

  defp json_encode(map) when is_map(map) do
    "{" <>
      (map
       |> Enum.map(fn {k, v} -> {to_string(k), v} end)
       |> Enum.sort_by(fn {k, _v} -> k end)
       |> Enum.map_join(",", fn {k, v} -> json_encode(k) <> ":" <> json_encode(v) end)) <> "}"
  end

  defp json_encode(value), do: json_encode(to_string(value))

  defp escape_json(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
    |> String.replace("\r", "\\r")
    |> String.replace("\t", "\\t")
  end
end
