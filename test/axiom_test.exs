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
      assert func.return_types == [:int]
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
      assert_raise Axiom.StaticError, fn -> Axiom.eval("ADD") end
    end

    test "undefined function raises error" do
      assert_raise Axiom.StaticError, fn -> Axiom.eval("5 nope") end
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
      assert_raise Axiom.StaticError, ~r/at word 2/, fn ->
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

  # ── New operators ──

  describe "RANGE" do
    test "basic range" do
      assert Axiom.eval("5 RANGE") == [[1, 2, 3, 4, 5]]
    end

    test "range 1" do
      assert Axiom.eval("1 RANGE") == [[1]]
    end

    test "range 0" do
      assert Axiom.eval("0 RANGE") == [[]]
    end

    test "range with filter" do
      # Generate 1..10, keep evens
      assert Axiom.eval("10 RANGE { 2 MOD 0 EQ } FILTER") == [[2, 4, 6, 8, 10]]
    end
  end

  describe "SORT and REVERSE" do
    test "sort" do
      assert Axiom.eval("[ 3 1 4 1 5 9 2 6 ] SORT") == [[1, 1, 2, 3, 4, 5, 6, 9]]
    end

    test "reverse" do
      assert Axiom.eval("[ 1 2 3 ] REVERSE") == [[3, 2, 1]]
    end

    test "sort then reverse = descending" do
      assert Axiom.eval("[ 3 1 2 ] SORT REVERSE") == [[3, 2, 1]]
    end
  end

  describe "MIN and MAX" do
    test "min" do
      assert Axiom.eval("3 7 MIN") == [3]
      assert Axiom.eval("7 3 MIN") == [3]
    end

    test "max" do
      assert Axiom.eval("3 7 MAX") == [7]
      assert Axiom.eval("7 3 MAX") == [7]
    end
  end

  describe "PRINT" do
    test "print is non-destructive" do
      # PRINT should leave the value on the stack
      assert Axiom.eval("42 PRINT") == [42]
    end

    test "print in a pipeline" do
      assert Axiom.eval("3 4 ADD PRINT 2 MUL") == [14]
    end
  end

  describe "APPLY" do
    test "basic apply" do
      assert Axiom.eval("5 { DUP ADD } APPLY") == [10]
    end

    test "apply with function from env" do
      source = "DEF sq : int -> int DUP MUL END 5 { sq } APPLY"
      assert Axiom.eval(source) == [25]
    end

    test "apply composes" do
      # Store a block, then apply it
      assert Axiom.eval("3 { DUP MUL } APPLY { DUP ADD } APPLY") == [18]
    end
  end

  describe "REDUCE" do
    test "sum via reduce" do
      assert Axiom.eval("[ 1 2 3 4 5 ] 0 { ADD } REDUCE") == [15]
    end

    test "product via reduce" do
      assert Axiom.eval("[ 1 2 3 4 5 ] 1 { MUL } REDUCE") == [120]
    end

    test "max via reduce" do
      assert Axiom.eval("[ 3 7 2 9 1 ] 0 { MAX } REDUCE") == [9]
    end

    test "reduce with user-defined function" do
      # add_sq: square the element (top), then add to accumulator (second)
      source = """
      DEF add_sq : int int -> int
        SQ ADD
      END
      [ 1 2 3 ] 0 { add_sq } REDUCE
      """
      # 0 + 1² + 2² + 3² = 14
      assert Axiom.eval(source) == [14]
    end

    test "reduce empty list returns initial" do
      assert Axiom.eval("[ ] 42 { ADD } REDUCE") == [42]
    end
  end

  describe "strings" do
    test "lexer tokenizes string literals" do
      assert {:ok, [{:str_lit, "hello", 0}]} = Axiom.Lexer.tokenize("\"hello\"")
    end

    test "lexer tokenizes multi-word strings" do
      assert {:ok, [{:str_lit, "hello world", 0}]} = Axiom.Lexer.tokenize("\"hello world\"")
    end

    test "string literal pushes onto stack" do
      assert Axiom.eval("\"hello\"") == ["hello"]
    end

    test "string with other values" do
      assert Axiom.eval("42 \"hello\"") == ["hello", 42]
    end

    test "SAY is non-destructive" do
      assert Axiom.eval("\"hello\" SAY") == ["hello"]
    end

    test "SAY with non-string" do
      assert Axiom.eval("42 SAY") == [42]
    end

    test "comments inside strings are preserved" do
      assert Axiom.eval("\"hello # world\"") == ["hello # world"]
    end

    test "string EQ" do
      assert Axiom.eval("\"a\" \"a\" EQ") == [true]
      assert Axiom.eval("\"a\" \"b\" EQ") == [false]
    end

    test "CONCAT with strings" do
      assert Axiom.eval("\"hello \" \"world\" CONCAT") == ["hello world"]
    end

    test "LEN on strings" do
      assert Axiom.eval("\"hello\" LEN") == [5]
      assert Axiom.eval("\"\" LEN") == [0]
    end

    test "WORDS splits on whitespace" do
      assert Axiom.eval("\"hello world\" WORDS") == [["hello", "world"]]
      assert Axiom.eval("\"  spaced   out  \" WORDS") == [["spaced", "out"]]
    end

    test "LINES splits on newlines" do
      assert Axiom.eval("\"a\nb\nc\" LINES") == [["a", "b", "c"]]
    end

    test "WORDS LEN counts words" do
      assert Axiom.eval("\"one two three\" WORDS LEN") == [3]
    end

    test "CHARS splits into graphemes" do
      assert Axiom.eval("\"hello\" CHARS") == [["h", "e", "l", "l", "o"]]
    end

    test "CHARS LEN counts characters" do
      assert Axiom.eval("\"hello\" CHARS LEN") == [5]
    end

    test "SPLIT on delimiter" do
      assert Axiom.eval("\"hello,world\" \",\" SPLIT") == [["hello", "world"]]
    end

    test "SPLIT with no match returns single-element list" do
      assert Axiom.eval("\"hello world\" \",\" SPLIT") == [["hello world"]]
    end

    test "TRIM removes surrounding whitespace" do
      assert Axiom.eval("\"  hi  \" TRIM") == ["hi"]
    end

    test "TRIM on clean string is a no-op" do
      assert Axiom.eval("\"hello\" TRIM") == ["hello"]
    end

    test "STARTS_WITH true" do
      assert Axiom.eval("\"hello\" \"he\" STARTS_WITH") == [true]
    end

    test "STARTS_WITH false" do
      assert Axiom.eval("\"hello\" \"wo\" STARTS_WITH") == [false]
    end

    test "SLICE extracts substring" do
      assert Axiom.eval("\"hello\" 1 3 SLICE") == ["ell"]
    end

    test "SLICE from start" do
      assert Axiom.eval("\"hello\" 0 2 SLICE") == ["he"]
    end

    test "TO_INT parses integer string" do
      assert Axiom.eval("\"42\" TO_INT") == [42]
    end

    test "TO_INT parses negative integer" do
      assert Axiom.eval("\"-7\" TO_INT") == [-7]
    end

    test "TO_INT raises on bad input" do
      assert_raise Axiom.RuntimeError, ~r/TO_INT/, fn ->
        Axiom.eval("\"abc\" TO_INT")
      end
    end

    test "TO_FLOAT parses float string" do
      assert Axiom.eval("\"3.14\" TO_FLOAT") == [3.14]
    end

    test "TO_FLOAT raises on bad input" do
      assert_raise Axiom.RuntimeError, ~r/TO_FLOAT/, fn ->
        Axiom.eval("\"abc\" TO_FLOAT")
      end
    end

    test "JOIN with separator" do
      assert Axiom.eval("[ \"a\" \"b\" \"c\" ] \",\" JOIN") == ["a,b,c"]
    end

    test "JOIN with empty separator" do
      assert Axiom.eval("[ \"h\" \"e\" \"l\" \"l\" \"o\" ] \"\" JOIN") == ["hello"]
    end

    test "JOIN on empty list" do
      assert Axiom.eval("[ ] \",\" JOIN") == [""]
    end

    test "CHARS then JOIN round-trips" do
      assert Axiom.eval("\"hello\" CHARS \"\" JOIN") == ["hello"]
    end
  end

  # Shared TYPE definition used across recursive-type tests
  @json_type """
  TYPE json = JNull
            | JBool bool
            | JNum  float
            | JStr  str
            | JArr  [json]
            | JObj  map[str json]
  """

  describe "recursive sum types" do
    test "JNull constructs a zero-field variant" do
      # An int literal before JNull terminates the TYPE declaration so JNull
      # is parsed as an expression, not a 7th variant.
      result = Axiom.eval(@json_type <> "0 DROP JNull")
      assert result == [{:variant, "json", "JNull", []}]
    end

    test "JBool wraps a bool" do
      result = Axiom.eval(@json_type <> "T JBool")
      assert result == [{:variant, "json", "JBool", [true]}]
    end

    test "JNum wraps a float" do
      result = Axiom.eval(@json_type <> "3.14 JNum")
      assert result == [{:variant, "json", "JNum", [3.14]}]
    end

    test "JStr wraps a string" do
      result = Axiom.eval(@json_type <> "\"hello\" JStr")
      assert result == [{:variant, "json", "JStr", ["hello"]}]
    end

    test "JArr wraps a list of json values (recursive)" do
      result = Axiom.eval(@json_type <> "[ JNull T JBool ] JArr")
      assert [{:variant, "json", "JArr", [[jnull, jbool]]}] = result
      assert jnull == {:variant, "json", "JNull", []}
      assert jbool == {:variant, "json", "JBool", [true]}
    end

    test "JObj wraps a map of str -> json" do
      result = Axiom.eval(@json_type <> ~s(M[ "k" JNull ] JObj))
      assert [{:variant, "json", "JObj", [%{"k" => jnull}]}] = result
      assert jnull == {:variant, "json", "JNull", []}
    end

    test "MATCH dispatches on JNull" do
      source = @json_type <> """
      DEF is_null : json -> bool
        MATCH
          JNull { T }
          JBool { DROP F }
          JNum  { DROP F }
          JStr  { DROP F }
          JArr  { DROP F }
          JObj  { DROP F }
        END
      END
      JNull is_null
      """
      assert Axiom.eval(source) == [true]
    end

    test "MATCH extracts JBool payload" do
      source = @json_type <> """
      DEF unwrap_bool : json -> bool
        MATCH
          JNull { F }
          JBool { }
          JNum  { DROP F }
          JStr  { DROP F }
          JArr  { DROP F }
          JObj  { DROP F }
        END
      END
      T JBool unwrap_bool
      """
      assert Axiom.eval(source) == [true]
    end

    test "MATCH extracts JArr payload as [json]" do
      source = @json_type <> """
      DEF json_len : json -> int
        MATCH
          JNull { 0 }
          JBool { DROP 0 }
          JNum  { DROP 0 }
          JStr  { DROP 0 }
          JArr  { LEN }
          JObj  { DROP 0 }
        END
      END
      [ JNull T JBool 1.0 JNum ] JArr json_len
      """
      assert Axiom.eval(source) == [3]
    end

    test "user type as bare variant field (tree-style)" do
      source = """
      TYPE tree = Leaf int | Node tree tree
      DEF depth : tree -> int
        MATCH
          Leaf { DROP 1 }
          Node { depth SWAP depth SWAP MAX 1 ADD }
        END
      END
      3 Leaf  5 Leaf  7 Leaf Node  Node  depth
      """
      assert Axiom.eval(source) == [3]
    end
  end

  # Full JSON scalar parser source (TYPE + helpers + parsers, no demo expressions)
  @json_parser File.read!("examples/json.ax")
               |> String.split("\n# --- Demo ---\n")
               |> hd()

  defp jv(tag, fields), do: {:variant, "json", tag, fields}

  describe "JSON scalar parser" do
    # After any parse_X call: stack = [remaining_chars(top), json_value(below)]
    # So Axiom.eval result list is [remaining, json_value].

    test "parse_null consumes 'null'" do
      result = Axiom.eval(@json_parser <> ~s("null" CHARS parse_null))
      assert result == [[], jv("JNull", [])]
    end

    test "parse_bool consumes 'true'" do
      result = Axiom.eval(@json_parser <> ~s("true" CHARS parse_bool))
      assert result == [[], jv("JBool", [true])]
    end

    test "parse_bool consumes 'false'" do
      result = Axiom.eval(@json_parser <> ~s("false" CHARS parse_bool))
      assert result == [[], jv("JBool", [false])]
    end

    test "parse_number handles integer-valued float" do
      result = Axiom.eval(@json_parser <> ~s("42" CHARS parse_number))
      assert result == [[], jv("JNum", [42.0])]
    end

    test "parse_number handles decimal" do
      result = Axiom.eval(@json_parser <> ~s("3.14" CHARS parse_number))
      assert result == [[], jv("JNum", [3.14])]
    end

    test "parse_number handles negative" do
      result = Axiom.eval(@json_parser <> ~s("-7.5" CHARS parse_number))
      assert result == [[], jv("JNum", [-7.5])]
    end

    test "parse_string returns JStr and remaining chars" do
      # ~S avoids Elixir escape processing — Axiom receives \"hello\" with real backslashes
      result = Axiom.eval(@json_parser <> ~S("\"hello\"" CHARS parse_string))
      assert result == [[], jv("JStr", ["hello"])]
    end

    test "parse_string preserves inner spaces" do
      result = Axiom.eval(@json_parser <> ~S("\"ab cd\"" CHARS parse_string))
      assert result == [[], jv("JStr", ["ab cd"])]
    end

    test "skip_ws drops leading spaces" do
      result = Axiom.eval(@json_parser <> ~s("   hi" CHARS skip_ws))
      assert result == [["h", "i"]]
    end

    test "parse_value dispatches null" do
      result = Axiom.eval(@json_parser <> ~s("null" CHARS parse_value))
      assert result == [[], jv("JNull", [])]
    end

    test "parse_value dispatches true" do
      result = Axiom.eval(@json_parser <> ~s("true" CHARS parse_value))
      assert result == [[], jv("JBool", [true])]
    end

    test "parse_value dispatches false" do
      result = Axiom.eval(@json_parser <> ~s("false" CHARS parse_value))
      assert result == [[], jv("JBool", [false])]
    end

    test "parse_value dispatches number" do
      result = Axiom.eval(@json_parser <> ~s("99.0" CHARS parse_value))
      assert result == [[], jv("JNum", [99.0])]
    end

    test "parse_value dispatches string" do
      result = Axiom.eval(@json_parser <> ~S("\"world\"" CHARS parse_value))
      assert result == [[], jv("JStr", ["world"])]
    end

    test "parse_value skips leading whitespace" do
      result = Axiom.eval(@json_parser <> ~s("  false" CHARS parse_value))
      assert result == [[], jv("JBool", [false])]
    end

    test "parse_value leaves trailing chars on stack" do
      # parse_value consumes 'null' and leaves ',' as remaining
      result = Axiom.eval(@json_parser <> ~s("null," CHARS parse_value))
      assert result == [[","], jv("JNull", [])]
    end
  end

  describe "JSON array/object parser" do
    test "parse_array parses empty array" do
      result = Axiom.eval(@json_parser <> ~s("[]" CHARS parse_array))
      assert result == [[], jv("JArr", [[]])]
    end

    test "parse_array parses single element" do
      result = Axiom.eval(@json_parser <> ~s("[1.0]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JNum", [1.0])]])]
    end

    test "parse_array parses multiple elements" do
      result = Axiom.eval(@json_parser <> ~s("[1.0,2.0,3.0]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JNum", [1.0]), jv("JNum", [2.0]), jv("JNum", [3.0])]])]
    end

    test "parse_array parses boolean elements" do
      result = Axiom.eval(@json_parser <> ~s("[true,false]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JBool", [true]), jv("JBool", [false])]])]
    end

    test "parse_array handles whitespace around elements" do
      result = Axiom.eval(@json_parser <> ~s("[ 1.0 , 2.0 ]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JNum", [1.0]), jv("JNum", [2.0])]])]
    end

    test "parse_array parses nested arrays" do
      result = Axiom.eval(@json_parser <> ~s("[[1.0]]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JArr", [[jv("JNum", [1.0])]])]])]
    end

    test "parse_value dispatches [ to parse_array" do
      result = Axiom.eval(@json_parser <> ~s("[null]" CHARS parse_value))
      assert result == [[], jv("JArr", [[jv("JNull", [])]])]
    end

    test "parse_object parses empty object" do
      result = Axiom.eval(@json_parser <> ~s("{}" CHARS parse_object))
      assert result == [[], jv("JObj", [%{}])]
    end

    test "parse_object parses single key-value pair" do
      result = Axiom.eval(@json_parser <> ~S("{\"x\":1.0}" CHARS parse_object))
      assert result == [[], jv("JObj", [%{"x" => jv("JNum", [1.0])}])]
    end

    test "parse_object parses multiple key-value pairs" do
      result = Axiom.eval(@json_parser <> ~S("{\"a\":true,\"b\":false}" CHARS parse_object))
      assert result == [[], jv("JObj", [%{"a" => jv("JBool", [true]), "b" => jv("JBool", [false])}])]
    end

    test "parse_object handles whitespace" do
      result = Axiom.eval(@json_parser <> ~S("{ \"k\" : null }" CHARS parse_object))
      assert result == [[], jv("JObj", [%{"k" => jv("JNull", [])}])]
    end

    test "parse_value dispatches { to parse_object" do
      result = Axiom.eval(@json_parser <> ~S("{\"n\":1.0}" CHARS parse_value))
      assert result == [[], jv("JObj", [%{"n" => jv("JNum", [1.0])}])]
    end

    test "parse_value handles array of objects" do
      result = Axiom.eval(@json_parser <> ~S("[{\"a\":1.0}]" CHARS parse_value))
      assert result == [[], jv("JArr", [[jv("JObj", [%{"a" => jv("JNum", [1.0])}])]])]
    end
  end

  # Full json.ax source including encoder (no demo expressions)
  @json_full File.read!("examples/json.ax")
             |> String.split("\n# --- Demo:")
             |> hd()

  describe "JSON encoder" do
    test "encode JNull" do
      assert Axiom.eval(@json_full <> " JNull encode") == ["null"]
    end

    test "encode JBool true" do
      assert Axiom.eval(@json_full <> " T JBool encode") == ["true"]
    end

    test "encode JBool false" do
      assert Axiom.eval(@json_full <> " F JBool encode") == ["false"]
    end

    test "encode JNum" do
      assert Axiom.eval(@json_full <> " 42.5 JNum encode") == ["42.5"]
    end

    test "encode JStr" do
      assert Axiom.eval(@json_full <> ~S( "hello" JStr encode)) == [~S("hello")]
    end

    test "encode empty JArr" do
      assert Axiom.eval(@json_full <> " [] JArr encode") == ["[]"]
    end

    test "encode JArr with elements" do
      result = Axiom.eval(@json_full <> " [ 1.0 JNum 2.0 JNum ] JArr encode")
      assert result == ["[1.0,2.0]"]
    end

    test "encode empty JObj" do
      assert Axiom.eval(@json_full <> " M[] JObj encode") == ["{}"]
    end

    test "encode JObj with entry" do
      result = Axiom.eval(@json_full <> ~S( M[] "x" 1.0 JNum PUT JObj encode))
      assert result == [~S({"x":1.0})]
    end

    test "round-trip: parse then encode scalars" do
      for src <- ["null", "true", "false", "42.5", "-7.0"] do
        result = Axiom.eval(@json_full <> ~s( "#{src}" CHARS parse_value DROP encode))
        assert result == [src], "round-trip failed for #{src}"
      end
    end

    test "round-trip: parse then encode array" do
      result = Axiom.eval(@json_full <> ~s( "[1.0,2.0]" CHARS parse_value DROP encode))
      assert result == ["[1.0,2.0]"]
    end

    test "round-trip: parse then encode object" do
      # Single key avoids map-ordering concerns; ~S keeps the \" literal for Axiom
      result = Axiom.eval(@json_full <> ~S( "{\"x\":42.5}" CHARS parse_value DROP encode))
      assert result == [~S({"x":42.5})]
    end

    test "round-trip: parse then encode nested array-of-objects" do
      result = Axiom.eval(@json_full <> ~S( "[{\"n\":1.0}]" CHARS parse_value DROP encode))
      assert result == [~S([{"n":1.0}])]
    end
  end

  describe "VERIFY sum type generation" do
    test "VERIFY works on a json -> json identity function" do
      source = @json_full <> """
      DEF json_id : json -> json
      END
      VERIFY json_id 50
      """
      assert Axiom.eval(source) == []
    end

    test "VERIFY round-trip: encode then parse gives back same value" do
      source = @json_full <> """
      DEF roundtrip : json -> json
        encode CHARS parse_value DROP
      END
      VERIFY roundtrip 50
      """
      assert Axiom.eval(source) == []
    end
  end

  describe "IO" do
    test "ARGV returns empty list by default" do
      Process.delete(:axiom_argv)
      assert Axiom.eval("ARGV") == [[]]
    end

    test "ARGV returns what was set via Process.put" do
      Process.put(:axiom_argv, ["foo", "bar"])
      assert Axiom.eval("ARGV") == [["foo", "bar"]]
      Process.delete(:axiom_argv)
    end

    test "ARGV HEAD gets first arg" do
      Process.put(:axiom_argv, ["hello", "world"])
      assert Axiom.eval("ARGV HEAD") == ["hello"]
      Process.delete(:axiom_argv)
    end

    test "READ_FILE reads a temp file" do
      path = Path.join(System.tmp_dir!(), "axiom_test_read_#{:rand.uniform(100_000)}.txt")
      File.write!(path, "hello from file")

      try do
        assert Axiom.eval("\"#{path}\" READ_FILE") == ["hello from file"]
      after
        File.rm(path)
      end
    end

    test "WRITE_FILE writes to a file" do
      path = Path.join(System.tmp_dir!(), "axiom_test_write_#{:rand.uniform(100_000)}.txt")

      try do
        assert Axiom.eval("\"test content\" \"#{path}\" WRITE_FILE") == []
        assert File.read!(path) == "test content"
      after
        File.rm(path)
      end
    end

    test "READ_FILE with bad path raises RuntimeError" do
      assert_raise Axiom.RuntimeError, ~r/cannot read/, fn ->
        Axiom.eval("\"/no/such/file/ever\" READ_FILE")
      end
    end
  end

  describe "any and void types" do
    test "any parses as a type in function signatures" do
      {:ok, tokens} = Axiom.Lexer.tokenize("DEF id : any -> any DUP DROP END")
      {:ok, [func]} = Axiom.Parser.parse(tokens)
      assert func.param_types == [:any]
      assert func.return_types == [:any]
    end

    test "void parses as a return type" do
      {:ok, tokens} = Axiom.Lexer.tokenize("DEF said : any -> void SAY DROP END")
      {:ok, [func]} = Axiom.Parser.parse(tokens)
      assert func.param_types == [:any]
      assert func.return_types == [:void]
    end

    test "[any] works as a list type" do
      {:ok, [{:type, {:list, :any}, 0}]} = Axiom.Lexer.tokenize("[any]")
    end

    test "any -> void function works end-to-end" do
      source = "DEF said : any -> void SAY DROP END 42 said"
      assert Axiom.eval(source) == []
    end

    test "any -> any function works with different types" do
      source = "DEF id : any -> any END"
      assert Axiom.eval(source <> " 42 id") == [42]
      assert Axiom.eval(source <> " \"hello\" id") == ["hello"]
      assert Axiom.eval(source <> " T id") == [true]
    end
  end

  describe "PRE conditions" do
    test "PRE passing" do
      source = "DEF pos_double : int -> int PRE { DUP 0 GT } DUP ADD END 5 pos_double"
      assert Axiom.eval(source) == [10]
    end

    test "PRE failing" do
      source = "DEF pos_double : int -> int PRE { DUP 0 GT } DUP ADD END -3 pos_double"
      assert_raise Axiom.ContractError, ~r/PRE/, fn -> Axiom.eval(source) end
    end

    test "PRE and POST together" do
      source = """
      DEF safe_double : int -> int
        PRE { DUP 0 GTE }
        DUP ADD
        POST DUP 0 GTE
      END
      5 safe_double
      """
      assert Axiom.eval(source) == [10]
    end

    test "PRE and POST together — PRE fails" do
      source = """
      DEF safe_double : int -> int
        PRE { DUP 0 GTE }
        DUP ADD
        POST DUP 0 GTE
      END
      -1 safe_double
      """
      assert_raise Axiom.ContractError, ~r/PRE/, fn -> Axiom.eval(source) end
    end
  end

  # ── Type checking ──

  describe "type checking" do
    test "int to int function passes" do
      source = "DEF double : int -> int DUP ADD END 5 double"
      assert Axiom.eval(source) == [10]
    end

    test "str to str function passes" do
      source = "DEF echo : str -> str END \"hello\" echo"
      assert Axiom.eval(source) == ["hello"]
    end

    test "any accepts all types" do
      source = "DEF id : any -> any END"
      assert Axiom.eval(source <> " 42 id") == [42]
      assert Axiom.eval(source <> " \"hello\" id") == ["hello"]
      assert Axiom.eval(source <> " T id") == [true]
    end

    test "string to int function raises type error" do
      source = "DEF double : int -> int DUP ADD END \"hello\" double"
      assert_raise Axiom.StaticError, ~r/expected int.*got str/, fn ->
        Axiom.eval(source)
      end
    end

    test "int to str function raises type error" do
      source = "DEF greet : str -> str END 42 greet"
      assert_raise Axiom.StaticError, ~r/expected str.*got int/, fn ->
        Axiom.eval(source)
      end
    end

    test "void function that leaves values raises type error" do
      source = "DEF bad_void : int -> void END 5 bad_void"
      assert_raise Axiom.StaticError, ~r/declared -> void/, fn ->
        Axiom.eval(source)
      end
    end

    test "void function that cleans up works" do
      source = "DEF said : any -> void SAY DROP END 42 said"
      assert Axiom.eval(source) == []
    end

    test "list to [int] function works" do
      source = "DEF sum_list : [int] -> int SUM END [ 1 2 3 ] sum_list"
      assert Axiom.eval(source) == [6]
    end

    test "type check happens before PRE" do
      source = """
      DEF pos_double : int -> int
        PRE { DUP 0 GT }
        DUP ADD
      END
      "hello" pos_double
      """
      # Should raise static type error, not contract error
      assert_raise Axiom.StaticError, ~r/expected int.*got str/, fn -> Axiom.eval(source) end
    end

    test "bool to int function raises type error" do
      source = "DEF double : int -> int DUP ADD END T double"
      assert_raise Axiom.StaticError, ~r/expected int.*got bool/, fn ->
        Axiom.eval(source)
      end
    end

    test "str type in lexer" do
      assert {:ok, [{:type, :str, 0}]} = Axiom.Lexer.tokenize("str")
      assert {:ok, [{:type, {:list, :str}, 0}]} = Axiom.Lexer.tokenize("[str]")
    end

    test "return type mismatch raises type error" do
      source = "DEF bad : int -> int \"oops\" SWAP DROP END 5 bad"
      assert_raise Axiom.StaticError, ~r/return type mismatch.*expected int.*got str/, fn ->
        Axiom.eval(source)
      end
    end

    test "return arity mismatch — too few" do
      source = "DEF bad : int -> int DROP END 5 bad"
      assert_raise Axiom.StaticError, ~r/1 return value.*but body produces 0/, fn ->
        Axiom.eval(source)
      end
    end

    test "return arity mismatch — too many" do
      source = "DEF bad : int -> int DUP END 5 bad"
      assert_raise Axiom.StaticError, ~r/1 return value.*but body produces 2/, fn ->
        Axiom.eval(source)
      end
    end

    test ":any return accepts any single value" do
      source = "DEF id : any -> any END"
      assert Axiom.eval(source <> " 42 id") == [42]
      assert Axiom.eval(source <> " \"hello\" id") == ["hello"]
    end

    test "multi-return parsing" do
      {:ok, tokens} = Axiom.Lexer.tokenize("DEF divmod : int int -> int int DUP ROT SWAP MOD SWAP ROT DIV SWAP END")
      {:ok, [func]} = Axiom.Parser.parse(tokens)
      assert func.return_types == [:int, :int]
      assert func.param_types == [:int, :int]
    end

    test "multi-return enforcement — correct values pass" do
      source = "DEF dup2 : int -> int int DUP END 5 dup2"
      assert Axiom.eval(source) == [5, 5]
    end

    test "multi-return enforcement — wrong count fails" do
      source = "DEF bad : int int -> int int DROP END 3 4 bad"
      assert_raise Axiom.StaticError, ~r/2 return value.*but body produces 1/, fn ->
        Axiom.eval(source)
      end
    end

    test "multi-return type order matters" do
      # Signature says -> str int, but body leaves [int, str] on stack
      source = "DEF bad_order : int str -> str int END \"hello\" 42 bad_order"
      # Body is empty so result_stack is [int, str], expected [str, int]
      # first check: expected str, got int — fails
      assert_raise Axiom.StaticError, ~r/return type mismatch.*expected str.*got int/, fn ->
        Axiom.eval(source)
      end
    end
  end

  describe "wildcard MATCH" do
    test "wildcard catches unmatched constructors" do
      source = """
      TYPE color = Red | Green | Blue
      DEF is_red : color -> bool
        MATCH
          Red { T }
          _ { F }
        END
      END
      Red is_red
      """
      assert Axiom.eval(source) == [true]
    end

    test "wildcard falls through when no named arm matches" do
      source = """
      TYPE color = Red | Green | Blue
      DEF is_red : color -> bool
        MATCH
          Red { T }
          _ { F }
        END
      END
      Blue is_red
      """
      assert Axiom.eval(source) == [false]
    end

    test "wildcard as sole arm matches everything" do
      source = """
      TYPE color = Red | Green | Blue
      DEF always_42 : color -> int
        MATCH
          _ { 42 }
        END
      END
      Green always_42
      """
      assert Axiom.eval(source) == [42]
    end

    test "wildcard discards fields (clean stack)" do
      source = @json_type <> """
      DEF is_null : json -> bool
        MATCH
          JNull { T }
          _ { F }
        END
      END
      3.14 JNum is_null
      """
      # JNum has 1 field (float) — wildcard must discard it
      assert Axiom.eval(source) == [false]
    end

    test "wildcard with multi-field variant discards all fields" do
      source = """
      TYPE shape = Point | Circle float | Rect float float
      DEF is_point : shape -> bool
        MATCH
          Point { T }
          _ { F }
        END
      END
      3.0 4.0 Rect is_point
      """
      # Rect has 2 fields — wildcard must discard both
      assert Axiom.eval(source) == [false]
    end

    test "type checker accepts wildcard as exhaustive" do
      source = @json_type <> """
      DEF is_null : json -> bool
        MATCH
          JNull { T }
          _ { F }
        END
      END
      """
      # Should not raise — wildcard makes it exhaustive
      assert :ok = Axiom.Checker.check(elem(Axiom.Parser.parse(elem(Axiom.Lexer.tokenize(source), 1)), 1))
    end

    test "wildcard works with json.ax helpers" do
      source = @json_full <> """
      DEF jstr_val2 : json -> str
        MATCH
          JStr { }
          _ { "" }
        END
      END
      "hello" JStr jstr_val2
      """
      assert Axiom.eval(source) == ["hello"]
    end

    test "wildcard works with json.ax helpers — fallback case" do
      source = @json_full <> """
      DEF jstr_val2 : json -> str
        MATCH
          JStr { }
          _ { "" }
        END
      END
      JNull jstr_val2
      """
      assert Axiom.eval(source) == [""]
    end
  end
end
