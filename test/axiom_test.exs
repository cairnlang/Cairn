defmodule AxiomTest do
  use ExUnit.Case

  # ── Lexer ──

  describe "Lexer" do
    test "tokenizes integer literals" do
      assert {:ok, [{:int_lit, 42, 0}]} = Axiom.Lexer.tokenize("42")
      assert {:ok, [{:int_lit, -7, 0}]} = Axiom.Lexer.tokenize("-7")
    end

    test "tokenizes float literals" do
      assert {:ok, [{:float_lit, 3.14, 0}]} = Axiom.Lexer.tokenize("3.14")
    end

    test "tokenizes boolean literals" do
      assert {:ok, [{:bool_lit, true, 0}]} = Axiom.Lexer.tokenize("T")
      assert {:ok, [{:bool_lit, false, 0}]} = Axiom.Lexer.tokenize("F")
    end

    test "tokenizes operators" do
      assert {:ok, [{:op, :add, 0}]} = Axiom.Lexer.tokenize("ADD")
      assert {:ok, [{:op, :filter, 0}]} = Axiom.Lexer.tokenize("FILTER")
      assert {:ok, [{:op, :dup, 0}]} = Axiom.Lexer.tokenize("DUP")
    end

    test "tokenizes list brackets" do
      assert {:ok, [{:list_open, "[", 0}, {:int_lit, 1, 1}, {:list_close, "]", 2}]} =
               Axiom.Lexer.tokenize("[ 1 ]")
    end

    test "tokenizes block braces" do
      assert {:ok, [{:block_open, "{", 0}, {:op, :dup, 1}, {:block_close, "}", 2}]} =
               Axiom.Lexer.tokenize("{ DUP }")
    end

    test "tokenizes function definition" do
      {:ok, tokens} = Axiom.Lexer.tokenize("DEF double : int -> int DUP ADD END")

      types = Enum.map(tokens, fn {type, _, _} -> type end)

      assert types == [
               :fn_def,
               :ident,
               :colon,
               :type,
               :arrow,
               :type,
               :op,
               :op,
               :fn_end
             ]
    end

    test "tokenizes type annotations" do
      assert {:ok, [{:type, :int, 0}]} = Axiom.Lexer.tokenize("int")
      assert {:ok, [{:type, :float, 0}]} = Axiom.Lexer.tokenize("float")
      assert {:ok, [{:type, {:list, :int}, 0}]} = Axiom.Lexer.tokenize("[int]")
    end

    test "tokenizes identifiers" do
      assert {:ok, [{:ident, "foo", 0}]} = Axiom.Lexer.tokenize("foo")
      assert {:ok, [{:ident, "my_func", 0}]} = Axiom.Lexer.tokenize("my_func")
    end

    test "rejects unknown tokens" do
      assert {:error, _} = Axiom.Lexer.tokenize("@#$")
    end
  end

  # ── Parser ──

  describe "Parser" do
    test "parses bare expression" do
      {:ok, tokens} = Axiom.Lexer.tokenize("3 4 ADD")
      {:ok, [item]} = Axiom.Parser.parse(tokens)
      assert {:expr, _} = item
    end

    test "parses function definition" do
      {:ok, tokens} = Axiom.Lexer.tokenize("DEF double : int -> int DUP ADD END")
      {:ok, [func]} = Axiom.Parser.parse(tokens)
      assert %Axiom.Types.Function{name: "double"} = func
      assert func.param_types == [:int]
      assert func.return_type == :int
      assert length(func.body) == 2
      assert func.post_condition == nil
    end

    test "parses function with POST condition" do
      {:ok, tokens} = Axiom.Lexer.tokenize("DEF dbl : int -> int DUP ADD POST 0 GT END")
      {:ok, [func]} = Axiom.Parser.parse(tokens)
      assert func.name == "dbl"
      assert func.post_condition != nil
      assert length(func.post_condition) == 2
    end

    test "parses mixed functions and expressions" do
      source = "DEF sq : int -> int DUP MUL END 5 sq"
      {:ok, tokens} = Axiom.Lexer.tokenize(source)
      {:ok, items} = Axiom.Parser.parse(tokens)
      assert length(items) == 2
      assert %Axiom.Types.Function{} = hd(items)
      assert {:expr, _} = List.last(items)
    end
  end

  # ── DAG ──

  describe "DAG" do
    setup do
      Axiom.DAG.clear()
      :ok
    end

    test "put and get a node" do
      node = %Axiom.Types.Node{op: :add, inputs: ["a", "b"], type: :int, meta: %{}}
      stored = Axiom.DAG.put(node)
      assert stored.hash != nil
      assert Axiom.DAG.get(stored.hash) == stored
    end

    test "content addressing deduplicates" do
      node1 = %Axiom.Types.Node{op: :add, inputs: ["a", "b"], type: :int, meta: %{}}
      node2 = %Axiom.Types.Node{op: :add, inputs: ["a", "b"], type: :int, meta: %{}}
      stored1 = Axiom.DAG.put(node1)
      stored2 = Axiom.DAG.put(node2)
      assert stored1.hash == stored2.hash
    end

    test "different nodes get different hashes" do
      node1 = %Axiom.Types.Node{op: :add, inputs: ["a", "b"], type: :int, meta: %{}}
      node2 = %Axiom.Types.Node{op: :mul, inputs: ["a", "b"], type: :int, meta: %{}}
      stored1 = Axiom.DAG.put(node1)
      stored2 = Axiom.DAG.put(node2)
      assert stored1.hash != stored2.hash
    end
  end

  # ── Evaluator / Integration ──

  describe "eval" do
    test "arithmetic" do
      assert Axiom.eval("3 4 ADD") == [7]
      assert Axiom.eval("10 3 SUB") == [7]
      assert Axiom.eval("3 4 MUL") == [12]
      assert Axiom.eval("10 3 DIV") == [3]
      assert Axiom.eval("10 3 MOD") == [1]
    end

    test "unary ops" do
      assert Axiom.eval("5 SQ") == [25]
      assert Axiom.eval("-3 ABS") == [3]
      assert Axiom.eval("5 NEG") == [-5]
    end

    test "comparison" do
      assert Axiom.eval("3 4 EQ") == [false]
      assert Axiom.eval("3 3 EQ") == [true]
      assert Axiom.eval("5 3 GT") == [true]
      assert Axiom.eval("3 5 LT") == [true]
    end

    test "logic" do
      assert Axiom.eval("T T AND") == [true]
      assert Axiom.eval("T F AND") == [false]
      assert Axiom.eval("T F OR") == [true]
      assert Axiom.eval("T NOT") == [false]
    end

    test "stack manipulation" do
      assert Axiom.eval("5 DUP") == [5, 5]
      assert Axiom.eval("3 5 SWAP") == [3, 5]
      assert Axiom.eval("3 5 DROP") == [3]
      assert Axiom.eval("3 5 OVER") == [3, 5, 3]
    end

    test "list construction" do
      assert Axiom.eval("[ 1 2 3 ]") == [[1, 2, 3]]
    end

    test "list operations" do
      assert Axiom.eval("[ 1 2 3 ] SUM") == [6]
      assert Axiom.eval("[ 1 2 3 ] LEN") == [3]
      assert Axiom.eval("[ 1 2 3 ] HEAD") == [1]
      assert Axiom.eval("[ 1 2 3 ] TAIL") == [[2, 3]]
    end

    test "filter with block" do
      assert Axiom.eval("[ 1 2 3 4 5 ] { 2 MOD 1 EQ } FILTER") == [[1, 3, 5]]
    end

    test "map with block" do
      assert Axiom.eval("[ 1 2 3 ] { SQ } MAP") == [[1, 4, 9]]
    end

    test "filter then map then sum (the showcase example)" do
      assert Axiom.eval("[ 1 2 3 4 5 ] { 2 MOD 1 EQ } FILTER { SQ } MAP SUM") == [35]
    end

    test "if/end true branch" do
      assert Axiom.eval("T IF 42 END") == [42]
    end

    test "if/end false branch (no else)" do
      assert Axiom.eval("F IF 42 END") == []
    end

    test "if/else/end" do
      assert Axiom.eval("T IF 1 ELSE 2 END") == [1]
      assert Axiom.eval("F IF 1 ELSE 2 END") == [2]
    end

    test "function definition and call" do
      source = "DEF double : int -> int DUP ADD END 5 double"
      assert Axiom.eval(source) == [10]
    end

    test "function with POST condition — passing" do
      source = "DEF dbl : int -> int DUP ADD POST 0 GTE END 5 dbl"
      assert Axiom.eval(source) == [10]
    end

    test "function with POST condition — failing" do
      source = "DEF bad : int -> int NEG POST 0 GT END 5 bad"
      assert_raise Axiom.ContractError, fn -> Axiom.eval(source) end
    end

    test "multiple values on stack" do
      assert Axiom.eval("1 2 3") == [3, 2, 1]
    end

    test "chained operations" do
      assert Axiom.eval("2 3 ADD 4 MUL") == [20]
    end
  end

  # ── Integration: multi-function programs ──

  describe "integration" do
    test "IF inside function body" do
      source = "DEF absv : int -> int DUP 0 LT IF NEG END END -5 absv"
      assert Axiom.eval(source) == [5]
    end

    test "IF/ELSE inside function body" do
      source = "DEF sign : int -> int DUP 0 GT IF DROP 1 ELSE DUP 0 LT IF DROP -1 ELSE DROP 0 END END END"
      assert Axiom.eval(source <> " 42 sign") == [1]
      assert Axiom.eval(source <> " -7 sign") == [-1]
      assert Axiom.eval(source <> " 0 sign") == [0]
    end

    test "multiple function definitions" do
      source = """
      DEF sq : int -> int DUP MUL END
      DEF double : int -> int DUP ADD END
      5 sq double
      """
      assert Axiom.eval(source) == [50]
    end

    test "function calling another function" do
      source = """
      DEF sq : int -> int DUP MUL END
      DEF sum_sq : [int] -> int { sq } MAP SUM END
      [ 1 2 3 ] sum_sq
      """
      assert Axiom.eval(source) == [14]
    end

    test "Collatz step with contract" do
      source = "DEF step : int -> int DUP 2 MOD 0 EQ IF 2 DIV ELSE 3 MUL 1 ADD END POST DUP 0 GT END 27 step step step"
      # 27 -> 82 -> 41 -> 124
      assert Axiom.eval(source) == [124]
    end

    test "filter + map + sum pipeline with contract" do
      source = """
      DEF sum_sq_odds : [int] -> int
        { 2 MOD 1 EQ } FILTER { SQ } MAP SUM
        POST DUP 0 GTE
      END
      [ 1 2 3 4 5 ] sum_sq_odds
      """
      assert Axiom.eval(source) == [35]
    end

    test "empty list operations" do
      assert Axiom.eval("[ ] SUM") == [0]
      assert Axiom.eval("[ ] LEN") == [0]
      assert Axiom.eval("[ 1 2 3 ] { 0 GT } FILTER") == [[1, 2, 3]]
      assert Axiom.eval("[ 1 2 3 ] { 0 LT } FILTER") == [[]]
    end

    test "stack underflow raises error" do
      assert_raise Axiom.RuntimeError, fn -> Axiom.eval("ADD") end
    end

    test "undefined function raises error" do
      assert_raise Axiom.RuntimeError, fn -> Axiom.eval("5 nope") end
    end

    test "division by zero raises error" do
      assert_raise Axiom.RuntimeError, fn -> Axiom.eval("5 0 DIV") end
    end

    test "nested blocks in filter and map" do
      # Filter evens, then map to double
      source = "[ 1 2 3 4 5 6 ] { 2 MOD 0 EQ } FILTER { DUP ADD } MAP"
      assert Axiom.eval(source) == [[4, 8, 12]]
    end

    test "REPL-style multi-line accumulation" do
      {stack, env} = Axiom.eval_with_env("DEF sq : int -> int DUP MUL END")
      assert stack == []
      {stack, _env} = Axiom.eval_with_env("5 sq", env, stack)
      assert stack == [25]
    end

    test "comments are stripped" do
      source = """
      # this is a comment
      3 4 ADD # inline comment
      """
      assert Axiom.eval(source) == [7]
    end

    test "error messages include position" do
      assert_raise Axiom.RuntimeError, ~r/at word 2/, fn ->
        Axiom.eval("5 nope")
      end
    end

    test ".ax file with comments and multi-line" do
      source = """
      # Sum of squared odds
      DEF ssq : [int] -> int
        { 2 MOD 1 EQ } FILTER
        { SQ } MAP
        SUM
      END

      [ 1 2 3 4 5 6 7 8 9 10 ] ssq
      """
      assert Axiom.eval(source) == [165]
    end
  end

  # ── Iteration ──

  describe "TIMES" do
    test "basic repeat" do
      # Start with 1, double it 4 times: 1 -> 2 -> 4 -> 8 -> 16
      assert Axiom.eval("1 4 { DUP ADD } TIMES") == [16]
    end

    test "zero times does nothing" do
      assert Axiom.eval("42 0 { DUP ADD } TIMES") == [42]
    end

    test "with named function" do
      source = """
      DEF step : int -> int
        DUP 2 MOD 0 EQ IF 2 DIV ELSE 3 MUL 1 ADD END
        POST DUP 0 GT
      END
      27 111 { step } TIMES
      """
      assert Axiom.eval(source) == [1]
    end

    test "block on top of count" do
      assert Axiom.eval("2 3 { DUP MUL } TIMES") == [256]
    end
  end

  describe "WHILE" do
    test "basic while loop" do
      # Start with 1, double while less than 100
      assert Axiom.eval("1 { DUP 100 LT } { DUP ADD } WHILE") == [128]
    end

    test "while with immediate false" do
      # Condition is false immediately — body never runs
      assert Axiom.eval("200 { DUP 100 LT } { DUP ADD } WHILE") == [200]
    end

    test "Collatz until 1" do
      source = """
      DEF step : int -> int
        DUP 2 MOD 0 EQ IF 2 DIV ELSE 3 MUL 1 ADD END
      END
      27 { DUP 1 GT } { step } WHILE
      """
      assert Axiom.eval(source) == [1]
    end

    test "countdown" do
      # 5 -> 4 -> 3 -> 2 -> 1 -> 0, stop when not > 0
      assert Axiom.eval("5 { DUP 0 GT } { 1 SUB } WHILE") == [0]
    end
  end
end
