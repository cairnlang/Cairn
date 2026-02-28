defmodule Cairn.DAG do
  @moduledoc """
  Content-addressed DAG storage backed by ETS.

  Every node is identified by a hash derived from its operation and inputs.
  Identical subexpressions automatically deduplicate (structural sharing).
  """

  @table :cairn_dag

  @doc """
  Initializes the ETS table for DAG storage.
  Safe to call multiple times — will not destroy existing data.
  """
  @spec init() :: :ok
  def init do
    case :ets.info(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  @doc """
  Clears all nodes from the DAG.
  """
  @spec clear() :: :ok
  def clear do
    init()
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc """
  Stores a node in the DAG. The hash is computed from op and inputs.
  Returns the node with its hash populated.
  """
  @spec put(Cairn.Types.Node.t()) :: Cairn.Types.Node.t()
  def put(%Cairn.Types.Node{} = node) do
    hash = compute_hash(node.op, node.inputs)
    node = %{node | hash: hash}
    :ets.insert(@table, {hash, node})
    node
  end

  @doc """
  Retrieves a node by its hash.
  """
  @spec get(String.t()) :: Cairn.Types.Node.t() | nil
  def get(hash) do
    case :ets.lookup(@table, hash) do
      [{^hash, node}] -> node
      [] -> nil
    end
  end

  @doc """
  Returns all nodes in the DAG.
  """
  @spec all() :: [Cairn.Types.Node.t()]
  def all do
    :ets.tab2list(@table)
    |> Enum.map(fn {_hash, node} -> node end)
  end

  @doc """
  Returns all nodes reachable from the given root hash.
  """
  @spec subgraph(String.t()) :: [Cairn.Types.Node.t()]
  def subgraph(root_hash) do
    collect_subgraph(root_hash, MapSet.new(), [])
    |> Enum.reverse()
  end

  defp collect_subgraph(hash, visited, acc) do
    if MapSet.member?(visited, hash) do
      {visited, acc}
    else
      case get(hash) do
        nil ->
          {visited, acc}

        node ->
          visited = MapSet.put(visited, hash)
          acc = [node | acc]

          Enum.reduce(node.inputs, {visited, acc}, fn input_hash, {v, a} ->
            collect_subgraph(input_hash, v, a)
          end)
      end
    end
  end

  @doc """
  Computes a content-derived hash for a node.
  """
  @spec compute_hash(atom(), [String.t()]) :: String.t()
  def compute_hash(op, inputs) do
    data = :erlang.term_to_binary({op, inputs})

    :crypto.hash(:sha256, data)
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 8)
  end
end
