defmodule Axiom.CheckerTest do
  use ExUnit.Case

  alias Axiom.Checker
  alias Axiom.Checker.{Stack, Unify, Effects}

  # Helper: check source and return :ok or {:error, errors}
  defp check(source, env \\ %{}) do
    {:ok, tokens} = Axiom.Lexer.tokenize(source)
    {:ok, items} = Axiom.Parser.parse(tokens)
    Checker.check(items, env)
  end

  defp check_ok(source), do: assert(:ok == check(source))

  defp check_errors(source) do
    assert {:error, errors} = check(source)
    errors
  end

  # ── Stack module ──

  describe "Stack" do
    test "new stack is empty" do
      s = Stack.new()
      assert Stack.depth(s) == 0
      assert Stack.peek(s) == :underflow
    end

    test "push and pop" do
      s = Stack.new() |> Stack.push(:int)
      assert Stack.depth(s) == 1
      assert {:ok, :int, rest} = Stack.pop(s)
      assert Stack.depth(rest) == 0
    end

    test "pop from empty returns :underflow" do
      assert :underflow = Stack.pop(Stack.new())
    end

    test "pop_n pops multiple types" do
      s = Stack.new() |> Stack.push(:int) |> Stack.push(:str) |> Stack.push(:bool)
      assert {[:bool, :str, :int], rest} = Stack.pop_n(s, 3)
      assert Stack.depth(rest) == 0
    end

    test "pop_n underflow" do
      s = Stack.new() |> Stack.push(:int)
      assert :underflow = Stack.pop_n(s, 2)
    end

    test "peek returns top without removing" do
      s = Stack.new() |> Stack.push(:int) |> Stack.push(:str)
      assert {:ok, :str} = Stack.peek(s)
      assert Stack.depth(s) == 2
    end
  end

  # ── Unify module ──

  describe "Unify" do
    test "same types unify" do
      assert {:ok, :int} = Unify.unify(:int, :int)
      assert {:ok, :str} = Unify.unify(:str, :str)
    end

    test ":any unifies with anything" do
      assert {:ok, :int} = Unify.unify(:any, :int)
      assert {:ok, :str} = Unify.unify(:str, :any)
    end

    test ":num unifies with numeric types" do
      assert {:ok, :int} = Unify.unify(:num, :int)
      assert {:ok, :float} = Unify.unify(:num, :float)
      assert {:ok, :int} = Unify.unify(:int, :num)
      assert {:ok, :float} = Unify.unify(:float, :num)
    end

    test ":num does not unify with non-numeric" do
      assert :error = Unify.unify(:num, :str)
      assert :error = Unify.unify(:num, :bool)
    end

    test "incompatible types fail" do
      assert :error = Unify.unify(:int, :str)
      assert :error = Unify.unify(:bool, :float)
    end

    test "list unification" do
      assert {:ok, {:list, :int}} = Unify.unify({:list, :int}, {:list, :int})
      assert {:ok, {:list, :int}} = Unify.unify({:list, :int}, {:list, :any})
      assert :error = Unify.unify({:list, :int}, {:list, :str})
    end

    test "type variable unification" do
      assert {:ok, :int} = Unify.unify({:tvar, 0}, :int)
      assert {:ok, :str} = Unify.unify(:str, {:tvar, 1})
    end
  end

  # ── Effects module ──

  describe "Effects" do
    test "arithmetic operators have effects" do
      assert {:ok, %{pops: [:num, :num], pushes: [:num_result]}} = Effects.lookup(:add)
      assert {:ok, %{pops: [:num, :num], pushes: [:num_result]}} = Effects.lookup(:sub)
      assert {:ok, %{pops: [:float, :float], pushes: [:float]}} = Effects.lookup(:pow)
    end

    test "comparison operators push bool" do
      assert {:ok, %{pushes: [:bool]}} = Effects.lookup(:gt)
      assert {:ok, %{pushes: [:bool]}} = Effects.lookup(:eq)
    end

    test "unknown operator" do
      assert :unknown = Effects.lookup(:nonexistent)
    end

    test "I/O operators have effects" do
      assert {:ok, %{pops: [], pushes: [{:list, :str}]}} = Effects.lookup(:argv)
      assert {:ok, %{pops: [:any], pushes: [:any]}} = Effects.lookup(:say)
    end

    test "string primitive operators have effects" do
      assert {:ok, %{pops: [:str],             pushes: [{:list, :str}]}} = Effects.lookup(:chars)
      assert {:ok, %{pops: [:str, :str],       pushes: [{:list, :str}]}} = Effects.lookup(:split)
      assert {:ok, %{pops: [:str],             pushes: [:str]}}           = Effects.lookup(:trim)
      assert {:ok, %{pops: [:str, :str],       pushes: [:bool]}}          = Effects.lookup(:starts_with)
      assert {:ok, %{pops: [:int, :int, :str], pushes: [:str]}}           = Effects.lookup(:slice)
      assert {:ok, %{pops: [:str], pushes: [{:user_type, "result"}]}} = Effects.lookup(:to_int)
      assert {:ok, %{pops: [:str], pushes: [{:user_type, "result"}]}} = Effects.lookup(:to_float)
      assert {:ok, %{pops: [:str], pushes: [:int]}} = Effects.lookup(:to_int!)
      assert {:ok, %{pops: [:str], pushes: [:float]}} = Effects.lookup(:to_float!)
    end

    test "explicit float math operators have effects" do
      assert {:ok, %{pops: [:float], pushes: [:float]}} = Effects.lookup(:sin)
      assert {:ok, %{pops: [:float], pushes: [:float]}} = Effects.lookup(:cos)
      assert {:ok, %{pops: [:float], pushes: [:float]}} = Effects.lookup(:exp)
      assert {:ok, %{pops: [:float], pushes: [:float]}} = Effects.lookup(:log)
      assert {:ok, %{pops: [:float], pushes: [:float]}} = Effects.lookup(:sqrt)
      assert {:ok, %{pops: [:float], pushes: [:float]}} = Effects.lookup(:floor)
      assert {:ok, %{pops: [:float], pushes: [:float]}} = Effects.lookup(:ceil)
      assert {:ok, %{pops: [:float], pushes: [:float]}} = Effects.lookup(:round)
      assert {:ok, %{pops: [], pushes: [:float]}} = Effects.lookup(:pi)
      assert {:ok, %{pops: [], pushes: [:float]}} = Effects.lookup(:e)
    end

    test "HOST_CALL stays special-cased outside the generic effects table" do
      assert :unknown = Effects.lookup(:host_call)
    end

    test "collection helper operators have effects" do
      assert {:ok, %{pops: [{:list, :any}, {:list, :any}], pushes: [{:list, {:list, :any}}]}} =
               Effects.lookup(:zip)

      assert {:ok, %{pops: [{:list, :any}], pushes: [{:list, {:list, :any}}]}} =
               Effects.lookup(:enumerate)

      assert {:ok, %{pops: [:int, {:list, :any}], pushes: [{:list, :any}]}} =
               Effects.lookup(:take)
    end
  end

  # ── Literal type tracking ──

  describe "literals" do
    test "integer literal" do
      check_ok("42")
    end

    test "float literal" do
      check_ok("3.14")
    end

    test "boolean literal" do
      check_ok("T")
      check_ok("F")
    end

    test "string literal" do
      check_ok("\"hello\"")
    end

    test "empty list literal" do
      check_ok("[]")
    end

    test "multiple literals" do
      check_ok("1 2 3")
    end
  end

  # ── Arithmetic and type errors ──

  describe "arithmetic operators" do
    test "int + int is valid" do
      check_ok("3 4 ADD")
    end

    test "float + float is valid" do
      check_ok("1.0 2.0 ADD")
    end

    test "int + float is valid (num unification)" do
      check_ok("3 2.0 ADD")
    end

    test "string + int is type error" do
      errors = check_errors("\"hello\" 3 ADD")
      assert length(errors) >= 1
      assert Enum.any?(errors, fn e -> e.message =~ "ADD" end)
    end

    test "bool + bool is type error" do
      errors = check_errors("T F ADD")
      assert length(errors) >= 1
    end

    test "MOD requires ints" do
      check_ok("10 3 MOD")
    end

    test "unary ops" do
      check_ok("5 SQ")
      check_ok("-3 ABS")
      check_ok("5 NEG")
      check_ok("1.0 SIN")
      check_ok("1.0 COS")
      check_ok("1.0 EXP")
      check_ok("1.0 LOG")
      check_ok("1.0 SQRT")
      check_ok("1.0 FLOOR")
      check_ok("1.0 CEIL")
      check_ok("1.0 ROUND")
      check_ok("PI")
      check_ok("E")
      check_ok("8.0 2.0 POW")
    end

    test "explicit float math requires floats" do
      errors = check_errors("1 SIN")
      assert Enum.any?(errors, fn e -> e.message =~ "SIN" and e.message =~ "expected float" and e.message =~ "got int" end)

      errors = check_errors("2 8.0 POW")
      assert Enum.any?(errors, fn e -> e.message =~ "POW" and e.message =~ "expected float" and e.message =~ "got int" end)
    end

    test "HOST_CALL accepts typed whitelisted helpers with literal arg lists" do
      check_ok("[ \"hello\" ] HOST_CALL str_upcase")
      check_ok("[ \"ha ha\" \"ha\" \"xo\" ] HOST_CALL str_replace")
      check_ok("[ 42 ] HOST_CALL int_to_string")
      check_ok("[ 3.14 ] HOST_CALL float_to_string")
    end

    test "HOST_CALL rejects unknown helper names" do
      errors = check_errors("[ \"hello\" ] HOST_CALL nope")
      assert Enum.any?(errors, fn e -> e.message =~ "HOST_CALL 'nope' is not in the v1 whitelist" end)
    end

    test "HOST_CALL enforces literal arg arity and types" do
      errors = check_errors("[ ] HOST_CALL str_upcase")
      assert Enum.any?(errors, fn e -> e.message =~ "HOST_CALL 'str_upcase' expected 1 arg(s), got 0" end)

      errors = check_errors("[ 42 ] HOST_CALL str_upcase")
      assert Enum.any?(errors, fn e -> e.message =~ "HOST_CALL 'str_upcase' arg type mismatch" end)
    end

    test "HOST_CALL rejects non-literal argument lists in v1" do
      errors = check_errors("[] LET args args HOST_CALL str_upcase")
      assert Enum.any?(errors, fn e -> e.message =~ "HOST_CALL 'str_upcase' in v1 requires a literal argument list immediately before it" end)
    end
  end

  # ── Stack underflow ──

  describe "stack underflow" do
    test "ADD on empty stack" do
      errors = check_errors("ADD")
      assert Enum.any?(errors, fn e -> e.message =~ "underflow" end)
    end

    test "ADD with one value" do
      errors = check_errors("5 ADD")
      assert Enum.any?(errors, fn e -> e.message =~ "underflow" end)
    end

    test "DUP on empty stack" do
      errors = check_errors("DUP")
      assert Enum.any?(errors, fn e -> e.message =~ "underflow" end)
    end

    test "DROP on empty stack" do
      errors = check_errors("DROP")
      assert Enum.any?(errors, fn e -> e.message =~ "underflow" end)
    end

    test "SWAP on one element" do
      errors = check_errors("5 SWAP")
      assert Enum.any?(errors, fn e -> e.message =~ "underflow" end)
    end

    test "ROT with two elements" do
      errors = check_errors("1 2 ROT")
      assert Enum.any?(errors, fn e -> e.message =~ "underflow" end)
    end
  end

  # ── Comparison and logic ──

  describe "comparison and logic" do
    test "numeric comparison" do
      check_ok("3 4 GT")
      check_ok("3 4 LT")
      check_ok("3 4 EQ")
    end

    test "EQ accepts any types" do
      check_ok("\"a\" \"b\" EQ")
    end

    test "boolean logic" do
      check_ok("T F AND")
      check_ok("T F OR")
      check_ok("T NOT")
    end

    test "AND with non-booleans is error" do
      errors = check_errors("3 4 AND")
      assert Enum.any?(errors, fn e -> e.message =~ "AND" end)
    end

    test "NOT with non-boolean is error" do
      errors = check_errors("3 NOT")
      assert Enum.any?(errors, fn e -> e.message =~ "NOT" end)
    end
  end

  # ── Stack manipulation ──

  describe "stack manipulation" do
    test "DUP preserves type" do
      check_ok("5 DUP ADD")
    end

    test "SWAP rearranges types" do
      check_ok("\"hello\" 42 SWAP")
    end

    test "OVER copies second element" do
      check_ok("3 5 OVER")
    end

    test "ROT rotates three" do
      check_ok("1 2 3 ROT")
    end

    test "DROP removes top" do
      check_ok("1 2 DROP")
    end

    test "complex stack manipulation" do
      check_ok("5 DUP DUP ADD SWAP DROP")
    end
  end

  # ── IF/ELSE branches ──

  describe "IF/ELSE branches" do
    test "simple IF with bool condition" do
      check_ok("T IF 42 END")
    end

    test "IF/ELSE with matching branches" do
      check_ok("T IF 1 ELSE 2 END")
    end

    test "non-bool IF condition is error" do
      errors = check_errors("42 IF 1 END")
      assert Enum.any?(errors, fn e -> e.message =~ "bool" end)
    end

    test "IF without condition is error" do
      errors = check_errors("IF 1 END")
      assert Enum.any?(errors, fn e -> e.message =~ "underflow" end)
    end

    test "nested IF" do
      check_ok("T IF T IF 1 ELSE 2 END ELSE 3 END")
    end

    test "IF inside function body" do
      check_ok("DEF absv : int -> int DUP 0 LT IF NEG END END")
    end

    test "IF/ELSE inside function body" do
      check_ok("DEF sign : int -> int DUP 0 GT IF DROP 1 ELSE DUP 0 LT IF DROP -1 ELSE DROP 0 END END END")
    end
  end

  # ── Functions ──

  describe "functions" do
    test "simple function definition and call" do
      check_ok("DEF double : int -> int DUP ADD END 5 double")
    end

    test "function with POST" do
      check_ok("DEF dbl : int -> int DUP ADD POST 0 GTE END 5 dbl")
    end

    test "function with PRE" do
      check_ok("DEF pos_double : int -> int PRE { DUP 0 GT } DUP ADD END 5 pos_double")
    end

    test "function with PRE and POST" do
      check_ok("""
      DEF safe_double : int -> int
        PRE { DUP 0 GTE }
        DUP ADD
        POST DUP 0 GTE
      END
      5 safe_double
      """)
    end

    test "void function" do
      check_ok("DEF said : any -> void SAY DROP END 42 said")
    end

    test "any param accepts all types" do
      check_ok("DEF id : any -> any END 42 id")
      check_ok("DEF id : any -> any END \"hello\" id")
    end

    test "wrong arg type is error" do
      errors = check_errors("DEF double : int -> int DUP ADD END \"hello\" double")
      assert Enum.any?(errors, fn e -> e.message =~ "expected int" and e.message =~ "got str" end)
    end

    test "return arity mismatch — too few" do
      errors = check_errors("DEF bad : int -> int DROP END")
      assert Enum.any?(errors, fn e -> e.message =~ "1 return value" and e.message =~ "produces 0" end)
    end

    test "return arity mismatch — too many" do
      errors = check_errors("DEF bad : int -> int DUP END")
      assert Enum.any?(errors, fn e -> e.message =~ "1 return value" and e.message =~ "produces 2" end)
    end

    test "return type mismatch" do
      errors = check_errors("DEF bad : int -> int \"oops\" SWAP DROP END")
      assert Enum.any?(errors, fn e -> e.message =~ "return type mismatch" end)
    end

    test "multi-return function" do
      check_ok("DEF dup2 : int -> int int DUP END 5 dup2")
    end

    test "multi-return wrong count" do
      errors = check_errors("DEF bad : int int -> int int DROP END")
      assert Enum.any?(errors, fn e -> e.message =~ "2 return value" and e.message =~ "produces 1" end)
    end

    test "multiple function definitions" do
      check_ok("""
      DEF sq : int -> int DUP MUL END
      DEF double : int -> int DUP ADD END
      5 sq double
      """)
    end

    test "function calling another function" do
      check_ok("""
      DEF sq : int -> int DUP MUL END
      DEF sum_sq : [int] -> int { sq } MAP SUM END
      [ 1 2 3 ] sum_sq
      """)
    end

    test "undefined function call is error" do
      errors = check_errors("5 nope")
      assert Enum.any?(errors, fn e -> e.message =~ "undefined function" end)
    end

    test "void function that leaves values is error" do
      errors = check_errors("DEF bad : int -> void END")
      assert Enum.any?(errors, fn e -> e.message =~ "void" end)
    end

    test "multi-return type order matters" do
      errors = check_errors("DEF bad : int str -> str int END")
      assert Enum.any?(errors, fn e -> e.message =~ "return type mismatch" end)
    end
  end

  # ── Blocks and higher-order ops ──

  describe "blocks and higher-order" do
    test "block pushes block type" do
      check_ok("{ DUP ADD }")
    end

    test "APPLY executes block" do
      check_ok("5 { DUP ADD } APPLY")
    end

    test "WITH_STATE threads explicit local state" do
      check_ok("1 { STATE 1 ADD SET_STATE } WITH_STATE")
    end

    test "STEP applies a state helper inside WITH_STATE" do
      check_ok("""
      DEF bump : int -> int
        1 ADD
      END
      1 { STEP bump } WITH_STATE
      """)
    end

    test "WITH_STATE accepts ADT-wrapped composite state" do
      check_ok("""
      TYPE pair = Pair int int
      1 2 Pair
      {
        STATE
        MATCH
          Pair { 1 ADD SWAP 10 ADD SWAP Pair SET_STATE }
        END
      } WITH_STATE
      """)
    end

    test "constructors accept mixed fields in declaration order" do
      check_ok("""
      TYPE mixed = Mixed str int bool
      "peer" 1 T Mixed
      MATCH
        Mixed { DROP DROP DROP }
      END
      """)
    end

    test "WITH_STATE accepts variant state-machine updates" do
      check_ok("""
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
      """)
    end

    test "FILTER with block" do
      check_ok("[ 1 2 3 4 5 ] { 2 MOD 1 EQ } FILTER")
    end

    test "MAP with block" do
      check_ok("[ 1 2 3 ] { SQ } MAP")
    end

    test "FLAT_MAP with block" do
      check_ok("[ 1 2 3 ] { DUP 10 MUL [ ] CONS CONS } FLAT_MAP")
    end

    test "FIND with block" do
      check_ok("[ 1 2 3 4 ] { 2 MOD 0 EQ } FIND")
    end

    test "GROUP_BY with block" do
      check_ok("[ 1 2 3 4 ] { 2 MOD } GROUP_BY")
    end

    test "REDUCE with block" do
      check_ok("[ 1 2 3 4 5 ] 0 { ADD } REDUCE")
    end

    test "TIMES with block" do
      check_ok("1 4 { DUP ADD } TIMES")
    end

    test "REPEAT with block" do
      check_ok("1 4 { DUP ADD } REPEAT")
    end

    test "WHILE with two blocks" do
      check_ok("1 { DUP 100 LT } { DUP ADD } WHILE")
    end

    test "FILTER then MAP then SUM" do
      check_ok("[ 1 2 3 4 5 ] { 2 MOD 1 EQ } FILTER { SQ } MAP SUM")
    end

    test "APPLY with non-block is error" do
      errors = check_errors("5 42 APPLY")
      assert Enum.any?(errors, fn e -> e.message =~ "APPLY" end)
    end

    test "STATE outside WITH_STATE is an error" do
      errors = check_errors("STATE")
      assert Enum.any?(errors, fn e -> e.message =~ "STATE is only available inside WITH_STATE" end)
    end

    test "SET_STATE outside WITH_STATE is an error" do
      errors = check_errors("1 SET_STATE")
      assert Enum.any?(errors, fn e -> e.message =~ "SET_STATE is only available inside WITH_STATE" end)
    end

    test "STEP outside WITH_STATE is an error" do
      errors = check_errors("STEP bump")
      assert Enum.any?(errors, fn e -> e.message =~ "STEP is only available inside WITH_STATE" end)
    end

    test "SET_STATE must preserve the state type" do
      errors = check_errors("1 { \"oops\" SET_STATE } WITH_STATE")
      assert Enum.any?(errors, fn e -> e.message =~ "SET_STATE expected int, got str" end)
    end

    test "WITH_STATE block must leave no visible values" do
      errors = check_errors("1 { STATE } WITH_STATE")
      assert Enum.any?(errors, fn e -> e.message =~ "WITH_STATE block must leave no visible values" end)
    end
  end

  # ── Lists ──

  describe "lists" do
    test "list construction" do
      check_ok("[ 1 2 3 ]")
    end

    test "empty list" do
      check_ok("[ ]")
    end

    test "list operations" do
      check_ok("[ 1 2 3 ] SUM")
      check_ok("[ 1 2 3 ] LEN")
      check_ok("[ 1 2 3 ] HEAD")
      check_ok("[ 1 2 3 ] TAIL")
      check_ok("[ 1 2 3 ] [ 4 5 6 ] ZIP")
      check_ok("[ 1 2 3 ] ENUMERATE")
      check_ok("[ 1 2 3 ] 2 TAKE")
    end

    test "SORT and REVERSE" do
      check_ok("[ 3 1 2 ] SORT")
      check_ok("[ 1 2 3 ] REVERSE")
    end

    test "RANGE" do
      check_ok("5 RANGE")
    end

    test "CONS" do
      check_ok("1 [ 2 3 ] CONS")
    end

    test "CONCAT with lists" do
      check_ok("[ 1 2 ] [ 3 4 ] CONCAT")
    end

    test "CONCAT with strings" do
      check_ok("\"hello \" \"world\" CONCAT")
    end

    test "FLAT_MAP block must return a list" do
      errors = check_errors("[ 1 2 3 ] { SQ } FLAT_MAP")
      assert Enum.any?(errors, fn e -> e.message =~ "FLAT_MAP block must return a list" end)
    end

    test "FIND block must return bool" do
      errors = check_errors("[ 1 2 3 ] { SQ } FIND")
      assert Enum.any?(errors, fn e -> e.message =~ "FIND block must return bool" end)
    end
  end

  # ── I/O operations ──

  describe "I/O operations" do
    test "SAY is non-destructive" do
      check_ok("42 SAY")
    end

    test "PRINT is non-destructive" do
      check_ok("42 PRINT")
    end

    test "ARGV pushes list of strings" do
      check_ok("ARGV")
    end

    test "READ_FILE expects string" do
      check_ok("\"path\" READ_FILE")
    end

    test "WRITE_FILE expects two strings" do
      check_ok("\"content\" \"path\" WRITE_FILE")
    end

    test "WORDS on string" do
      check_ok("\"hello world\" WORDS")
    end

    test "LINES on string" do
      check_ok("\"a\nb\" LINES")
    end

    test "CONTAINS on strings" do
      check_ok("\"hello\" \"ell\" CONTAINS")
    end

    test "LEN on strings" do
      check_ok("\"hello\" LEN")
    end
  end

  # ── String primitives ──

  describe "string primitives" do
    test "CHARS on string" do
      check_ok("\"hello\" CHARS")
    end

    test "CHARS result is [str] — LEN works" do
      check_ok("\"hello\" CHARS LEN")
    end

    test "CHARS then HEAD gives str" do
      check_ok("\"hello\" CHARS HEAD")
    end

    test "CHARS on non-string is error" do
      errors = check_errors("42 CHARS")
      assert Enum.any?(errors, fn e -> e.message =~ "CHARS" end)
    end

    test "SPLIT on two strings" do
      check_ok("\"hello,world\" \",\" SPLIT")
    end

    test "SPLIT result is [str] — LEN works" do
      check_ok("\"a,b,c\" \",\" SPLIT LEN")
    end

    test "SPLIT with wrong input type is error" do
      errors = check_errors("42 \",\" SPLIT")
      assert Enum.any?(errors, fn e -> e.message =~ "SPLIT" end)
    end

    test "TRIM on string" do
      check_ok("\"  hi  \" TRIM")
    end

    test "TRIM result is str — CONCAT works" do
      check_ok("\"  hi  \" TRIM \"!\" CONCAT")
    end

    test "TRIM on non-string is error" do
      errors = check_errors("42 TRIM")
      assert Enum.any?(errors, fn e -> e.message =~ "TRIM" end)
    end

    test "STARTS_WITH on two strings" do
      check_ok("\"hello\" \"he\" STARTS_WITH")
    end

    test "STARTS_WITH result is bool — NOT works" do
      check_ok("\"hello\" \"he\" STARTS_WITH NOT")
    end

    test "STARTS_WITH with wrong input type is error" do
      errors = check_errors("42 \"he\" STARTS_WITH")
      assert Enum.any?(errors, fn e -> e.message =~ "STARTS_WITH" end)
    end

    test "SLICE on string with int start and len" do
      check_ok("\"hello\" 1 3 SLICE")
    end

    test "SLICE result is str — CONCAT works" do
      check_ok("\"hello\" 0 3 SLICE \"!\" CONCAT")
    end

    test "SLICE with wrong type is error" do
      errors = check_errors("42 1 3 SLICE")
      assert Enum.any?(errors, fn e -> e.message =~ "SLICE" end)
    end

    test "TO_INT on string" do
      check_ok("\"42\" TO_INT")
    end

    test "TO_INT result is result — MATCH works" do
      check_ok("\"42\" TO_INT MATCH Ok { } Err { DROP 0 } END")
    end

    test "TO_INT! result is int — arithmetic works" do
      check_ok("\"42\" TO_INT! 10 ADD")
    end

    test "TO_INT! result is int — used in function expecting int" do
      check_ok("DEF double : int -> int DUP ADD END \"5\" TO_INT! double")
    end

    test "TO_INT on non-string is error" do
      errors = check_errors("42 TO_INT")
      assert Enum.any?(errors, fn e -> e.message =~ "TO_INT" end)
    end

    test "TO_FLOAT on string" do
      check_ok("\"3.14\" TO_FLOAT")
    end

    test "TO_FLOAT! result is float — arithmetic works" do
      check_ok("\"3.14\" TO_FLOAT! 1.0 ADD")
    end

    test "TO_FLOAT on non-string is error" do
      errors = check_errors("3.14 TO_FLOAT")
      assert Enum.any?(errors, fn e -> e.message =~ "TO_FLOAT" end)
    end

    test "pipeline: SPLIT then MAP TO_INT! then SUM" do
      check_ok("\"1,2,3\" \",\" SPLIT { TO_INT! } MAP SUM")
    end

    test "JOIN on list of strings" do
      check_ok("[ \"a\" \"b\" \"c\" ] \",\" JOIN")
    end

    test "JOIN result is str" do
      check_ok("[ \"a\" \"b\" ] \",\" JOIN LEN")
    end

    test "CHARS then JOIN round-trips" do
      check_ok("\"hello\" CHARS \"\" JOIN")
    end

    test "JOIN with wrong sep type is error" do
      errors = check_errors("[ \"a\" \"b\" ] 42 JOIN")
      assert Enum.any?(errors, fn e -> e.message =~ "JOIN" end)
    end
  end

  # ── Multiple errors in one pass ──

  describe "error recovery" do
    test "reports multiple errors" do
      # ADD underflows, then the best-effort :num result lets DROP succeed,
      # but 5 ADD also has a type error since string can't be added to num
      errors = check_errors("\"hello\" 5 ADD \"world\" 5 ADD")
      assert length(errors) >= 2
    end

    test "continues after type error" do
      errors = check_errors("\"hello\" 3 ADD DROP")
      assert length(errors) >= 1
    end

    test "reports function body and call-site errors" do
      errors = check_errors("DEF bad : int -> int DROP END \"hello\" bad")
      assert length(errors) >= 2
    end
  end

  # ── User types in compound positions (recursive sum types) ──

  @json_type """
  TYPE json = JNull
            | JBool bool
            | JNum  float
            | JStr  str
            | JArr  [json]
            | JObj  map[str json]
  """

  describe "user types in compound positions" do
    test "[user_type] is a valid list type in the lexer" do
      assert {:ok, [{:type, {:list, {:user_type, "json"}}, 0}]} =
               Axiom.Lexer.tokenize("[json]")
    end

    test "map[str user_type] is a valid map type in the lexer" do
      assert {:ok, [{:type, {:map, :str, {:user_type, "json"}}, 0}]} =
               Axiom.Lexer.tokenize("map[str json]")
    end

    test "recursive TYPE json definition type-checks" do
      check_ok(@json_type)
    end

    test "constructing JNull, JBool, JNum, JStr type-checks" do
      # 0 DROP terminates the TYPE declaration so bare JNull is an expression
      check_ok(@json_type <> "0 DROP JNull  T JBool  3.14 JNum  \"hi\" JStr")
    end

    test "JArr constructor accepts [json]" do
      check_ok(@json_type <> "[ JNull ] JArr")
    end

    test "JObj constructor accepts map[str json]" do
      check_ok(@json_type <> ~s(M[ "k" JNull ] JObj))
    end

    test "[json] works as a function parameter type" do
      check_ok(@json_type <> """
      DEF wrap_array : [json] -> json
        JArr
      END
      """)
    end

    test "map[str json] works as a function parameter type" do
      check_ok(@json_type <> """
      DEF wrap_object : map[str json] -> json
        JObj
      END
      """)
    end

    test "MATCH on json type-checks with exhaustive arms" do
      check_ok(@json_type <> """
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
      """)
    end

    test "non-exhaustive MATCH on json is an error" do
      errors = check_errors(@json_type <> """
      DEF bad : json -> bool
        MATCH
          JNull { T }
          JBool { DROP F }
        END
      END
      """)
      assert Enum.any?(errors, fn e -> e.message =~ "exhaustive" end)
    end

    test "user type as bare variant field type-checks (tree)" do
      check_ok("""
      TYPE tree = Leaf int | Node tree tree
      DEF depth : tree -> int
        MATCH
          Leaf { DROP 1 }
          Node { depth SWAP depth SWAP MAX 1 ADD }
        END
      END
      """)
    end
  end

  # ── Example programs (no false positives) ──

  describe "example programs" do
    test "collatz step function" do
      check_ok("""
      DEF step : int -> int
        DUP 2 MOD 0 EQ
        IF 2 DIV
        ELSE 3 MUL 1 ADD
        END
        POST DUP 0 GT
      END
      27 { DUP 1 GT } { step } WHILE SAY DROP
      """)
    end

    test "factorial" do
      check_ok("""
      DEF factorial : int -> int
        PRE { DUP 0 GTE }
        RANGE 1 { MUL } REDUCE
        POST DUP 0 GT
      END
      10 factorial SAY DROP
      """)
    end

    test "fibonacci" do
      check_ok("0 1 20 { SWAP OVER ADD } TIMES SWAP DROP SAY DROP")
    end

    test "gcd" do
      check_ok("""
      DEF gcd : int int -> int
        { DUP 0 NEQ }
        { SWAP OVER MOD }
        WHILE
        DROP
      END
      48 18 gcd SAY DROP
      """)
    end

    test "sum of squared odds" do
      check_ok("""
      DEF sum_sq_odds : [int] -> int
        { 2 MOD 1 EQ } FILTER
        { SQ } MAP
        SUM
        POST DUP 0 GTE
      END
      [ 1 2 3 4 5 6 7 8 9 10 ] sum_sq_odds SAY DROP
      """)
    end

    test "statistics: mean, sum_of_squares, median" do
      check_ok("""
      DEF mean : [int] -> int
        DUP SUM SWAP LEN DIV
      END

      DEF sum_of_squares : [int] -> int
        0 { SQ ADD } REDUCE
        POST DUP 0 GTE
      END

      DEF median : [int] -> int
        SORT DUP LEN 2 DIV
        { TAIL } TIMES
        HEAD
      END

      [ 10 4 7 2 9 1 8 3 6 5 ]
      DUP mean SAY DROP
      DUP sum_of_squares SAY DROP
      median SAY DROP
      """)
    end

    test "cat utility" do
      check_ok("""
      DEF said : any -> void SAY DROP END
      ARGV HEAD READ_FILE! said
      """)
    end

    test "hello world" do
      check_ok("""
      "Hello, World!" SAY DROP
      "Hello, " "Axiom!" CONCAT SAY DROP
      42 "The answer is:" SAY DROP SAY DROP
      """)
    end

    test "sum of CSV integers" do
      check_ok("""
      DEF parse_csv_sum : str -> int
        "," SPLIT { TO_INT! } MAP SUM
      END
      "1,2,3,4,5" parse_csv_sum SAY DROP
      """)
    end

    test "trim and prefix check pipeline" do
      check_ok("""
      DEF is_keyword : str -> bool
        TRIM "kw:" STARTS_WITH
      END
      "  kw:hello  " is_keyword SAY DROP
      """)
    end
  end
end
