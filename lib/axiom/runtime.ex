defmodule Axiom.Runtime do
  @moduledoc """
  Stack-based runtime for Axiom operators.

  Every operator takes a stack (list, top element first) and returns a new stack.
  """

  # Arithmetic — binary, pop 2 push 1
  def execute(:add, [a, b | rest]) when is_number(a) and is_number(b), do: [b + a | rest]
  def execute(:sub, [a, b | rest]) when is_number(a) and is_number(b), do: [b - a | rest]
  def execute(:mul, [a, b | rest]) when is_number(a) and is_number(b), do: [b * a | rest]

  def execute(:div, [a, b | rest]) when is_number(a) and is_number(b) do
    if a == 0, do: raise(Axiom.RuntimeError, "division by zero")
    [div(b, a) | rest]
  end

  def execute(:mod, [a, b | rest]) when is_integer(a) and is_integer(b), do: [rem(b, a) | rest]

  # Arithmetic — unary, pop 1 push 1
  def execute(:sq, [a | rest]) when is_number(a), do: [a * a | rest]
  def execute(:abs, [a | rest]) when is_number(a), do: [Kernel.abs(a) | rest]
  def execute(:neg, [a | rest]) when is_number(a), do: [-a | rest]

  # Comparison — pop 2, push bool
  def execute(:eq, [a, b | rest]), do: [b == a | rest]
  def execute(:neq, [a, b | rest]), do: [b != a | rest]
  def execute(:gt, [a, b | rest]) when is_number(a) and is_number(b), do: [b > a | rest]
  def execute(:lt, [a, b | rest]) when is_number(a) and is_number(b), do: [b < a | rest]
  def execute(:gte, [a, b | rest]) when is_number(a) and is_number(b), do: [b >= a | rest]
  def execute(:lte, [a, b | rest]) when is_number(a) and is_number(b), do: [b <= a | rest]

  # Logic
  def execute(:and, [a, b | rest]) when is_boolean(a) and is_boolean(b), do: [b and a | rest]
  def execute(:or, [a, b | rest]) when is_boolean(a) and is_boolean(b), do: [b or a | rest]
  def execute(:not, [a | rest]) when is_boolean(a), do: [not a | rest]

  # Stack manipulation
  def execute(:dup, [a | rest]), do: [a, a | rest]
  def execute(:drop, [_ | rest]), do: rest
  def execute(:swap, [a, b | rest]), do: [b, a | rest]
  def execute(:over, [a, b | rest]), do: [b, a, b | rest]
  def execute(:rot, [a, b, c | rest]), do: [c, a, b | rest]

  # Math — binary
  def execute(:min, [a, b | rest]) when is_number(a) and is_number(b), do: [Kernel.min(b, a) | rest]
  def execute(:max, [a, b | rest]) when is_number(a) and is_number(b), do: [Kernel.max(b, a) | rest]

  # List operations — basic
  def execute(:len, [list | rest]) when is_list(list), do: [length(list) | rest]
  def execute(:len, [s | rest]) when is_binary(s), do: [String.length(s) | rest]
  def execute(:head, [[h | _] | rest]), do: [h | rest]
  def execute(:tail, [[_ | t] | rest]), do: [t | rest]
  def execute(:cons, [list, elem | rest]) when is_list(list), do: [[elem | list] | rest]
  def execute(:concat, [b, a | rest]) when is_list(a) and is_list(b), do: [a ++ b | rest]
  def execute(:concat, [b, a | rest]) when is_binary(a) and is_binary(b), do: [a <> b | rest]

  # CONTAINS: pop string, pop substring, push boolean
  def execute(:contains, [sub, str | rest]) when is_binary(str) and is_binary(sub), do: [String.contains?(str, sub) | rest]
  def execute(:sum, [list | rest]) when is_list(list), do: [Enum.sum(list) | rest]
  def execute(:sort, [list | rest]) when is_list(list), do: [Enum.sort(list) | rest]
  def execute(:reverse, [list | rest]) when is_list(list), do: [Enum.reverse(list) | rest]

  # RANGE: N RANGE -> [1, 2, ..., N]
  def execute(:range, [0 | rest]), do: [[] | rest]
  def execute(:range, [n | rest]) when is_integer(n) and n > 0, do: [Enum.to_list(1..n) | rest]

  # PRINT: non-destructive — prints top of stack, leaves it there
  def execute(:print, [a | rest]) do
    IO.inspect(a, label: "ax")
    [a | rest]
  end

  # SAY: non-destructive — prints value cleanly (IO.puts for strings, IO.inspect otherwise)
  def execute(:say, [a | rest]) when is_binary(a) do
    IO.puts(a)
    [a | rest]
  end

  def execute(:say, [a | rest]) do
    IO.puts(inspect(a))
    [a | rest]
  end

  # List operations — higher-order (take a block from the stack)
  # Blocks are {:block, tokens, env} — they capture the environment at creation.

  # FILTER: { block } list FILTER — keeps elements where block returns true
  def execute(:filter, [{:block, block_tokens, env}, list | rest]) when is_list(list) do
    filtered =
      Enum.filter(list, fn elem ->
        result = Axiom.Evaluator.eval_tokens(block_tokens, [elem], env)
        hd(result) == true
      end)

    [filtered | rest]
  end

  # MAP: { block } list MAP — applies block to each element
  def execute(:map, [{:block, block_tokens, env}, list | rest]) when is_list(list) do
    mapped =
      Enum.map(list, fn elem ->
        result = Axiom.Evaluator.eval_tokens(block_tokens, [elem], env)
        hd(result)
      end)

    [mapped | rest]
  end

  # REDUCE: [list] initial { block } REDUCE
  # Block receives [element, accumulator] on stack, must leave new accumulator
  def execute(:reduce, [{:block, block_tokens, env}, init, list | rest]) when is_list(list) do
    result =
      Enum.reduce(list, init, fn elem, acc ->
        result = Axiom.Evaluator.eval_tokens(block_tokens, [elem, acc], env)
        hd(result)
      end)

    [result | rest]
  end

  # Also support: list initial { block } REDUCE (block on top)
  def execute(:reduce, [list, {:block, _, _} = block, init | rest]) when is_list(list) do
    execute(:reduce, [block, init, list | rest])
  end

  # Also support: list { block } FILTER (block on top)
  def execute(:filter, [list, {:block, _, _} = block | rest]) when is_list(list) do
    execute(:filter, [block, list | rest])
  end

  def execute(:map, [list, {:block, _, _} = block | rest]) when is_list(list) do
    execute(:map, [block, list | rest])
  end

  # Iteration — TIMES: N { block } TIMES — run block N times
  def execute(:times, [{:block, _block_tokens, _env}, 0 | rest]) do
    rest
  end

  def execute(:times, [{:block, block_tokens, env}, n | rest]) when is_integer(n) and n > 0 do
    Enum.reduce(1..n, rest, fn _, stack ->
      Axiom.Evaluator.eval_tokens(block_tokens, stack, env)
    end)
  end

  # Also support: { block } N TIMES (count on top)
  def execute(:times, [n, {:block, _, _} = block | rest]) when is_integer(n) do
    execute(:times, [block, n | rest])
  end

  # Iteration — WHILE: { cond } { body } WHILE
  # Order: cond block first (bottom), body block second (top).
  # Evaluates cond block; if it pushes true, pops it, runs body, repeats.
  def execute(:while, [{:block, body_tokens, body_env}, {:block, cond_tokens, cond_env} | rest]) do
    run_while(cond_tokens, cond_env, body_tokens, body_env, rest)
  end

  # Map operations
  def execute(:get, [key, map | rest]) when is_map(map), do: [Map.fetch!(map, key) | rest]
  def execute(:put, [value, key, map | rest]) when is_map(map), do: [Map.put(map, key, value) | rest]
  def execute(:del, [key, map | rest]) when is_map(map), do: [Map.delete(map, key) | rest]
  def execute(:keys, [map | rest]) when is_map(map), do: [Map.keys(map) | rest]
  def execute(:values, [map | rest]) when is_map(map), do: [Map.values(map) | rest]
  def execute(:has, [key, map | rest]) when is_map(map), do: [Map.has_key?(map, key) | rest]
  def execute(:mlen, [map | rest]) when is_map(map), do: [map_size(map) | rest]

  def execute(:merge, [map2, map1 | rest]) when is_map(map1) and is_map(map2),
    do: [Map.merge(map1, map2) | rest]

  # WORDS: split string on whitespace, push list of words
  def execute(:words, [s | rest]) when is_binary(s), do: [String.split(s) | rest]

  # LINES: split string into lines
  def execute(:lines, [s | rest]) when is_binary(s), do: [String.split(s, "\n", trim: true) | rest]

  # ARGV: push command-line args list (stored in process dictionary by mix task)
  def execute(:argv, stack), do: [Process.get(:axiom_argv, []) | stack]

  # READ_FILE: pop filename, push file contents
  def execute(:read_file, [path | rest]) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} -> [contents | rest]
      {:error, reason} -> raise Axiom.RuntimeError, "cannot read '#{path}': #{reason}"
    end
  end

  # WRITE_FILE: pop contents and filename, write to file
  def execute(:write_file, [path, contents | rest]) when is_binary(path) and is_binary(contents) do
    case File.write(path, contents) do
      :ok -> rest
      {:error, reason} -> raise Axiom.RuntimeError, "cannot write '#{path}': #{reason}"
    end
  end

  # READ_LINE: read one line from stdin, push trimmed string
  def execute(:read_line, stack) do
    line = IO.gets("") |> String.trim_trailing("\n")
    [line | stack]
  end

  # Error cases
  def execute(op, stack) do
    raise Axiom.RuntimeError,
          "cannot apply #{op} to stack: #{inspect(Enum.take(stack, 3))}... (#{length(stack)} elements)"
  end

  defp run_while(cond_tokens, cond_env, body_tokens, body_env, stack) do
    check_stack = Axiom.Evaluator.eval_tokens(cond_tokens, stack, cond_env)

    case check_stack do
      [true | rest_after_check] ->
        new_stack = Axiom.Evaluator.eval_tokens(body_tokens, rest_after_check, body_env)
        run_while(cond_tokens, cond_env, body_tokens, body_env, new_stack)

      [false | rest_after_check] ->
        rest_after_check

      other ->
        raise Axiom.RuntimeError,
              "WHILE condition must return bool, got: #{inspect(hd(other))}"
    end
  end
end

defmodule Axiom.RuntimeError do
  defexception [:message]
end

defmodule Axiom.ContractError do
  defexception [:message, :function_name, :stack]
end
