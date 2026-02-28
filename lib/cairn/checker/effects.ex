defmodule Cairn.Checker.Effects do
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
    pow: %{pops: [:float, :float], pushes: [:float]},

    # Arithmetic — unary: pop 1 num, push 1 num
    sq: %{pops: [:num], pushes: [:num_result]},
    abs: %{pops: [:num], pushes: [:num_result]},
    neg: %{pops: [:num], pushes: [:num_result]},
    sin: %{pops: [:float], pushes: [:float]},
    cos: %{pops: [:float], pushes: [:float]},
    exp: %{pops: [:float], pushes: [:float]},
    log: %{pops: [:float], pushes: [:float]},
    sqrt: %{pops: [:float], pushes: [:float]},
    floor: %{pops: [:float], pushes: [:float]},
    ceil: %{pops: [:float], pushes: [:float]},
    round: %{pops: [:float], pushes: [:float]},
    pi: %{pops: [], pushes: [:float]},
    e: %{pops: [], pushes: [:float]},

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
    zip: %{pops: [{:list, :any}, {:list, :any}], pushes: [{:list, {:list, :any}}]},
    enumerate: %{pops: [{:list, :any}], pushes: [{:list, {:list, :any}}]},
    take: %{pops: [:int, {:list, :any}], pushes: [{:list, :any}]},
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
    lower:       %{pops: [:str],             pushes: [:str]},
    upper:       %{pops: [:str],             pushes: [:str]},
    starts_with: %{pops: [:str, :str],       pushes: [:bool]},
    ends_with:   %{pops: [:str, :str],       pushes: [:bool]},
    replace:     %{pops: [:str, :str, :str], pushes: [:str]},
    reverse_str: %{pops: [:str],             pushes: [:str]},
    slice:       %{pops: [:int, :int, :str], pushes: [:str]},
    to_int:      %{pops: [:str],             pushes: [{:user_type, "result"}]},
    to_float:    %{pops: [:str],             pushes: [{:user_type, "result"}]},
    to_int!:  %{pops: [:str],             pushes: [:int]},
    to_float!: %{pops: [:str],            pushes: [:float]},
    join:        %{pops: [:str, {:list, :str}], pushes: [:str]},

    # I/O — non-destructive (pop any, push same)
    say: %{pops: [:any], pushes: [:any]},
    print: %{pops: [:any], pushes: [:any]},

    # I/O — destructive (pop any, push nothing)
    said: %{pops: [:any], pushes: []},

    # I/O — push only
    argv: %{pops: [], pushes: [{:list, :str}]},
    read_line: %{pops: [], pushes: [:str]},

    # File I/O
    read_file: %{pops: [:str], pushes: [{:user_type, "result"}]},
    write_file: %{pops: [:str, :str], pushes: [{:user_type, "result"}]},
    read_file!: %{pops: [:str], pushes: [:str]},
    write_file!: %{pops: [:str, :str], pushes: []},
    http_serve: %{pops: [{:block, :opaque}, :int], pushes: []},
    db_put: %{pops: [:str, :str], pushes: []},
    db_get: %{pops: [:str], pushes: [{:user_type, "result"}]},
    db_del: %{pops: [:str], pushes: []},
    db_pairs: %{pops: [], pushes: [{:list, {:list, :str}}]},

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
    num_str: %{pops: [:num], pushes: [:str]},

    # ASK: pop prompt string, push input string
    ask: %{pops: [:str], pushes: [{:user_type, "result"}]},
    ask!: %{pops: [:str], pushes: [:str]},

    # RANDOM: pop int N, push random int in [1, N]
    random: %{pops: [:int], pushes: [:int]}
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
