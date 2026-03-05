defmodule Cairn.Runtime do
  @moduledoc """
  Stack-based runtime for Cairn operators.

  Every operator takes a stack (list, top element first) and returns a new stack.
  """

  # Arithmetic — binary, pop 2 push 1
  def execute(:add, [a, b | rest]) when is_number(a) and is_number(b), do: [b + a | rest]
  def execute(:sub, [a, b | rest]) when is_number(a) and is_number(b), do: [b - a | rest]
  def execute(:mul, [a, b | rest]) when is_number(a) and is_number(b), do: [b * a | rest]

  def execute(:div, [a, b | rest]) when is_number(a) and is_number(b) do
    if a == 0, do: raise(Cairn.RuntimeError, "division by zero")
    [div(b, a) | rest]
  end

  def execute(:mod, [a, b | rest]) when is_integer(a) and is_integer(b), do: [rem(b, a) | rest]

  # Arithmetic — unary, pop 1 push 1
  def execute(:sq, [a | rest]) when is_number(a), do: [a * a | rest]
  def execute(:abs, [a | rest]) when is_number(a), do: [Kernel.abs(a) | rest]
  def execute(:neg, [a | rest]) when is_number(a), do: [-a | rest]
  def execute(:sin, [a | rest]) when is_float(a), do: [:math.sin(a) | rest]
  def execute(:cos, [a | rest]) when is_float(a), do: [:math.cos(a) | rest]
  def execute(:exp, [a | rest]) when is_float(a), do: [:math.exp(a) | rest]
  def execute(:pow, [a, b | rest]) when is_float(a) and is_float(b), do: [:math.pow(b, a) | rest]
  def execute(:pi, rest), do: [:math.pi() | rest]
  def execute(:e, rest), do: [:math.exp(1.0) | rest]
  def execute(:floor, [a | rest]) when is_float(a), do: [Float.floor(a) | rest]
  def execute(:ceil, [a | rest]) when is_float(a), do: [Float.ceil(a) | rest]
  def execute(:round, [a | rest]) when is_float(a), do: [Float.round(a) | rest]

  def execute(:log, [a | rest]) when is_float(a) do
    if a <= 0.0, do: raise(Cairn.RuntimeError, "LOG expects a positive float, got #{inspect(a)}")
    [:math.log(a) | rest]
  end

  def execute(:sqrt, [a | rest]) when is_float(a) do
    if a < 0.0, do: raise(Cairn.RuntimeError, "SQRT expects a non-negative float, got #{inspect(a)}")
    [:math.sqrt(a) | rest]
  end

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
  def execute(:assert_eq, [expected, actual | rest]) do
    if actual == expected do
      rest
    else
      raise(Cairn.RuntimeError, "ASSERT_EQ failed: expected #{inspect(expected)}, got #{inspect(actual)}")
    end
  end

  def execute(:assert_true, [value | rest]) do
    if value === true do
      rest
    else
      raise(Cairn.RuntimeError, "ASSERT_TRUE failed: expected TRUE, got #{inspect(value)}")
    end
  end

  def execute(:assert_false, [value | rest]) do
    if value === false do
      rest
    else
      raise(Cairn.RuntimeError, "ASSERT_FALSE failed: expected FALSE, got #{inspect(value)}")
    end
  end

  # Stack manipulation
  def execute(:dup, [a | rest]), do: [a, a | rest]
  def execute(:drop, [_ | rest]), do: rest
  def execute(:swap, [a, b | rest]), do: [b, a | rest]
  def execute(:over, [a, b | rest]), do: [b, a, b | rest]
  def execute(:rot, [a, b, c | rest]), do: [c, a, b | rest]
  def execute(:rot4, [a, b, c, d | rest]), do: [d, a, b, c | rest]
  def execute(:fst, [{:tuple, [a | _]} | rest]), do: [a | rest]
  def execute(:snd, [{:tuple, [_a, b | _]} | rest]), do: [b | rest]
  def execute(:trd, [{:tuple, [_a, _b, c | _]} | rest]), do: [c | rest]

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
  def execute(:zip, [b, a | rest]) when is_list(a) and is_list(b),
    do: [Enum.zip_with(a, b, fn left, right -> {:tuple, [left, right]} end) | rest]

  def execute(:enumerate, [list | rest]) when is_list(list),
    do: [Enum.with_index(list, 1) |> Enum.map(fn {elem, idx} -> {:tuple, [idx, elem]} end) | rest]
  def execute(:take, [count, list | rest]) when is_list(list) and is_integer(count) and count >= 0, do: [Enum.take(list, count) | rest]

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
    IO.puts("ax: " <> format_value(a))
    [a | rest]
  end

  # SAY: non-destructive — prints value cleanly (IO.puts for strings, IO.inspect otherwise)
  def execute(:say, [a | rest]) when is_binary(a) do
    IO.puts(a)
    [a | rest]
  end

  def execute(:say, [a | rest]) do
    IO.puts(format_value(a))
    [a | rest]
  end

  # SAID: destructive SAY — prints value cleanly then drops it
  def execute(:said, [a | rest]) when is_binary(a) do
    IO.puts(a)
    rest
  end

  def execute(:said, [a | rest]) do
    IO.puts(format_value(a))
    rest
  end

  # List operations — higher-order (take a block from the stack)
  # Blocks are {:block, tokens, env} — they capture the environment at creation.

  # FILTER: { block } list FILTER — keeps elements where block returns true
  def execute(:filter, [{:block, block_tokens, env}, list | rest]) when is_list(list) do
    filtered =
      Enum.filter(list, fn elem ->
        result = Cairn.Evaluator.eval_tokens(block_tokens, [elem], env)
        hd(result) == true
      end)

    [filtered | rest]
  end

  # MAP: { block } list MAP — applies block to each element
  def execute(:map, [{:block, block_tokens, env}, list | rest]) when is_list(list) do
    mapped =
      Enum.map(list, fn elem ->
        result = Cairn.Evaluator.eval_tokens(block_tokens, [elem], env)
        hd(result)
      end)

    [mapped | rest]
  end

  # REDUCE: [list] initial { block } REDUCE
  # Block receives [element, accumulator] on stack, must leave new accumulator
  def execute(:reduce, [{:block, block_tokens, env}, init, list | rest]) when is_list(list) do
    result =
      Enum.reduce(list, init, fn elem, acc ->
        result = Cairn.Evaluator.eval_tokens(block_tokens, [elem, acc], env)
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

  # FIND: { block } list FIND — returns Ok element or Err "not found"
  def execute(:find, [{:block, block_tokens, env}, list | rest]) when is_list(list) do
    result =
      Enum.find(list, fn elem ->
        eval_result = Cairn.Evaluator.eval_tokens(block_tokens, [elem], env)
        hd(eval_result) == true
      end)

    case result do
      nil -> [err("not found") | rest]
      elem -> [ok(elem) | rest]
    end
  end

  def execute(:find, [list, {:block, _, _} = block | rest]) when is_list(list) do
    execute(:find, [block, list | rest])
  end

  # FLAT_MAP: { block } list FLAT_MAP — block must produce a list for each element
  def execute(:flat_map, [{:block, block_tokens, env}, list | rest]) when is_list(list) do
    mapped =
      Enum.flat_map(list, fn elem ->
        result = Cairn.Evaluator.eval_tokens(block_tokens, [elem], env)

        case hd(result) do
          value when is_list(value) -> value
          other -> raise Cairn.RuntimeError, "FLAT_MAP block must return a list, got #{inspect(other)}"
        end
      end)

    [mapped | rest]
  end

  def execute(:flat_map, [list, {:block, _, _} = block | rest]) when is_list(list) do
    execute(:flat_map, [block, list | rest])
  end

  # GROUP_BY: { block } list GROUP_BY — groups original elements by the block's key
  def execute(:group_by, [{:block, block_tokens, env}, list | rest]) when is_list(list) do
    grouped =
      Enum.group_by(list, fn elem ->
        result = Cairn.Evaluator.eval_tokens(block_tokens, [elem], env)
        hd(result)
      end)

    [grouped | rest]
  end

  def execute(:group_by, [list, {:block, _, _} = block | rest]) when is_list(list) do
    execute(:group_by, [block, list | rest])
  end

  # Iteration — TIMES: N { block } TIMES — run block N times
  def execute(:times, [{:block, _block_tokens, _env}, 0 | rest]) do
    rest
  end

  def execute(:times, [{:block, block_tokens, env}, n | rest]) when is_integer(n) and n > 0 do
    Enum.reduce(1..n, rest, fn _, stack ->
      Cairn.Evaluator.eval_tokens(block_tokens, stack, env)
    end)
  end

  # Also support: { block } N TIMES (count on top)
  def execute(:times, [n, {:block, _, _} = block | rest]) when is_integer(n) do
    execute(:times, [block, n | rest])
  end

  # Bounded iteration — REPEAT is the direct readability-oriented sibling of TIMES.
  # It keeps the same stack semantics and argument ordering flexibility.
  def execute(:repeat, stack) do
    execute(:times, stack)
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

  def execute(:pairs, [map | rest]) when is_map(map),
    do: [map |> Map.to_list() |> Enum.map(fn {k, v} -> {:tuple, [k, v]} end) | rest]

  def execute(:num_str, [n | rest]) when is_float(n), do: [Float.to_string(n) | rest]
  def execute(:num_str, [n | rest]) when is_integer(n), do: [Integer.to_string(n) | rest]

  # WORDS: split string on whitespace, push list of words
  def execute(:words, [s | rest]) when is_binary(s), do: [String.split(s) | rest]

  # LINES: split string into lines
  def execute(:lines, [s | rest]) when is_binary(s), do: [String.split(s, "\n", trim: true) | rest]

  # CHARS: split string into list of graphemes
  def execute(:chars, [s | rest]) when is_binary(s), do: [String.graphemes(s) | rest]

  # SPLIT: split string on delimiter
  def execute(:split, [delim, s | rest]) when is_binary(s) and is_binary(delim), do: [String.split(s, delim) | rest]

  # TRIM: remove leading and trailing whitespace
  def execute(:trim, [s | rest]) when is_binary(s), do: [String.trim(s) | rest]

  # LOWER / UPPER: case normalization helpers
  def execute(:lower, [s | rest]) when is_binary(s), do: [String.downcase(s) | rest]
  def execute(:upper, [s | rest]) when is_binary(s), do: [String.upcase(s) | rest]

  # STARTS_WITH: check if string starts with prefix
  def execute(:starts_with, [prefix, s | rest]) when is_binary(s) and is_binary(prefix), do: [String.starts_with?(s, prefix) | rest]

  # ENDS_WITH: check if string ends with suffix
  def execute(:ends_with, [suffix, s | rest]) when is_binary(s) and is_binary(suffix),
    do: [String.ends_with?(s, suffix) | rest]

  # REPLACE: replace all matches of a pattern with the replacement string
  def execute(:replace, [replacement, pattern, s | rest])
      when is_binary(s) and is_binary(pattern) and is_binary(replacement),
      do: [String.replace(s, pattern, replacement) | rest]

  # REVERSE_STR: reverse the graphemes in a string
  def execute(:reverse_str, [s | rest]) when is_binary(s), do: [String.reverse(s) | rest]

  # SLICE: extract substring (zero-based start, length)
  def execute(:slice, [len, start, s | rest]) when is_binary(s) and is_integer(start) and is_integer(len), do: [String.slice(s, start, len) | rest]

  # TO_INT: parse string as integer (safe, returns result)
  def execute(:to_int, [s | rest]) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> [ok(n) | rest]
      _ -> [err("TO_INT: cannot parse #{inspect(s)} as integer") | rest]
    end
  end

  # TO_INT!: parse string as integer (unsafe, raises on failure)
  def execute(:to_int!, [s | rest]) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> [n | rest]
      _ -> raise Cairn.RuntimeError, "TO_INT!: cannot parse #{inspect(s)} as integer"
    end
  end

  # JOIN: join list of strings with separator
  def execute(:join, [sep, list | rest]) when is_list(list) and is_binary(sep), do: [Enum.join(list, sep) | rest]

  # TO_FLOAT: parse string as float (safe, returns result)
  def execute(:to_float, [s | rest]) when is_binary(s) do
    case Float.parse(s) do
      {f, ""} -> [ok(f) | rest]
      _ -> [err("TO_FLOAT: cannot parse #{inspect(s)} as float") | rest]
    end
  end

  # TO_FLOAT!: parse string as float (unsafe, raises on failure)
  def execute(:to_float!, [s | rest]) when is_binary(s) do
    case Float.parse(s) do
      {f, ""} -> [f | rest]
      _ -> raise Cairn.RuntimeError, "TO_FLOAT!: cannot parse #{inspect(s)} as float"
    end
  end

  # ARGV: push command-line args list (stored in process dictionary by mix task)
  def execute(:argv, stack), do: [Process.get(:cairn_argv, []) | stack]

  # READ_FILE: pop filename, push result
  def execute(:read_file, [path | rest]) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} -> [ok(contents) | rest]
      {:error, reason} -> [err("cannot read '#{path}': #{reason}") | rest]
    end
  end

  # READ_FILE!: pop filename, push file contents or raise
  def execute(:read_file!, [path | rest]) when is_binary(path) do
    case File.read(path) do
      {:ok, contents} -> [contents | rest]
      {:error, reason} -> raise Cairn.RuntimeError, "cannot read '#{path}': #{reason}"
    end
  end

  # WRITE_FILE: pop contents and filename, write file, push result
  def execute(:write_file, [path, contents | rest]) when is_binary(path) and is_binary(contents) do
    case File.write(path, contents) do
      :ok -> [ok(true) | rest]
      {:error, reason} -> [err("cannot write '#{path}': #{reason}") | rest]
    end
  end

  # WRITE_FILE!: pop contents and filename, write file or raise
  def execute(:write_file!, [path, contents | rest]) when is_binary(path) and is_binary(contents) do
    case File.write(path, contents) do
      :ok -> rest
      {:error, reason} -> raise Cairn.RuntimeError, "cannot write '#{path}': #{reason}"
    end
  end

  # Bounded Mnesia-backed key/value storage
  def execute(:db_put, [key, value | rest]) when is_binary(key) and is_binary(value) do
    Cairn.DataStore.put(key, value)
    rest
  end

  def execute(:db_get, [key | rest]) when is_binary(key) do
    case Cairn.DataStore.get(key) do
      {:ok, value} -> [ok(value) | rest]
      :error -> [err("missing key '#{key}'") | rest]
    end
  end

  def execute(:db_del, [key | rest]) when is_binary(key) do
    Cairn.DataStore.delete(key)
    rest
  end

  def execute(:db_pairs, stack) do
    [Cairn.DataStore.pairs() | stack]
  end

  def execute(:auth_check, [password, username | rest])
      when is_binary(password) and is_binary(username) do
    case Cairn.UserStore.authenticate(username, password) do
      {:ok, user} -> [ok(user) | rest]
      :error -> [err("invalid username or password") | rest]
    end
  end

  # READ_LINE: read one line from stdin, push trimmed string
  def execute(:read_line, stack) do
    line = IO.gets("") |> String.trim_trailing("\n")
    [line | stack]
  end

  # ASK: pop prompt string, read line, push result
  def execute(:ask, [prompt | rest]) when is_binary(prompt) do
    case IO.gets(prompt) do
      nil -> [err("ASK: input stream closed") | rest]
      line -> [ok(String.trim_trailing(line, "\n")) | rest]
    end
  end

  # ASK!: pop prompt string, read line, raise on EOF
  def execute(:ask!, [prompt | rest]) when is_binary(prompt) do
    case IO.gets(prompt) do
      nil -> raise Cairn.RuntimeError, "ASK!: input stream closed"
      line -> [String.trim_trailing(line, "\n") | rest]
    end
  end

  # RANDOM: pop N, push random integer in [1, N]
  def execute(:random, [n | rest]) when is_integer(n) and n > 0 do
    [Enum.random(1..n) | rest]
  end

  # FMT: pop format string, pop one value per {} placeholder, push formatted string
  def execute(:fmt, [format | rest]) when is_binary(format) do
    {result, remaining} = format_string(format, rest)
    [result | remaining]
  end

  # Error cases
  def execute(op, stack) do
    raise Cairn.RuntimeError,
          "cannot apply #{op} to stack: #{inspect(Enum.take(stack, 3))}... (#{length(stack)} elements)"
  end

  @doc """
  Execute a whitelisted host helper for the narrow interop v1 slice.
  """
  def host_call(name, args) when is_binary(name) and is_list(args) do
    wrapper =
      case name do
        "int_to_string" -> {:ok, 1, fn [value] when is_integer(value) -> Integer.to_string(value) end}
        "float_to_string" -> {:ok, 1, fn [value] when is_float(value) -> Float.to_string(value) end}
        _ -> :error
      end

    case wrapper do
      {:ok, arity, fun} ->
        if length(args) != arity do
          raise Cairn.RuntimeError, "HOST_CALL #{name}: expected #{arity} arg(s), got #{length(args)}"
        end

        try do
          case fun.(args) do
            result when is_binary(result) -> result
            other -> raise Cairn.RuntimeError, "HOST_CALL #{name}: returned unsupported host value #{inspect(other)}"
          end
        rescue
          e in Cairn.RuntimeError ->
            reraise e, __STACKTRACE__

          FunctionClauseError ->
            raise Cairn.RuntimeError, "HOST_CALL #{name}: argument types do not match the whitelist signature"

          e ->
            raise Cairn.RuntimeError, "HOST_CALL #{name}: host wrapper raised #{Exception.message(e)}"
        end

      :error ->
        raise Cairn.RuntimeError, "HOST_CALL #{name}: unknown host helper"
    end
  end

  # --- FMT helpers ---

  defp format_string(format, stack) do
    format_string_acc(format, stack, [])
  end

  defp format_string_acc("", stack, acc) do
    {acc |> Enum.reverse() |> IO.iodata_to_binary(), stack}
  end

  defp format_string_acc("{{" <> rest, stack, acc) do
    format_string_acc(rest, stack, ["{" | acc])
  end

  defp format_string_acc("}}" <> rest, stack, acc) do
    format_string_acc(rest, stack, ["}" | acc])
  end

  defp format_string_acc("{}" <> rest, [value | stack], acc) do
    format_string_acc(rest, stack, [format_value(value) | acc])
  end

  defp format_string_acc(<<c::utf8, rest::binary>>, stack, acc) do
    format_string_acc(rest, stack, [<<c::utf8>> | acc])
  end

  defp format_value(v) when is_binary(v), do: v
  defp format_value(v) when is_integer(v), do: Integer.to_string(v)
  defp format_value(v) when is_float(v), do: Float.to_string(v)
  defp format_value(true), do: "TRUE"
  defp format_value(false), do: "FALSE"
  defp format_value(v) when is_list(v),
    do: "[" <> (v |> Enum.map(&format_value/1) |> Enum.join(", ")) <> "]"
  defp format_value({:tuple, vals}),
    do: "#(" <> (vals |> Enum.map(&format_value/1) |> Enum.join(" ")) <> ")"
  defp format_value(v), do: inspect(v)

  defp ok(value), do: {:variant, "result", "Ok", [value]}
  defp err(message), do: {:variant, "result", "Err", [message]}

  defp run_while(cond_tokens, cond_env, body_tokens, body_env, stack) do
    check_stack = Cairn.Evaluator.eval_tokens(cond_tokens, stack, cond_env)

    case check_stack do
      [true | rest_after_check] ->
        new_stack = Cairn.Evaluator.eval_tokens(body_tokens, rest_after_check, body_env)
        run_while(cond_tokens, cond_env, body_tokens, body_env, new_stack)

      [false | rest_after_check] ->
        rest_after_check

      other ->
        raise Cairn.RuntimeError,
              "WHILE condition must return bool, got: #{inspect(hd(other))}"
    end
  end
end

defmodule Cairn.RuntimeError do
  defexception [:message]
end

defmodule Cairn.ContractError do
  defexception [:message, :function_name, :stack]
end
