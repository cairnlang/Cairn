defmodule Cairn.Loader do
  @moduledoc """
  Loads Cairn source files with recursive IMPORT resolution.
  """

  alias Cairn.{Lexer, Parser}

  @type parsed_item ::
          Cairn.Types.Function.t()
          | Cairn.Types.TypeDef.t()
          | {:expr, [Cairn.Types.token()]}
          | {:verify, String.t(), pos_integer()}
          | {:prove, String.t()}
          | {:test, String.t(), [Cairn.Types.token()]}

  @spec load_items(String.t()) :: {:ok, [parsed_item()]} | {:error, String.t()}
  def load_items(path) do
    path
    |> Path.expand()
    |> load_recursive(MapSet.new(), [])
    |> case do
      {:ok, _loaded, items} -> {:ok, items}
      {:error, _} = err -> err
    end
  end

  defp load_recursive(path, loaded, loading) do
    cond do
      MapSet.member?(loaded, path) ->
        {:ok, loaded, []}

      path in loading ->
        chain = Enum.reverse([path | loading]) |> Enum.join(" -> ")
        {:error, "IMPORT cycle detected: #{chain}"}

      true ->
        with {:ok, source} <- read_source(path),
             {:ok, tokens} <- wrap(Lexer.tokenize(source), path, "tokenize"),
             {:ok, loaded, imported_items} <- load_imports_from_tokens(tokens, path, loaded, [path | loading]),
             {:ok, items} <- wrap(Parser.parse(tokens, collect_imported_type_names(imported_items)), path, "parse") do
          local_items = Enum.reject(items, &match?({:import, _}, &1))
          {:ok, MapSet.put(loaded, path), imported_items ++ local_items}
        end
    end
  end

  defp load_imports_from_tokens(tokens, current_path, loaded, loading) do
    current_dir = Path.dirname(current_path)

    tokens
    |> collect_import_paths()
    |> Enum.reduce_while({:ok, loaded, []}, fn import_path, {:ok, loaded_acc, items_acc} ->
      resolved = resolve_import_path(import_path, current_dir)

      case load_recursive(resolved, loaded_acc, loading) do
        {:ok, loaded_next, imported_items} ->
          {:cont, {:ok, loaded_next, items_acc ++ imported_items}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  defp collect_import_paths(tokens) do
    tokens
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.reduce([], fn
      [{:import_kw, _, _}, {:str_lit, path, _}], acc -> acc ++ [path]
      _, acc -> acc
    end)
  end

  defp collect_imported_type_names(items) do
    Enum.reduce(items, MapSet.new(), fn
      %Cairn.Types.TypeDef{name: name}, acc -> MapSet.put(acc, name)
      _, acc -> acc
    end)
  end

  defp resolve_import_path(path, current_dir) do
    if Path.type(path) == :absolute do
      Path.expand(path)
    else
      Path.expand(path, current_dir)
    end
  end

  defp read_source(path) do
    case File.read(path) do
      {:ok, source} ->
        {:ok, source}

      {:error, reason} ->
        {:error, "IMPORT failed to read '#{path}': #{reason}"}
    end
  end

  defp wrap({:ok, value}, _path, _action), do: {:ok, value}

  defp wrap({:error, msg}, path, action) do
    {:error, "IMPORT #{action} error in '#{path}': #{msg}"}
  end
end
