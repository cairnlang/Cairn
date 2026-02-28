defmodule CairnTest do
  use ExUnit.Case

  # ── Lexer ──

  describe "Lexer" do
    test "tokenizes integer literals" do
      assert {:ok, [{:int_lit, 42, 0}]} = Cairn.Lexer.tokenize("42")
      assert {:ok, [{:int_lit, -7, 0}]} = Cairn.Lexer.tokenize("-7")
    end

    test "tokenizes float literals" do
      assert {:ok, [{:float_lit, 3.14, 0}]} = Cairn.Lexer.tokenize("3.14")
    end

    test "tokenizes boolean literals" do
      assert {:ok, [{:bool_lit, true, 0}]} = Cairn.Lexer.tokenize("T")
      assert {:ok, [{:bool_lit, false, 0}]} = Cairn.Lexer.tokenize("F")
    end

    test "tokenizes operators" do
      assert {:ok, [{:op, :add, 0}]} = Cairn.Lexer.tokenize("ADD")
      assert {:ok, [{:op, :filter, 0}]} = Cairn.Lexer.tokenize("FILTER")
      assert {:ok, [{:op, :flat_map, 0}]} = Cairn.Lexer.tokenize("FLAT_MAP")
      assert {:ok, [{:op, :group_by, 0}]} = Cairn.Lexer.tokenize("GROUP_BY")
      assert {:ok, [{:op, :sin, 0}]} = Cairn.Lexer.tokenize("SIN")
      assert {:ok, [{:op, :sqrt, 0}]} = Cairn.Lexer.tokenize("SQRT")
      assert {:ok, [{:op, :pow, 0}]} = Cairn.Lexer.tokenize("POW")
      assert {:ok, [{:op, :pi, 0}]} = Cairn.Lexer.tokenize("PI")
      assert {:ok, [{:op, :e, 0}]} = Cairn.Lexer.tokenize("E")
      assert {:ok, [{:op, :floor, 0}]} = Cairn.Lexer.tokenize("FLOOR")
      assert {:ok, [{:op, :ceil, 0}]} = Cairn.Lexer.tokenize("CEIL")
      assert {:ok, [{:op, :round, 0}]} = Cairn.Lexer.tokenize("ROUND")
      assert {:ok, [{:op, :host_call, 0}]} = Cairn.Lexer.tokenize("HOST_CALL")
      assert {:ok, [{:op, :lower, 0}]} = Cairn.Lexer.tokenize("LOWER")
      assert {:ok, [{:op, :upper, 0}]} = Cairn.Lexer.tokenize("UPPER")
      assert {:ok, [{:op, :ends_with, 0}]} = Cairn.Lexer.tokenize("ENDS_WITH")
      assert {:ok, [{:op, :replace, 0}]} = Cairn.Lexer.tokenize("REPLACE")
      assert {:ok, [{:op, :reverse_str, 0}]} = Cairn.Lexer.tokenize("REVERSE_STR")
      assert {:ok, [{:op, :http_serve, 0}]} = Cairn.Lexer.tokenize("HTTP_SERVE")
      assert {:ok, [{:op, :with_state, 0}]} = Cairn.Lexer.tokenize("WITH_STATE")
      assert {:ok, [{:op, :repeat, 0}]} = Cairn.Lexer.tokenize("REPEAT")
      assert {:ok, [{:op, :step, 0}]} = Cairn.Lexer.tokenize("STEP")
      assert {:ok, [{:op, :dup, 0}]} = Cairn.Lexer.tokenize("DUP")
    end

    test "tokenizes list brackets" do
      assert {:ok, [{:list_open, "[", 0}, {:int_lit, 1, 1}, {:list_close, "]", 2}]} =
               Cairn.Lexer.tokenize("[ 1 ]")
    end

    test "tokenizes block braces" do
      assert {:ok, [{:block_open, "{", 0}, {:op, :dup, 1}, {:block_close, "}", 2}]} =
               Cairn.Lexer.tokenize("{ DUP }")
    end

    test "tokenizes function definition" do
      {:ok, tokens} = Cairn.Lexer.tokenize("DEF double : int -> int DUP ADD END")

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

    test "tokenizes import statement" do
      assert {:ok, [{:import_kw, "IMPORT", 0}, {:str_lit, "lib.crn", 1}]} =
               Cairn.Lexer.tokenize("IMPORT \"lib.crn\"")
    end

    test "tokenizes type annotations" do
      assert {:ok, [{:type, :int, 0}]} = Cairn.Lexer.tokenize("int")
      assert {:ok, [{:type, :float, 0}]} = Cairn.Lexer.tokenize("float")
      assert {:ok, [{:type, {:list, :int}, 0}]} = Cairn.Lexer.tokenize("[int]")
    end

    test "tokenizes identifiers" do
      assert {:ok, [{:ident, "foo", 0}]} = Cairn.Lexer.tokenize("foo")
      assert {:ok, [{:ident, "my_func", 0}]} = Cairn.Lexer.tokenize("my_func")
    end

    test "rejects unknown tokens" do
      assert {:error, _} = Cairn.Lexer.tokenize("@#$")
    end
  end

  # ── Parser ──

  describe "Parser" do
    test "parses bare expression" do
      {:ok, tokens} = Cairn.Lexer.tokenize("3 4 ADD")
      {:ok, [item]} = Cairn.Parser.parse(tokens)
      assert {:expr, _} = item
    end

    test "parses function definition" do
      {:ok, tokens} = Cairn.Lexer.tokenize("DEF double : int -> int DUP ADD END")
      {:ok, [func]} = Cairn.Parser.parse(tokens)
      assert %Cairn.Types.Function{name: "double"} = func
      assert func.param_types == [:int]
      assert func.return_types == [:int]
      assert length(func.body) == 2
      assert func.post_condition == nil
    end

    test "parses function with POST condition" do
      {:ok, tokens} = Cairn.Lexer.tokenize("DEF dbl : int -> int DUP ADD POST 0 GT END")
      {:ok, [func]} = Cairn.Parser.parse(tokens)
      assert func.name == "dbl"
      assert func.post_condition != nil
      assert length(func.post_condition) == 2
    end

    test "parses mixed functions and expressions" do
      source = "DEF sq : int -> int DUP MUL END 5 sq"
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert length(items) == 2
      assert %Cairn.Types.Function{} = hd(items)
      assert {:expr, _} = List.last(items)
    end

    test "parses import statement" do
      {:ok, tokens} = Cairn.Lexer.tokenize("IMPORT \"lib.crn\"")
      {:ok, [{:import, "lib.crn"}]} = Cairn.Parser.parse(tokens)
    end
  end

  # ── DAG ──

  describe "DAG" do
    setup do
      Cairn.DAG.clear()
      :ok
    end

    test "put and get a node" do
      node = %Cairn.Types.Node{op: :add, inputs: ["a", "b"], type: :int, meta: %{}}
      stored = Cairn.DAG.put(node)
      assert stored.hash != nil
      assert Cairn.DAG.get(stored.hash) == stored
    end

    test "content addressing deduplicates" do
      node1 = %Cairn.Types.Node{op: :add, inputs: ["a", "b"], type: :int, meta: %{}}
      node2 = %Cairn.Types.Node{op: :add, inputs: ["a", "b"], type: :int, meta: %{}}
      stored1 = Cairn.DAG.put(node1)
      stored2 = Cairn.DAG.put(node2)
      assert stored1.hash == stored2.hash
    end

    test "different nodes get different hashes" do
      node1 = %Cairn.Types.Node{op: :add, inputs: ["a", "b"], type: :int, meta: %{}}
      node2 = %Cairn.Types.Node{op: :mul, inputs: ["a", "b"], type: :int, meta: %{}}
      stored1 = Cairn.DAG.put(node1)
      stored2 = Cairn.DAG.put(node2)
      assert stored1.hash != stored2.hash
    end
  end

  # ── Evaluator / Integration ──

  describe "eval" do
    test "arithmetic" do
      assert Cairn.eval("3 4 ADD") == [7]
      assert Cairn.eval("10 3 SUB") == [7]
      assert Cairn.eval("3 4 MUL") == [12]
      assert Cairn.eval("10 3 DIV") == [3]
      assert Cairn.eval("10 3 MOD") == [1]
    end

    test "unary ops" do
      assert Cairn.eval("5 SQ") == [25]
      assert Cairn.eval("-3 ABS") == [3]
      assert Cairn.eval("5 NEG") == [-5]
    end

    test "explicit float math ops" do
      assert_in_delta hd(Cairn.eval("0.0 SIN")), 0.0, 1.0e-12
      assert_in_delta hd(Cairn.eval("0.0 COS")), 1.0, 1.0e-12
      assert_in_delta hd(Cairn.eval("PI")), :math.pi(), 1.0e-12
      assert_in_delta hd(Cairn.eval("E")), :math.exp(1.0), 1.0e-12
      assert_in_delta hd(Cairn.eval("3.7 FLOOR")), 3.0, 1.0e-12
      assert_in_delta hd(Cairn.eval("3.2 CEIL")), 4.0, 1.0e-12
      assert_in_delta hd(Cairn.eval("3.6 ROUND")), 4.0, 1.0e-12
      assert_in_delta hd(Cairn.eval("1.0 EXP")), :math.exp(1.0), 1.0e-12
      assert_in_delta hd(Cairn.eval("8.0 2.0 POW")), :math.pow(8.0, 2.0), 1.0e-12
      assert_in_delta hd(Cairn.eval("10.0 LOG")), :math.log(10.0), 1.0e-12
      assert_in_delta hd(Cairn.eval("9.0 SQRT")), 3.0, 1.0e-12
    end

    test "explicit float math validates runtime domains" do
      assert_raise Cairn.RuntimeError, ~r/LOG expects a positive float/, fn ->
        Cairn.eval("0.0 LOG")
      end

      assert_raise Cairn.RuntimeError, ~r/SQRT expects a non-negative float/, fn ->
        Cairn.eval("-1.0 SQRT")
      end
    end

    test "native string helpers cover practical transforms" do
      assert Cairn.eval("\"hello\" UPPER") == ["HELLO"]
      assert Cairn.eval("\"One Two\" LOWER") == ["one two"]
      assert Cairn.eval("\"abc\" REVERSE_STR") == ["cba"]
      assert Cairn.eval("\"ha ha\" \"ha\" \"xo\" REPLACE") == ["xo xo"]
      assert Cairn.eval("\"hello\" \"lo\" ENDS_WITH") == [true]
      assert Cairn.eval("\"hello\" \"he\" ENDS_WITH") == [false]
    end

    test "host interop v1 stays narrow and calls formatting helpers" do
      assert Cairn.eval("[ 42 ] HOST_CALL int_to_string") == ["42"]
      assert Cairn.eval("[ 3.14 ] HOST_CALL float_to_string") == ["3.14"]
    end

    test "comparison" do
      assert Cairn.eval("3 4 EQ") == [false]
      assert Cairn.eval("3 3 EQ") == [true]
      assert Cairn.eval("5 3 GT") == [true]
      assert Cairn.eval("3 5 LT") == [true]
    end

    test "logic" do
      assert Cairn.eval("T T AND") == [true]
      assert Cairn.eval("T F AND") == [false]
      assert Cairn.eval("T F OR") == [true]
      assert Cairn.eval("T NOT") == [false]
    end

    test "stack manipulation" do
      assert Cairn.eval("5 DUP") == [5, 5]
      assert Cairn.eval("3 5 SWAP") == [3, 5]
      assert Cairn.eval("3 5 DROP") == [3]
      assert Cairn.eval("3 5 OVER") == [3, 5, 3]
    end

    test "list construction" do
      assert Cairn.eval("[ 1 2 3 ]") == [[1, 2, 3]]
    end

    test "list operations" do
      assert Cairn.eval("[ 1 2 3 ] SUM") == [6]
      assert Cairn.eval("[ 1 2 3 ] LEN") == [3]
      assert Cairn.eval("[ 1 2 3 ] HEAD") == [1]
      assert Cairn.eval("[ 1 2 3 ] TAIL") == [[2, 3]]
      assert Cairn.eval("[ 1 2 3 ] [ 10 20 30 ] ZIP") == [[[1, 10], [2, 20], [3, 30]]]
      assert Cairn.eval("[ \"a\" \"b\" ] ENUMERATE") == [[[1, "a"], [2, "b"]]]
      assert Cairn.eval("[ 1 2 3 4 ] 2 TAKE") == [[1, 2]]
    end

    test "filter with block" do
      assert Cairn.eval("[ 1 2 3 4 5 ] { 2 MOD 1 EQ } FILTER") == [[1, 3, 5]]
    end

    test "map with block" do
      assert Cairn.eval("[ 1 2 3 ] { SQ } MAP") == [[1, 4, 9]]
    end

    test "flat_map with block" do
      source = "[ 1 2 3 ] { DUP 10 MUL [ ] CONS CONS } FLAT_MAP"
      assert Cairn.eval(source) == [[1, 10, 2, 20, 3, 30]]
    end

    test "flat_map requires a list result from the block" do
      assert_raise Cairn.StaticError, ~r/FLAT_MAP block must return a list/, fn ->
        Cairn.eval("[ 1 2 3 ] { SQ } FLAT_MAP")
      end
    end

    test "find with block returns result" do
      assert Cairn.eval("[ 1 2 3 4 5 ] { 2 MOD 0 EQ } FIND") == [{:variant, "result", "Ok", [2]}]
      assert Cairn.eval("[ 1 3 5 ] { 2 MOD 0 EQ } FIND") == [{:variant, "result", "Err", ["not found"]}]
    end

    test "group_by with block returns grouped map" do
      assert Cairn.eval("[ 1 2 3 4 ] { 2 MOD } GROUP_BY") == [%{0 => [2, 4], 1 => [1, 3]}]
    end

    test "filter then map then sum (the showcase example)" do
      assert Cairn.eval("[ 1 2 3 4 5 ] { 2 MOD 1 EQ } FILTER { SQ } MAP SUM") == [35]
    end

    test "with_state threads local state through a block" do
      assert Cairn.eval("1 { STATE 1 ADD SET_STATE } WITH_STATE") == [2]
      assert Cairn.eval("1 { STATE 1 ADD SET_STATE STATE 2 MUL SET_STATE } WITH_STATE") == [4]
    end

    test "step applies a state helper inside with_state" do
      assert Cairn.eval("""
             DEF bump : int -> int
               1 ADD
             END
             1 { STEP bump } WITH_STATE
             """) == [2]
    end

    test "with_state can thread an ADT-wrapped composite state" do
      assert Cairn.eval("""
             TYPE pair = Pair int int
             1 2 Pair
             {
               STATE
               MATCH
                 Pair { 1 ADD SWAP 10 ADD SWAP Pair SET_STATE }
               END
             } WITH_STATE
             MATCH
               Pair { }
             END
             """) == [12, 2]
    end

    test "constructors accept mixed fields in declaration order" do
      assert Cairn.eval("""
             TYPE mixed = Mixed str int bool
             "peer" 1 T Mixed
             MATCH
               Mixed { }
             END
             """) == ["peer", 1, true]
    end

    test "with_state can thread a variant state machine" do
      assert Cairn.eval("""
             TYPE light = Green | Yellow | Red
             DEF initial_light : light
               Green
             END
             initial_light {
               STATE
               MATCH
                 Green { Yellow SET_STATE }
                 Yellow { Red SET_STATE }
                 Red { Green SET_STATE }
               END
             } WITH_STATE
             MATCH
               Green { "green" }
               Yellow { "yellow" }
               Red { "red" }
             END
             """) == ["yellow"]
    end

    test "with_state block must leave no visible values" do
      assert_raise Cairn.StaticError, ~r/WITH_STATE block must leave no visible values/, fn ->
        Cairn.eval("1 { STATE } WITH_STATE")
      end
    end

    test "state ops require with_state at runtime" do
      assert_raise Cairn.StaticError, ~r/STATE is only available inside WITH_STATE/, fn ->
        Cairn.eval("STATE")
      end

      assert_raise Cairn.StaticError, ~r/SET_STATE is only available inside WITH_STATE/, fn ->
        Cairn.eval("1 SET_STATE")
      end

      assert_raise Cairn.StaticError, ~r/STEP is only available inside WITH_STATE/, fn ->
        Cairn.eval("STEP bump")
      end
    end

    test "if/end true branch" do
      assert Cairn.eval("T IF 42 END") == [42]
    end

    test "if/end false branch (no else)" do
      assert Cairn.eval("F IF 42 END") == []
    end

    test "if/else/end" do
      assert Cairn.eval("T IF 1 ELSE 2 END") == [1]
      assert Cairn.eval("F IF 1 ELSE 2 END") == [2]
    end

    test "function definition and call" do
      source = "DEF double : int -> int DUP ADD END 5 double"
      assert Cairn.eval(source) == [10]
    end

    test "function with POST condition — passing" do
      source = "DEF dbl : int -> int DUP ADD POST 0 GTE END 5 dbl"
      assert Cairn.eval(source) == [10]
    end

    test "function with POST condition — failing" do
      source = "DEF bad : int -> int NEG POST 0 GT END 5 bad"
      assert_raise Cairn.ContractError, fn -> Cairn.eval(source) end
    end

    test "multiple values on stack" do
      assert Cairn.eval("1 2 3") == [3, 2, 1]
    end

    test "chained operations" do
      assert Cairn.eval("2 3 ADD 4 MUL") == [20]
    end
  end

  # ── Integration: multi-function programs ──

  describe "integration" do
    test "IF inside function body" do
      source = "DEF absv : int -> int DUP 0 LT IF NEG END END -5 absv"
      assert Cairn.eval(source) == [5]
    end

    test "IF/ELSE inside function body" do
      source = "DEF sign : int -> int DUP 0 GT IF DROP 1 ELSE DUP 0 LT IF DROP -1 ELSE DROP 0 END END END"
      assert Cairn.eval(source <> " 42 sign") == [1]
      assert Cairn.eval(source <> " -7 sign") == [-1]
      assert Cairn.eval(source <> " 0 sign") == [0]
    end

    test "multiple function definitions" do
      source = """
      DEF sq : int -> int DUP MUL END
      DEF double : int -> int DUP ADD END
      5 sq double
      """
      assert Cairn.eval(source) == [50]
    end

    test "function calling another function" do
      source = """
      DEF sq : int -> int DUP MUL END
      DEF sum_sq : [int] -> int { sq } MAP SUM END
      [ 1 2 3 ] sum_sq
      """
      assert Cairn.eval(source) == [14]
    end

    test "Collatz step with contract" do
      source = "DEF step : int -> int DUP 2 MOD 0 EQ IF 2 DIV ELSE 3 MUL 1 ADD END POST DUP 0 GT END 27 step step step"
      # 27 -> 82 -> 41 -> 124
      assert Cairn.eval(source) == [124]
    end

    test "filter + map + sum pipeline with contract" do
      source = """
      DEF sum_sq_odds : [int] -> int
        { 2 MOD 1 EQ } FILTER { SQ } MAP SUM
        POST DUP 0 GTE
      END
      [ 1 2 3 4 5 ] sum_sq_odds
      """
      assert Cairn.eval(source) == [35]
    end

    test "empty list operations" do
      assert Cairn.eval("[ ] SUM") == [0]
      assert Cairn.eval("[ ] LEN") == [0]
      assert Cairn.eval("[ 1 2 3 ] { 0 GT } FILTER") == [[1, 2, 3]]
      assert Cairn.eval("[ 1 2 3 ] { 0 LT } FILTER") == [[]]
    end

    test "stack underflow raises error" do
      assert_raise Cairn.StaticError, fn -> Cairn.eval("ADD") end
    end

    test "undefined function raises error" do
      assert_raise Cairn.StaticError, fn -> Cairn.eval("5 nope") end
    end

    test "division by zero raises error" do
      assert_raise Cairn.RuntimeError, fn -> Cairn.eval("5 0 DIV") end
    end

    test "nested blocks in filter and map" do
      # Filter evens, then map to double
      source = "[ 1 2 3 4 5 6 ] { 2 MOD 0 EQ } FILTER { DUP ADD } MAP"
      assert Cairn.eval(source) == [[4, 8, 12]]
    end

    test "REPL-style multi-line accumulation" do
      {stack, env} = Cairn.eval_with_env("DEF sq : int -> int DUP MUL END")
      assert stack == []
      {stack, _env} = Cairn.eval_with_env("5 sq", env, stack)
      assert stack == [25]
    end

    test "comments are stripped" do
      source = """
      # this is a comment
      3 4 ADD # inline comment
      """
      assert Cairn.eval(source) == [7]
    end

    test "error messages include position" do
      assert_raise Cairn.StaticError, ~r/at word 2/, fn ->
        Cairn.eval("5 nope")
      end
    end

    test ".crn file with comments and multi-line" do
      source = """
      # Sum of squared odds
      DEF ssq : [int] -> int
        { 2 MOD 1 EQ } FILTER
        { SQ } MAP
        SUM
      END

      [ 1 2 3 4 5 6 7 8 9 10 ] ssq
      """
      assert Cairn.eval(source) == [165]
    end
  end

  describe "IMPORT" do
    test "imports a sibling file and uses its definitions" do
      dir = make_tmp_dir()
      File.write!(Path.join(dir, "math.crn"), "DEF double : int -> int DUP ADD END")
      File.write!(Path.join(dir, "main.crn"), "IMPORT \"math.crn\" 5 double")

      assert Cairn.eval_file(Path.join(dir, "main.crn")) |> elem(0) == [10]
    end

    test "imports are recursive and path resolution is relative to importing file" do
      dir = make_tmp_dir()
      File.mkdir_p!(Path.join(dir, "lib"))

      File.write!(Path.join(dir, "lib/math.crn"), "DEF inc : int -> int 1 ADD END")
      File.write!(Path.join(dir, "lib/helpers.crn"), "IMPORT \"math.crn\" DEF inc2 : int -> int inc inc END")
      File.write!(Path.join(dir, "main.crn"), "IMPORT \"lib/helpers.crn\" 5 inc2")

      assert Cairn.eval_file(Path.join(dir, "main.crn")) |> elem(0) == [7]
    end

    test "duplicate imports are deduplicated" do
      dir = make_tmp_dir()
      File.write!(Path.join(dir, "shared.crn"), "1")
      File.write!(Path.join(dir, "main.crn"), "IMPORT \"shared.crn\" IMPORT \"shared.crn\"")

      assert Cairn.eval_file(Path.join(dir, "main.crn")) |> elem(0) == [1]
    end

    test "import cycles raise a runtime error" do
      dir = make_tmp_dir()
      File.write!(Path.join(dir, "a.crn"), "IMPORT \"b.crn\"")
      File.write!(Path.join(dir, "b.crn"), "IMPORT \"a.crn\"")

      assert_raise Cairn.RuntimeError, ~r/IMPORT cycle detected/, fn ->
        Cairn.eval_file(Path.join(dir, "a.crn"))
      end
    end

    test "missing imported file raises a runtime error" do
      dir = make_tmp_dir()
      File.write!(Path.join(dir, "main.crn"), "IMPORT \"missing.crn\"")

      assert_raise Cairn.RuntimeError, ~r/IMPORT failed to read/, fn ->
        Cairn.eval_file(Path.join(dir, "main.crn"))
      end
    end

    test "IMPORT in source-string mode is rejected" do
      assert_raise Cairn.RuntimeError, ~r/Cairn.eval_file\/3/, fn ->
        Cairn.eval("IMPORT \"foo.crn\"")
      end
    end

    test "repo import example runs end-to-end" do
      assert Cairn.eval_file("examples/imports/main.crn") |> elem(0) == []
    end

    test "file mode auto-loads prelude helpers" do
      dir = make_tmp_dir()
      File.write!(Path.join(dir, "main.crn"), "0 \"42\" TO_INT result_unwrap_or")

      assert Cairn.eval_file(Path.join(dir, "main.crn")) |> elem(0) == [42]
    end

    test "file mode prelude exposes modular helper functions" do
      dir = make_tmp_dir()

      source = """
      " a\\n\\n b \\n\\n" lines_nonempty
      LEN
      0 "42" TO_INT result_unwrap_or
      "PORT" "APP=one\\n# comment\\nPORT=4000\\n" env_map "missing" map_get_or
      "missing" "; note\\n[svc]\\nport=7000\\n" "svc" "port" ini_fetch result_unwrap_or
      """

      File.write!(Path.join(dir, "main.crn"), source)
      assert Cairn.eval_file(Path.join(dir, "main.crn")) |> elem(0) == ["7000", "4000", 42, 2]
    end

    test "user definitions override prelude helpers in file mode" do
      dir = make_tmp_dir()

      source = """
      DEF result_is_ok : result -> bool
        DROP F
      END
      123 Ok result_is_ok
      """

      File.write!(Path.join(dir, "main.crn"), source)
      assert Cairn.eval_file(Path.join(dir, "main.crn")) |> elem(0) == [false]
    end
  end

  describe "mini_grep example" do
    test "supports case-insensitive numbered output via argv" do
      Process.put(:cairn_argv, ["-i", "-n", "cairn", "examples/practical/data/mini_grep.txt"])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {[], _env} = Cairn.eval_file("examples/practical/mini_grep.crn")
        end)

      assert output =~ "1:Cairn"
      assert output =~ "4:gamma cairn"
      assert output =~ "5:delta Cairn"

      Process.delete(:cairn_argv)
    end

    test "supports inverted matches via argv" do
      Process.put(:cairn_argv, ["-v", "Cairn", "examples/practical/data/mini_grep.txt"])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {[], _env} = Cairn.eval_file("examples/practical/mini_grep.crn")
        end)

      assert output =~ "alpha"
      assert output =~ "Beta"
      assert output =~ "gamma cairn"
      refute output =~ "Cairn\n"
      refute output =~ "delta Cairn"

      Process.delete(:cairn_argv)
    end
  end

  describe "mini_env example" do
    test "supports key listing via argv" do
      Process.put(:cairn_argv, ["--keys", "examples/practical/data/app.env"])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {[], _env} = Cairn.eval_file("examples/practical/mini_env.crn")
        end)

      assert output =~ "APP_NAME"
      assert output =~ "PORT"
      assert output =~ "TOKEN"

      Process.delete(:cairn_argv)
    end

    test "supports lookup fallback via argv" do
      Process.put(:cairn_argv, ["examples/practical/data/app.env", "MISSING", "fallback-value"])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {[], _env} = Cairn.eval_file("examples/practical/mini_env.crn")
        end)

      assert output =~ "fallback-value"

      Process.delete(:cairn_argv)
    end
  end

  describe "mini_ini example" do
    test "supports section listing via argv" do
      Process.put(:cairn_argv, ["--sections", "examples/practical/data/app.ini"])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {[], _env} = Cairn.eval_file("examples/practical/mini_ini.crn")
        end)

      assert output =~ "server"
      assert output =~ "auth"

      Process.delete(:cairn_argv)
    end

    test "supports lookup fallback via argv" do
      Process.put(:cairn_argv, ["examples/practical/data/app.ini", "server", "missing", "fallback-value"])

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {[], _env} = Cairn.eval_file("examples/practical/mini_ini.crn")
        end)

      assert output =~ "fallback-value"

      Process.delete(:cairn_argv)
    end
  end

  # ── Iteration ──

  describe "TIMES" do
    test "basic repeat" do
      # Start with 1, double it 4 times: 1 -> 2 -> 4 -> 8 -> 16
      assert Cairn.eval("1 4 { DUP ADD } TIMES") == [16]
    end

    test "zero times does nothing" do
      assert Cairn.eval("42 0 { DUP ADD } TIMES") == [42]
    end

    test "with named function" do
      source = """
      DEF step : int -> int
        DUP 2 MOD 0 EQ IF 2 DIV ELSE 3 MUL 1 ADD END
        POST DUP 0 GT
      END
      27 111 { step } TIMES
      """
      assert Cairn.eval(source) == [1]
    end

    test "block on top of count" do
      assert Cairn.eval("2 3 { DUP MUL } TIMES") == [256]
    end
  end

  describe "REPEAT" do
    test "basic bounded repetition" do
      assert Cairn.eval("1 4 { DUP ADD } REPEAT") == [16]
    end

    test "block on top of count" do
      assert Cairn.eval("2 3 { DUP MUL } REPEAT") == [256]
    end
  end

  describe "WHILE" do
    test "basic while loop" do
      # Start with 1, double while less than 100
      assert Cairn.eval("1 { DUP 100 LT } { DUP ADD } WHILE") == [128]
    end

    test "while with immediate false" do
      # Condition is false immediately — body never runs
      assert Cairn.eval("200 { DUP 100 LT } { DUP ADD } WHILE") == [200]
    end

    test "Collatz until 1" do
      source = """
      DEF step : int -> int
        DUP 2 MOD 0 EQ IF 2 DIV ELSE 3 MUL 1 ADD END
      END
      27 { DUP 1 GT } { step } WHILE
      """
      assert Cairn.eval(source) == [1]
    end

    test "countdown" do
      # 5 -> 4 -> 3 -> 2 -> 1 -> 0, stop when not > 0
      assert Cairn.eval("5 { DUP 0 GT } { 1 SUB } WHILE") == [0]
    end
  end

  # ── New operators ──

  describe "RANGE" do
    test "basic range" do
      assert Cairn.eval("5 RANGE") == [[1, 2, 3, 4, 5]]
    end

    test "range 1" do
      assert Cairn.eval("1 RANGE") == [[1]]
    end

    test "range 0" do
      assert Cairn.eval("0 RANGE") == [[]]
    end

    test "range with filter" do
      # Generate 1..10, keep evens
      assert Cairn.eval("10 RANGE { 2 MOD 0 EQ } FILTER") == [[2, 4, 6, 8, 10]]
    end
  end

  describe "SORT and REVERSE" do
    test "sort" do
      assert Cairn.eval("[ 3 1 4 1 5 9 2 6 ] SORT") == [[1, 1, 2, 3, 4, 5, 6, 9]]
    end

    test "reverse" do
      assert Cairn.eval("[ 1 2 3 ] REVERSE") == [[3, 2, 1]]
    end

    test "sort then reverse = descending" do
      assert Cairn.eval("[ 3 1 2 ] SORT REVERSE") == [[3, 2, 1]]
    end
  end

  describe "MIN and MAX" do
    test "min" do
      assert Cairn.eval("3 7 MIN") == [3]
      assert Cairn.eval("7 3 MIN") == [3]
    end

    test "max" do
      assert Cairn.eval("3 7 MAX") == [7]
      assert Cairn.eval("7 3 MAX") == [7]
    end
  end

  describe "PRINT" do
    test "print is non-destructive" do
      # PRINT should leave the value on the stack
      assert Cairn.eval("42 PRINT") == [42]
    end

    test "print in a pipeline" do
      assert Cairn.eval("3 4 ADD PRINT 2 MUL") == [14]
    end
  end

  describe "APPLY" do
    test "basic apply" do
      assert Cairn.eval("5 { DUP ADD } APPLY") == [10]
    end

    test "apply with function from env" do
      source = "DEF sq : int -> int DUP MUL END 5 { sq } APPLY"
      assert Cairn.eval(source) == [25]
    end

    test "apply composes" do
      # Store a block, then apply it
      assert Cairn.eval("3 { DUP MUL } APPLY { DUP ADD } APPLY") == [18]
    end
  end

  describe "REDUCE" do
    test "sum via reduce" do
      assert Cairn.eval("[ 1 2 3 4 5 ] 0 { ADD } REDUCE") == [15]
    end

    test "product via reduce" do
      assert Cairn.eval("[ 1 2 3 4 5 ] 1 { MUL } REDUCE") == [120]
    end

    test "max via reduce" do
      assert Cairn.eval("[ 3 7 2 9 1 ] 0 { MAX } REDUCE") == [9]
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
      assert Cairn.eval(source) == [14]
    end

    test "reduce empty list returns initial" do
      assert Cairn.eval("[ ] 42 { ADD } REDUCE") == [42]
    end
  end

  describe "strings" do
    test "lexer tokenizes string literals" do
      assert {:ok, [{:str_lit, "hello", 0}]} = Cairn.Lexer.tokenize("\"hello\"")
    end

    test "lexer tokenizes multi-word strings" do
      assert {:ok, [{:str_lit, "hello world", 0}]} = Cairn.Lexer.tokenize("\"hello world\"")
    end

    test "string literal pushes onto stack" do
      assert Cairn.eval("\"hello\"") == ["hello"]
    end

    test "string with other values" do
      assert Cairn.eval("42 \"hello\"") == ["hello", 42]
    end

    test "SAY is non-destructive" do
      assert Cairn.eval("\"hello\" SAY") == ["hello"]
    end

    test "SAY with non-string" do
      assert Cairn.eval("42 SAY") == [42]
    end

    test "comments inside strings are preserved" do
      assert Cairn.eval("\"hello # world\"") == ["hello # world"]
    end

    test "string EQ" do
      assert Cairn.eval("\"a\" \"a\" EQ") == [true]
      assert Cairn.eval("\"a\" \"b\" EQ") == [false]
    end

    test "CONCAT with strings" do
      assert Cairn.eval("\"hello \" \"world\" CONCAT") == ["hello world"]
    end

    test "LEN on strings" do
      assert Cairn.eval("\"hello\" LEN") == [5]
      assert Cairn.eval("\"\" LEN") == [0]
    end

    test "WORDS splits on whitespace" do
      assert Cairn.eval("\"hello world\" WORDS") == [["hello", "world"]]
      assert Cairn.eval("\"  spaced   out  \" WORDS") == [["spaced", "out"]]
    end

    test "LINES splits on newlines" do
      assert Cairn.eval("\"a\nb\nc\" LINES") == [["a", "b", "c"]]
    end

    test "WORDS LEN counts words" do
      assert Cairn.eval("\"one two three\" WORDS LEN") == [3]
    end

    test "CHARS splits into graphemes" do
      assert Cairn.eval("\"hello\" CHARS") == [["h", "e", "l", "l", "o"]]
    end

    test "CHARS LEN counts characters" do
      assert Cairn.eval("\"hello\" CHARS LEN") == [5]
    end

    test "SPLIT on delimiter" do
      assert Cairn.eval("\"hello,world\" \",\" SPLIT") == [["hello", "world"]]
    end

    test "SPLIT with no match returns single-element list" do
      assert Cairn.eval("\"hello world\" \",\" SPLIT") == [["hello world"]]
    end

    test "TRIM removes surrounding whitespace" do
      assert Cairn.eval("\"  hi  \" TRIM") == ["hi"]
    end

    test "TRIM on clean string is a no-op" do
      assert Cairn.eval("\"hello\" TRIM") == ["hello"]
    end

    test "STARTS_WITH true" do
      assert Cairn.eval("\"hello\" \"he\" STARTS_WITH") == [true]
    end

    test "STARTS_WITH false" do
      assert Cairn.eval("\"hello\" \"wo\" STARTS_WITH") == [false]
    end

    test "SLICE extracts substring" do
      assert Cairn.eval("\"hello\" 1 3 SLICE") == ["ell"]
    end

    test "SLICE from start" do
      assert Cairn.eval("\"hello\" 0 2 SLICE") == ["he"]
    end

    test "TO_INT returns Ok integer on success" do
      assert Cairn.eval("\"42\" TO_INT") == [{:variant, "result", "Ok", [42]}]
    end

    test "TO_INT returns Err on bad input" do
      assert [{:variant, "result", "Err", [_]}] = Cairn.eval("\"abc\" TO_INT")
    end

    test "TO_INT! parses integer string" do
      assert Cairn.eval("\"42\" TO_INT!") == [42]
    end

    test "TO_INT! raises on bad input" do
      assert_raise Cairn.RuntimeError, ~r/TO_INT!/, fn ->
        Cairn.eval("\"abc\" TO_INT!")
      end
    end

    test "TO_FLOAT returns Ok float on success" do
      assert Cairn.eval("\"3.14\" TO_FLOAT") == [{:variant, "result", "Ok", [3.14]}]
    end

    test "TO_FLOAT! raises on bad input" do
      assert_raise Cairn.RuntimeError, ~r/TO_FLOAT!/, fn ->
        Cairn.eval("\"abc\" TO_FLOAT!")
      end
    end

    test "JOIN with separator" do
      assert Cairn.eval("[ \"a\" \"b\" \"c\" ] \",\" JOIN") == ["a,b,c"]
    end

    test "JOIN with empty separator" do
      assert Cairn.eval("[ \"h\" \"e\" \"l\" \"l\" \"o\" ] \"\" JOIN") == ["hello"]
    end

    test "JOIN on empty list" do
      assert Cairn.eval("[ ] \",\" JOIN") == [""]
    end

    test "CHARS then JOIN round-trips" do
      assert Cairn.eval("\"hello\" CHARS \"\" JOIN") == ["hello"]
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
      result = Cairn.eval(@json_type <> "0 DROP JNull")
      assert result == [{:variant, "json", "JNull", []}]
    end

    test "JBool wraps a bool" do
      result = Cairn.eval(@json_type <> "T JBool")
      assert result == [{:variant, "json", "JBool", [true]}]
    end

    test "JNum wraps a float" do
      result = Cairn.eval(@json_type <> "3.14 JNum")
      assert result == [{:variant, "json", "JNum", [3.14]}]
    end

    test "JStr wraps a string" do
      result = Cairn.eval(@json_type <> "\"hello\" JStr")
      assert result == [{:variant, "json", "JStr", ["hello"]}]
    end

    test "JArr wraps a list of json values (recursive)" do
      result = Cairn.eval(@json_type <> "[ JNull T JBool ] JArr")
      assert [{:variant, "json", "JArr", [[jnull, jbool]]}] = result
      assert jnull == {:variant, "json", "JNull", []}
      assert jbool == {:variant, "json", "JBool", [true]}
    end

    test "JObj wraps a map of str -> json" do
      result = Cairn.eval(@json_type <> ~s(M[ "k" JNull ] JObj))
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
      assert Cairn.eval(source) == [true]
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
      assert Cairn.eval(source) == [true]
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
      assert Cairn.eval(source) == [3]
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
      assert Cairn.eval(source) == [3]
    end
  end

  # Full JSON parser/encoder core source (no demo expressions)
  @json_parser File.read!("examples/json/core.crn")

  defp make_tmp_dir do
    dir =
      Path.join(
        System.tmp_dir!(),
        "cairn_import_test_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp jv(tag, fields), do: {:variant, "json", tag, fields}

  describe "JSON scalar parser" do
    # After any parse_X call: stack = [remaining_chars(top), json_value(below)]
    # So Cairn.eval result list is [remaining, json_value].

    test "parse_null consumes 'null'" do
      result = Cairn.eval(@json_parser <> ~s("null" CHARS parse_null))
      assert result == [[], jv("JNull", [])]
    end

    test "parse_bool consumes 'true'" do
      result = Cairn.eval(@json_parser <> ~s("true" CHARS parse_bool))
      assert result == [[], jv("JBool", [true])]
    end

    test "parse_bool consumes 'false'" do
      result = Cairn.eval(@json_parser <> ~s("false" CHARS parse_bool))
      assert result == [[], jv("JBool", [false])]
    end

    test "parse_number handles integer-valued float" do
      result = Cairn.eval(@json_parser <> ~s("42" CHARS parse_number))
      assert result == [[], jv("JNum", [42.0])]
    end

    test "parse_number handles decimal" do
      result = Cairn.eval(@json_parser <> ~s("3.14" CHARS parse_number))
      assert result == [[], jv("JNum", [3.14])]
    end

    test "parse_number handles negative" do
      result = Cairn.eval(@json_parser <> ~s("-7.5" CHARS parse_number))
      assert result == [[], jv("JNum", [-7.5])]
    end

    test "parse_string returns JStr and remaining chars" do
      # ~S avoids Elixir escape processing — Cairn receives \"hello\" with real backslashes
      result = Cairn.eval(@json_parser <> ~S("\"hello\"" CHARS parse_string))
      assert result == [[], jv("JStr", ["hello"])]
    end

    test "parse_string preserves inner spaces" do
      result = Cairn.eval(@json_parser <> ~S("\"ab cd\"" CHARS parse_string))
      assert result == [[], jv("JStr", ["ab cd"])]
    end

    test "skip_ws drops leading spaces" do
      result = Cairn.eval(@json_parser <> ~s("   hi" CHARS skip_ws))
      assert result == [["h", "i"]]
    end

    test "parse_value dispatches null" do
      result = Cairn.eval(@json_parser <> ~s("null" CHARS parse_value))
      assert result == [[], jv("JNull", [])]
    end

    test "parse_value dispatches true" do
      result = Cairn.eval(@json_parser <> ~s("true" CHARS parse_value))
      assert result == [[], jv("JBool", [true])]
    end

    test "parse_value dispatches false" do
      result = Cairn.eval(@json_parser <> ~s("false" CHARS parse_value))
      assert result == [[], jv("JBool", [false])]
    end

    test "parse_value dispatches number" do
      result = Cairn.eval(@json_parser <> ~s("99.0" CHARS parse_value))
      assert result == [[], jv("JNum", [99.0])]
    end

    test "parse_value dispatches string" do
      result = Cairn.eval(@json_parser <> ~S("\"world\"" CHARS parse_value))
      assert result == [[], jv("JStr", ["world"])]
    end

    test "parse_value skips leading whitespace" do
      result = Cairn.eval(@json_parser <> ~s("  false" CHARS parse_value))
      assert result == [[], jv("JBool", [false])]
    end

    test "parse_value leaves trailing chars on stack" do
      # parse_value consumes 'null' and leaves ',' as remaining
      result = Cairn.eval(@json_parser <> ~s("null," CHARS parse_value))
      assert result == [[","], jv("JNull", [])]
    end
  end

  describe "JSON array/object parser" do
    test "parse_array parses empty array" do
      result = Cairn.eval(@json_parser <> ~s("[]" CHARS parse_array))
      assert result == [[], jv("JArr", [[]])]
    end

    test "parse_array parses single element" do
      result = Cairn.eval(@json_parser <> ~s("[1.0]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JNum", [1.0])]])]
    end

    test "parse_array parses multiple elements" do
      result = Cairn.eval(@json_parser <> ~s("[1.0,2.0,3.0]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JNum", [1.0]), jv("JNum", [2.0]), jv("JNum", [3.0])]])]
    end

    test "parse_array parses boolean elements" do
      result = Cairn.eval(@json_parser <> ~s("[true,false]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JBool", [true]), jv("JBool", [false])]])]
    end

    test "parse_array handles whitespace around elements" do
      result = Cairn.eval(@json_parser <> ~s("[ 1.0 , 2.0 ]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JNum", [1.0]), jv("JNum", [2.0])]])]
    end

    test "parse_array parses nested arrays" do
      result = Cairn.eval(@json_parser <> ~s("[[1.0]]" CHARS parse_array))
      assert result == [[], jv("JArr", [[jv("JArr", [[jv("JNum", [1.0])]])]])]
    end

    test "parse_value dispatches [ to parse_array" do
      result = Cairn.eval(@json_parser <> ~s("[null]" CHARS parse_value))
      assert result == [[], jv("JArr", [[jv("JNull", [])]])]
    end

    test "parse_object parses empty object" do
      result = Cairn.eval(@json_parser <> ~s("{}" CHARS parse_object))
      assert result == [[], jv("JObj", [%{}])]
    end

    test "parse_object parses single key-value pair" do
      result = Cairn.eval(@json_parser <> ~S("{\"x\":1.0}" CHARS parse_object))
      assert result == [[], jv("JObj", [%{"x" => jv("JNum", [1.0])}])]
    end

    test "parse_object parses multiple key-value pairs" do
      result = Cairn.eval(@json_parser <> ~S("{\"a\":true,\"b\":false}" CHARS parse_object))
      assert result == [[], jv("JObj", [%{"a" => jv("JBool", [true]), "b" => jv("JBool", [false])}])]
    end

    test "parse_object handles whitespace" do
      result = Cairn.eval(@json_parser <> ~S("{ \"k\" : null }" CHARS parse_object))
      assert result == [[], jv("JObj", [%{"k" => jv("JNull", [])}])]
    end

    test "parse_value dispatches { to parse_object" do
      result = Cairn.eval(@json_parser <> ~S("{\"n\":1.0}" CHARS parse_value))
      assert result == [[], jv("JObj", [%{"n" => jv("JNum", [1.0])}])]
    end

    test "parse_value handles array of objects" do
      result = Cairn.eval(@json_parser <> ~S("[{\"a\":1.0}]" CHARS parse_value))
      assert result == [[], jv("JArr", [[jv("JObj", [%{"a" => jv("JNum", [1.0])}])]])]
    end
  end

  # Full parser/encoder source (no demo expressions)
  @json_full File.read!("examples/json/core.crn")

  describe "JSON encoder" do
    test "encode JNull" do
      assert Cairn.eval(@json_full <> " JNull encode") == ["null"]
    end

    test "encode JBool true" do
      assert Cairn.eval(@json_full <> " T JBool encode") == ["true"]
    end

    test "encode JBool false" do
      assert Cairn.eval(@json_full <> " F JBool encode") == ["false"]
    end

    test "encode JNum" do
      assert Cairn.eval(@json_full <> " 42.5 JNum encode") == ["42.5"]
    end

    test "encode JStr" do
      assert Cairn.eval(@json_full <> ~S( "hello" JStr encode)) == [~S("hello")]
    end

    test "encode empty JArr" do
      assert Cairn.eval(@json_full <> " [] JArr encode") == ["[]"]
    end

    test "encode JArr with elements" do
      result = Cairn.eval(@json_full <> " [ 1.0 JNum 2.0 JNum ] JArr encode")
      assert result == ["[1.0,2.0]"]
    end

    test "encode empty JObj" do
      assert Cairn.eval(@json_full <> " M[] JObj encode") == ["{}"]
    end

    test "encode JObj with entry" do
      result = Cairn.eval(@json_full <> ~S( M[] "x" 1.0 JNum PUT JObj encode))
      assert result == [~S({"x":1.0})]
    end

    test "round-trip: parse then encode scalars" do
      for src <- ["null", "true", "false", "42.5", "-7.0"] do
        result = Cairn.eval(@json_full <> ~s( "#{src}" CHARS parse_value DROP encode))
        assert result == [src], "round-trip failed for #{src}"
      end
    end

    test "round-trip: parse then encode array" do
      result = Cairn.eval(@json_full <> ~s( "[1.0,2.0]" CHARS parse_value DROP encode))
      assert result == ["[1.0,2.0]"]
    end

    test "round-trip: parse then encode object" do
      # Single key avoids map-ordering concerns; ~S keeps the \" literal for Cairn
      result = Cairn.eval(@json_full <> ~S( "{\"x\":42.5}" CHARS parse_value DROP encode))
      assert result == [~S({"x":42.5})]
    end

    test "round-trip: parse then encode nested array-of-objects" do
      result = Cairn.eval(@json_full <> ~S( "[{\"n\":1.0}]" CHARS parse_value DROP encode))
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
      assert Cairn.eval(source) == []
    end

    test "VERIFY round-trip: encode then parse gives back same value" do
      source = @json_full <> """
      DEF roundtrip : json -> json
        encode CHARS parse_value DROP
      END
      VERIFY roundtrip 50
      """
      assert Cairn.eval(source) == []
    end
  end

  describe "IO" do
    test "ARGV returns empty list by default" do
      Process.delete(:cairn_argv)
      assert Cairn.eval("ARGV") == [[]]
    end

    test "ARGV returns what was set via Process.put" do
      Process.put(:cairn_argv, ["foo", "bar"])
      assert Cairn.eval("ARGV") == [["foo", "bar"]]
      Process.delete(:cairn_argv)
    end

    test "ARGV HEAD gets first arg" do
      Process.put(:cairn_argv, ["hello", "world"])
      assert Cairn.eval("ARGV HEAD") == ["hello"]
      Process.delete(:cairn_argv)
    end

    test "READ_FILE reads a temp file" do
      path = Path.join(System.tmp_dir!(), "cairn_test_read_#{:rand.uniform(100_000)}.txt")
      File.write!(path, "hello from file")

      try do
        assert Cairn.eval("\"#{path}\" READ_FILE") ==
                 [{:variant, "result", "Ok", ["hello from file"]}]
      after
        File.rm(path)
      end
    end

    test "WRITE_FILE writes to a file" do
      path = Path.join(System.tmp_dir!(), "cairn_test_write_#{:rand.uniform(100_000)}.txt")

      try do
        assert Cairn.eval("\"test content\" \"#{path}\" WRITE_FILE") ==
                 [{:variant, "result", "Ok", [true]}]
        assert File.read!(path) == "test content"
      after
        File.rm(path)
      end
    end

    test "READ_FILE returns Err on bad path" do
      assert [{:variant, "result", "Err", [_]}] =
               Cairn.eval("\"/no/such/file/ever\" READ_FILE")
    end

    test "READ_FILE! with bad path raises RuntimeError" do
      assert_raise Cairn.RuntimeError, ~r/cannot read/, fn ->
        Cairn.eval("\"/no/such/file/ever\" READ_FILE!")
      end
    end
  end

  describe "any and void types" do
    test "any parses as a type in function signatures" do
      {:ok, tokens} = Cairn.Lexer.tokenize("DEF id : any -> any DUP DROP END")
      {:ok, [func]} = Cairn.Parser.parse(tokens)
      assert func.param_types == [:any]
      assert func.return_types == [:any]
    end

    test "void parses as a return type" do
      {:ok, tokens} = Cairn.Lexer.tokenize("DEF said : any -> void SAY DROP END")
      {:ok, [func]} = Cairn.Parser.parse(tokens)
      assert func.param_types == [:any]
      assert func.return_types == [:void]
    end

    test "[any] works as a list type" do
      {:ok, [{:type, {:list, :any}, 0}]} = Cairn.Lexer.tokenize("[any]")
    end

    test "any -> void function works end-to-end" do
      source = "DEF said : any -> void SAY DROP END 42 said"
      assert Cairn.eval(source) == []
    end

    test "any -> any function works with different types" do
      source = "DEF id : any -> any END"
      assert Cairn.eval(source <> " 42 id") == [42]
      assert Cairn.eval(source <> " \"hello\" id") == ["hello"]
      assert Cairn.eval(source <> " T id") == [true]
    end
  end

  describe "PRE conditions" do
    test "PRE passing" do
      source = "DEF pos_double : int -> int PRE { DUP 0 GT } DUP ADD END 5 pos_double"
      assert Cairn.eval(source) == [10]
    end

    test "PRE failing" do
      source = "DEF pos_double : int -> int PRE { DUP 0 GT } DUP ADD END -3 pos_double"
      assert_raise Cairn.ContractError, ~r/PRE/, fn -> Cairn.eval(source) end
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
      assert Cairn.eval(source) == [10]
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
      assert_raise Cairn.ContractError, ~r/PRE/, fn -> Cairn.eval(source) end
    end
  end

  # ── Type checking ──

  describe "type checking" do
    test "int to int function passes" do
      source = "DEF double : int -> int DUP ADD END 5 double"
      assert Cairn.eval(source) == [10]
    end

    test "str to str function passes" do
      source = "DEF echo : str -> str END \"hello\" echo"
      assert Cairn.eval(source) == ["hello"]
    end

    test "any accepts all types" do
      source = "DEF id : any -> any END"
      assert Cairn.eval(source <> " 42 id") == [42]
      assert Cairn.eval(source <> " \"hello\" id") == ["hello"]
      assert Cairn.eval(source <> " T id") == [true]
    end

    test "string to int function raises type error" do
      source = "DEF double : int -> int DUP ADD END \"hello\" double"
      assert_raise Cairn.StaticError, ~r/expected int.*got str/, fn ->
        Cairn.eval(source)
      end
    end

    test "int to str function raises type error" do
      source = "DEF greet : str -> str END 42 greet"
      assert_raise Cairn.StaticError, ~r/expected str.*got int/, fn ->
        Cairn.eval(source)
      end
    end

    test "void function that leaves values raises type error" do
      source = "DEF bad_void : int -> void END 5 bad_void"
      assert_raise Cairn.StaticError, ~r/declared -> void/, fn ->
        Cairn.eval(source)
      end
    end

    test "void function that cleans up works" do
      source = "DEF said : any -> void SAY DROP END 42 said"
      assert Cairn.eval(source) == []
    end

    test "list to [int] function works" do
      source = "DEF sum_list : [int] -> int SUM END [ 1 2 3 ] sum_list"
      assert Cairn.eval(source) == [6]
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
      assert_raise Cairn.StaticError, ~r/expected int.*got str/, fn -> Cairn.eval(source) end
    end

    test "bool to int function raises type error" do
      source = "DEF double : int -> int DUP ADD END T double"
      assert_raise Cairn.StaticError, ~r/expected int.*got bool/, fn ->
        Cairn.eval(source)
      end
    end

    test "str type in lexer" do
      assert {:ok, [{:type, :str, 0}]} = Cairn.Lexer.tokenize("str")
      assert {:ok, [{:type, {:list, :str}, 0}]} = Cairn.Lexer.tokenize("[str]")
    end

    test "return type mismatch raises type error" do
      source = "DEF bad : int -> int \"oops\" SWAP DROP END 5 bad"
      assert_raise Cairn.StaticError, ~r/return type mismatch.*expected int.*got str/, fn ->
        Cairn.eval(source)
      end
    end

    test "return arity mismatch — too few" do
      source = "DEF bad : int -> int DROP END 5 bad"
      assert_raise Cairn.StaticError, ~r/1 return value.*but body produces 0/, fn ->
        Cairn.eval(source)
      end
    end

    test "return arity mismatch — too many" do
      source = "DEF bad : int -> int DUP END 5 bad"
      assert_raise Cairn.StaticError, ~r/1 return value.*but body produces 2/, fn ->
        Cairn.eval(source)
      end
    end

    test ":any return accepts any single value" do
      source = "DEF id : any -> any END"
      assert Cairn.eval(source <> " 42 id") == [42]
      assert Cairn.eval(source <> " \"hello\" id") == ["hello"]
    end

    test "multi-return parsing" do
      {:ok, tokens} = Cairn.Lexer.tokenize("DEF divmod : int int -> int int DUP ROT SWAP MOD SWAP ROT DIV SWAP END")
      {:ok, [func]} = Cairn.Parser.parse(tokens)
      assert func.return_types == [:int, :int]
      assert func.param_types == [:int, :int]
    end

    test "multi-return enforcement — correct values pass" do
      source = "DEF dup2 : int -> int int DUP END 5 dup2"
      assert Cairn.eval(source) == [5, 5]
    end

    test "multi-return enforcement — wrong count fails" do
      source = "DEF bad : int int -> int int DROP END 3 4 bad"
      assert_raise Cairn.StaticError, ~r/2 return value.*but body produces 1/, fn ->
        Cairn.eval(source)
      end
    end

    test "multi-return type order matters" do
      # Signature says -> str int, but body leaves [int, str] on stack
      source = "DEF bad_order : int str -> str int END \"hello\" 42 bad_order"
      # Body is empty so result_stack is [int, str], expected [str, int]
      # first check: expected str, got int — fails
      assert_raise Cairn.StaticError, ~r/return type mismatch.*expected str.*got int/, fn ->
        Cairn.eval(source)
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
      assert Cairn.eval(source) == [true]
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
      assert Cairn.eval(source) == [false]
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
      assert Cairn.eval(source) == [42]
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
      assert Cairn.eval(source) == [false]
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
      assert Cairn.eval(source) == [false]
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
      assert :ok = Cairn.Checker.check(elem(Cairn.Parser.parse(elem(Cairn.Lexer.tokenize(source), 1)), 1))
    end

    test "wildcard works with json.crn helpers" do
      source = @json_full <> """
      DEF jstr_val2 : json -> str
        MATCH
          JStr { }
          _ { "" }
        END
      END
      "hello" JStr jstr_val2
      """
      assert Cairn.eval(source) == ["hello"]
    end

    test "wildcard works with json.crn helpers — fallback case" do
      source = @json_full <> """
      DEF jstr_val2 : json -> str
        MATCH
          JStr { }
          _ { "" }
        END
      END
      JNull jstr_val2
      """
      assert Cairn.eval(source) == [""]
    end
  end

  # ── PROVE with IF/ELSE ──

  describe "PROVE with IF/ELSE" do
    test "PROVE function using IF (abs) is proven" do
      source = """
      DEF my_abs : int -> int
        DUP 0 LT IF NEG END
        POST DUP 0 GTE
      END
      PROVE my_abs
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Cairn.eval(source)
      end)
      assert output =~ "PROVEN"
    end

    test "PROVE function using IF/ELSE is proven" do
      source = """
      DEF safe_abs : int -> int
        DUP 0 GTE IF ELSE NEG END
        POST DUP 0 GTE
      END
      PROVE safe_abs
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Cairn.eval(source)
      end)
      assert output =~ "PROVEN"
    end

    test "PROVE function using IF/ELSE is disproven" do
      source = """
      DEF bad_branch : int -> int
        DUP 0 GT IF 1 ADD ELSE 1 SUB END
        POST DUP 0 GT
      END
      PROVE bad_branch
      """

      assert_raise Cairn.ContractError, ~r/DISPROVEN/, fn ->
        Cairn.eval(source)
      end
    end

    test "PROVE function using ABS is proven" do
      source = """
      DEF use_abs : int -> int
        ABS
        POST DUP 0 GTE
      END
      PROVE use_abs
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Cairn.eval(source)
      end)
      assert output =~ "PROVEN"
    end

    test "PROVE function using MIN is proven" do
      source = """
      DEF clamp_top : int int -> int
        PRE { OVER 0 GTE SWAP 0 GT AND }
        MIN
        POST DUP 0 GTE
      END
      PROVE clamp_top
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Cairn.eval(source)
      end)
      assert output =~ "PROVEN"
    end
  end

  # ── PROVE with function inlining ──

  describe "PROVE with function call inlining" do
    test "PROVE function that calls another function (distance via abs)" do
      source = """
      DEF my_abs : int -> int
        DUP 0 LT IF NEG END
      END

      DEF distance : int int -> int
        SUB my_abs
        POST DUP 0 GTE
      END
      PROVE distance
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Cairn.eval(source)
      end)
      assert output =~ "PROVEN"
    end

    test "PROVE chained function calls" do
      source = """
      DEF double : int -> int
        DUP ADD
      END

      DEF quadruple : int -> int
        double double
        POST DUP 0 GTE
      END
      PROVE quadruple
      """

      # quadruple(x) = 4x, which is NOT always >= 0 (negative inputs)
      assert_raise Cairn.ContractError, ~r/DISPROVEN/, fn ->
        Cairn.eval(source)
      end
    end

    test "PROVE with PRE makes chained calls provable" do
      source = """
      DEF double : int -> int
        DUP ADD
      END

      DEF quadruple : int -> int
        PRE { DUP 0 GTE }
        double double
        POST DUP 0 GTE
      END
      PROVE quadruple
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Cairn.eval(source)
      end)
      assert output =~ "PROVEN"
    end
  end

  # ── LET bindings ──

  describe "LET bindings" do
    test "binds and retrieves a value" do
      assert Cairn.eval("42 LET x x") == [42]
    end

    test "multiple bindings" do
      assert Cairn.eval("1 LET a 2 LET b a b ADD") == [3]
    end

    test "rebinding shadows previous value" do
      assert Cairn.eval("1 LET x 2 LET x x") == [2]
    end

    test "LET with strings" do
      assert Cairn.eval(~s|"hello" LET s s|) == ["hello"]
    end

    test "LET with booleans" do
      assert Cairn.eval("T LET flag flag") == [true]
    end

    test "LET inside function body" do
      source = """
      DEF add_ten : int -> int
        10 LET n
        n ADD
      END
      5 add_ten
      """
      assert Cairn.eval(source) == [15]
    end

    test "LET preserves stack correctly" do
      # 1 LET x pushes 1 then pops it into x; 2 stays on stack
      assert Cairn.eval("2 1 LET x x ADD") == [3]
    end

    test "LET used with computation" do
      # LET to name intermediate results in a multi-step computation
      source = """
      10 LET base
      base base MUL LET squared
      squared base ADD
      """
      assert Cairn.eval(source) == [110]
    end

    test "LET on empty stack raises static error" do
      assert_raise Cairn.StaticError, ~r/LET.*underflow/, fn ->
        Cairn.eval("LET x")
      end
    end

    test "type checker accepts LET programs" do
      source = "42 LET x x"
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert :ok = Cairn.Checker.check(items)
    end

    test "type checker rejects LET on empty stack" do
      source = "LET x"
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert {:error, errors} = Cairn.Checker.check(items)
      assert Enum.any?(errors, fn e -> e.message =~ "LET" and e.message =~ "underflow" end)
    end

    test "type checker tracks LET binding types" do
      source = """
      DEF use_let : int -> int
        LET x
        x x ADD
      END
      """
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert :ok = Cairn.Checker.check(items)
    end
  end

  # ── SAID ──

  describe "SAID" do
    test "prints and drops string" do
      output = ExUnit.CaptureIO.capture_io(fn ->
        result = Cairn.eval(~s|"hello" SAID|)
        send(self(), {:result, result})
      end)
      assert output =~ "hello"
      assert_received {:result, []}
    end

    test "prints and drops integer" do
      output = ExUnit.CaptureIO.capture_io(fn ->
        result = Cairn.eval("42 SAID")
        send(self(), {:result, result})
      end)
      assert output =~ "42"
      assert_received {:result, []}
    end

    test "replaces SAY DROP pattern" do
      output = ExUnit.CaptureIO.capture_io(fn ->
        result = Cairn.eval(~s|"hi" SAID 99|)
        send(self(), {:result, result})
      end)
      assert output =~ "hi"
      assert_received {:result, [99]}
    end

    test "type checker accepts SAID" do
      source = ~s|"hello" SAID|
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert :ok = Cairn.Checker.check(items)
    end
  end

  # ── FMT ──

  describe "FMT" do
    test "single int placeholder" do
      assert Cairn.eval(~s|42 "Score: {}!" FMT|) == ["Score: 42!"]
    end

    test "multiple placeholders" do
      assert Cairn.eval(~s|42 "Alice" "Name: {}, Age: {}" FMT|) == ["Name: Alice, Age: 42"]
    end

    test "no placeholders" do
      assert Cairn.eval(~s|"hello" FMT|) == ["hello"]
    end

    test "auto-converts bool" do
      assert Cairn.eval(~s|T "flag: {}" FMT|) == ["flag: T"]
    end

    test "auto-converts float" do
      result = Cairn.eval(~s|3.14 "pi: {}" FMT|)
      [s] = result
      assert String.starts_with?(s, "pi: 3.14")
    end

    test "literal braces with {{ and }}" do
      assert Cairn.eval(~s|"use {{}} for placeholders" FMT|) == ["use {} for placeholders"]
    end

    test "inside function body" do
      source = """
      DEF greet : str -> str
        "Hello, {}!" FMT
      END
      "world" greet
      """
      assert Cairn.eval(source) == ["Hello, world!"]
    end

    test "type checker accepts FMT with literal format string" do
      source = ~s|42 "val: {}" FMT|
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert :ok = Cairn.Checker.check(items)
    end

    test "type checker rejects FMT on empty stack" do
      source = "FMT"
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert {:error, errors} = Cairn.Checker.check(items)
      assert Enum.any?(errors, fn e -> e.message =~ "FMT" and e.message =~ "underflow" end)
    end
  end

  # ── ASK ──

  describe "ASK" do
    test "reads input with prompt" do
      output = ExUnit.CaptureIO.capture_io([input: "Alice\n"], fn ->
        result = Cairn.eval(~s|"Name? " ASK!|)
        # Send result to test process
        send(self(), {:result, result})
      end)
      assert output =~ "Name? "
      assert_received {:result, ["Alice"]}
    end

    test "ASK returns Ok on success" do
      output = ExUnit.CaptureIO.capture_io([input: "Bob\n"], fn ->
        result = Cairn.eval(~s|"Name? " ASK|)
        send(self(), {:result, result})
      end)

      assert output =~ "Name? "
      assert_received {:result, [{:variant, "result", "Ok", ["Bob"]}]}
    end

    test "type checker accepts ASK and ASK!" do
      source = ~s|"prompt" ASK DROP "prompt" ASK!|
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert :ok = Cairn.Checker.check(items)
    end
  end

  # ── RANDOM ──

  describe "RANDOM" do
    test "produces integer in range" do
      results = for _ <- 1..100, do: hd(Cairn.eval("10 RANDOM"))
      assert Enum.all?(results, fn r -> is_integer(r) and r >= 1 and r <= 10 end)
      # Should have some variety (not all the same)
      assert length(Enum.uniq(results)) > 1
    end

    test "type checker accepts RANDOM" do
      source = "100 RANDOM"
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert :ok = Cairn.Checker.check(items)
    end
  end
end
