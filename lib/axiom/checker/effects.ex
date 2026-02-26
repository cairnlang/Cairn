defmodule Axiom.Checker.Effects do
  @moduledoc """
  Declarative registry of operator stack effects for the type checker.

  Each effect specifies what types an operator pops and pushes.
  """

  @type effect :: %{pops: [atom()], pushes: [atom()]}

  # :num means int or float
  # :num_result means "same numeric type as inputs" (resolved by checker)
  # :any means any type

  @effects %{
    # Arithmetic — binary: pop 2 nums, push 1 num
    add: %{pops: [:num, :num], pushes: [:num_result]},
    sub: %{pops: [:num, :num], pushes: [:num_result]},
    mul: %{pops: [:num, :num], pushes: [:num_result]},
    div: %{pops: [:num, :num], pushes: [:num_result]},
    mod: %{pops: [:int, :int], pushes: [:int]},
    min: %{pops: [:num, :num], pushes: [:num_result]},
    max: %{pops: [:num, :num], pushes: [:num_result]},

    # Arithmetic — unary: pop 1 num, push 1 num
    sq: %{pops: [:num], pushes: [:num_result]},
    abs: %{pops: [:num], pushes: [:num_result]},
    neg: %{pops: [:num], pushes: [:num_result]},

    # Comparison — pop 2, push bool
    eq: %{pops: [:any, :any], pushes: [:bool]},
    neq: %{pops: [:any, :any], pushes: [:bool]},
    gt: %{pops: [:num, :num], pushes: [:bool]},
    lt: %{pops: [:num, :num], pushes: [:bool]},
    gte: %{pops: [:num, :num], pushes: [:bool]},
    lte: %{pops: [:num, :num], pushes: [:bool]},

    # Logic — binary
    and: %{pops: [:bool, :bool], pushes: [:bool]},
    or: %{pops: [:bool, :bool], pushes: [:bool]},

    # Logic — unary
    not: %{pops: [:bool], pushes: [:bool]},

    # List operations
    sum: %{pops: [{:list, :num}], pushes: [:num]},
    len: %{pops: [:any], pushes: [:int]},
    head: %{pops: [{:list, :any}], pushes: [:any]},
    tail: %{pops: [{:list, :any}], pushes: [{:list, :any}]},
    cons: %{pops: [{:list, :any}, :any], pushes: [{:list, :any}]},
    concat: %{pops: [:any, :any], pushes: [:any]},
    sort: %{pops: [{:list, :any}], pushes: [{:list, :any}]},
    reverse: %{pops: [{:list, :any}], pushes: [{:list, :any}]},
    range: %{pops: [:int], pushes: [{:list, :int}]},

    # String operations
    words: %{pops: [:str], pushes: [{:list, :str}]},
    lines: %{pops: [:str], pushes: [{:list, :str}]},
    contains:    %{pops: [:str, :str],       pushes: [:bool]},
    chars:       %{pops: [:str],             pushes: [{:list, :str}]},
    split:       %{pops: [:str, :str],       pushes: [{:list, :str}]},
    trim:        %{pops: [:str],             pushes: [:str]},
    starts_with: %{pops: [:str, :str],       pushes: [:bool]},
    slice:       %{pops: [:int, :int, :str], pushes: [:str]},
    to_int:      %{pops: [:str],             pushes: [:int]},
    to_float:    %{pops: [:str],             pushes: [:float]},
    join:        %{pops: [:str, {:list, :str}], pushes: [:str]},

    # I/O — non-destructive (pop any, push same)
    say: %{pops: [:any], pushes: [:any]},
    print: %{pops: [:any], pushes: [:any]},

    # I/O — push only
    argv: %{pops: [], pushes: [{:list, :str}]},
    read_line: %{pops: [], pushes: [:str]},

    # File I/O
    read_file: %{pops: [:str], pushes: [:str]},
    write_file: %{pops: [:str, :str], pushes: []},

    # Map operations
    get: %{pops: [:any, {:map, :any, :any}], pushes: [:any]},
    put: %{pops: [:any, :any, {:map, :any, :any}], pushes: [{:map, :any, :any}]},
    del: %{pops: [:any, {:map, :any, :any}], pushes: [{:map, :any, :any}]},
    keys: %{pops: [{:map, :any, :any}], pushes: [{:list, :any}]},
    values: %{pops: [{:map, :any, :any}], pushes: [{:list, :any}]},
    has: %{pops: [:any, {:map, :any, :any}], pushes: [:bool]},
    mlen: %{pops: [{:map, :any, :any}], pushes: [:int]},
    merge:   %{pops: [{:map, :any, :any}, {:map, :any, :any}], pushes: [{:map, :any, :any}]},
    pairs:   %{pops: [{:map, :any, :any}], pushes: [{:list, {:list, :any}}]},
    num_str: %{pops: [:num], pushes: [:str]}
  }

  @doc """
  Look up the stack effect for an operator.
  Returns `{:ok, effect}` or `:unknown`.
  """
  @spec lookup(atom()) :: {:ok, effect()} | :unknown
  def lookup(op) do
    case Map.get(@effects, op) do
      nil -> :unknown
      effect -> {:ok, effect}
    end
  end
end
