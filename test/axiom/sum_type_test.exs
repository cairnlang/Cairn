defmodule Axiom.SumTypeTest do
  use ExUnit.Case

  # Helpers

  # Two-step eval: first call defines TYPE/DEF, second call evaluates expressions
  # using the constructors and functions registered in the first call's env.
  defp define(source) do
    {_stack, env} = Axiom.eval_with_env(source)
    env
  end

  defp run(source, env) do
    {stack, _env} = Axiom.eval_with_env(source, env)
    stack
  end

  defp check(source, env) do
    {:ok, tokens} = Axiom.Lexer.tokenize(source)
    {:ok, items} = Axiom.Parser.parse(tokens)
    Axiom.Checker.check(items, env)
  end

  defp check_ok(source, env), do: assert(:ok == check(source, env))

  defp check_errors(source, env) do
    assert {:error, errors} = check(source, env)
    errors
  end

  defp lex(source) do
    {:ok, tokens} = Axiom.Lexer.tokenize(source)
    tokens
  end

  defp parse(source) do
    {:ok, tokens} = Axiom.Lexer.tokenize(source)
    {:ok, items} = Axiom.Parser.parse(tokens)
    items
  end

  # ── Lexer ──

  describe "Lexer: TYPE keyword" do
    test "TYPE tokenized as :type_kw" do
      tokens = lex("TYPE")
      assert [{:type_kw, "TYPE", 0}] = tokens
    end

    test "MATCH tokenized as :match_kw" do
      tokens = lex("MATCH")
      assert [{:match_kw, "MATCH", 0}] = tokens
    end

    test "| tokenized as :pipe" do
      tokens = lex("|")
      assert [{:pipe, "|", 0}] = tokens
    end

    test "= tokenized as :equals" do
      tokens = lex("=")
      assert [{:equals, "=", 0}] = tokens
    end

    test "uppercase words are constructors" do
      tokens = lex("Some None Just")

      assert [{:constructor, "Some", _}, {:constructor, "None", _}, {:constructor, "Just", _}] =
               tokens
    end

    test "uppercase keyword operators are not constructors" do
      tokens = lex("ADD SUB MUL")
      types = Enum.map(tokens, fn {type, _, _} -> type end)
      assert Enum.all?(types, &(&1 == :op))
    end

    test "TYPE and DEF and END remain keywords" do
      tokens = lex("TYPE DEF END")
      assert [{:type_kw, _, _}, {:fn_def, _, _}, {:fn_end, _, _}] = tokens
    end

    test "lowercase identifiers still work" do
      tokens = lex("foo bar_baz x")
      types = Enum.map(tokens, fn {type, _, _} -> type end)
      assert Enum.all?(types, &(&1 == :ident))
    end

    test "mixed type expression" do
      tokens = lex("TYPE option = None | Some int")

      assert [
               {:type_kw, _, _},
               {:ident, "option", _},
               {:equals, _, _},
               {:constructor, "None", _},
               {:pipe, _, _},
               {:constructor, "Some", _},
               {:type, :int, _}
             ] = tokens
    end
  end

  # ── Parser ──

  describe "Parser: TYPE declarations" do
    test "nullary constructors only" do
      items = parse("TYPE direction = North | South | East | West")
      assert [%Axiom.Types.TypeDef{name: "direction", variants: variants}] = items
      assert Map.keys(variants) |> Enum.sort() == ["East", "North", "South", "West"]
      assert variants["North"] == []
    end

    test "constructor with fields" do
      items = parse("TYPE option = None | Some int")
      assert [%Axiom.Types.TypeDef{name: "option", variants: variants}] = items
      assert variants["None"] == []
      assert variants["Some"] == [:int]
    end

    test "multiple constructors with fields" do
      items = parse("TYPE result = Ok int | Err str")
      assert [%Axiom.Types.TypeDef{} = td] = items
      assert td.name == "result"
      assert td.variants["Ok"] == [:int]
      assert td.variants["Err"] == [:str]
    end

    test "constructor with multiple fields" do
      items = parse("TYPE pair = Pair int int")
      assert [%Axiom.Types.TypeDef{variants: %{"Pair" => [:int, :int]}}] = items
    end

    test "TYPE followed by DEF stops at DEF" do
      items = parse("TYPE option = None | Some int DEF id : int -> int 42 DROP END")
      assert length(items) == 2
      assert %Axiom.Types.TypeDef{} = hd(items)
    end

    test "TYPE followed by an int literal stops at the literal" do
      items = parse("TYPE option = None | Some int 42")
      # TYPE ends at 42, which becomes a separate expression
      assert length(items) == 2
      assert %Axiom.Types.TypeDef{} = hd(items)
      assert {:expr, [{:int_lit, 42, _}]} = List.last(items)
    end

    test "multiple TYPE declarations" do
      items = parse("TYPE option = None | Some int TYPE result = Ok int | Err str")
      assert length(items) == 2
      assert Enum.all?(items, fn i -> match?(%Axiom.Types.TypeDef{}, i) end)
    end
  end

  # ── Evaluator: constructors ──
  # NOTE: Because TYPE declarations consume constructor tokens greedily,
  # constructor-call expressions must be evaluated in a separate call that
  # already has the type registered in the env.

  describe "Evaluator: variant construction" do
    test "nullary constructor" do
      env = define("TYPE option = None | Some int")
      stack = run("None", env)
      assert [{:variant, "option", "None", []}] = stack
    end

    test "constructor with one field" do
      env = define("TYPE option = None | Some int")
      stack = run("42 Some", env)
      assert [{:variant, "option", "Some", [42]}] = stack
    end

    test "constructor with two fields" do
      env = define("TYPE result = Ok int int | Err str")
      # Push 3 then 7 → stack = [7, 3] (7 on top); Ok pops [7, 3] → fields = [7, 3]
      stack = run("3 7 Ok", env)
      assert [{:variant, "result", "Ok", [7, 3]}] = stack
    end

    test "multiple variants on stack" do
      env = define("TYPE option = None | Some int")
      stack = run("None 99 Some", env)

      assert [
               {:variant, "option", "Some", [99]},
               {:variant, "option", "None", []}
             ] = stack
    end

    test "unknown constructor raises StaticError (caught by checker)" do
      env = define("TYPE option = None | Some int")

      assert_raise Axiom.StaticError, fn ->
        run("Blah", env)
      end
    end
  end

  # ── Evaluator: MATCH ──

  describe "Evaluator: MATCH dispatch" do
    test "match None arm" do
      env = define("TYPE option = None | Some int")

      stack =
        run("""
        None
        MATCH
          None { 0 }
          Some { 1 ADD }
        END
        """, env)

      assert [0] = stack
    end

    test "match Some arm pushes field" do
      env = define("TYPE option = None | Some int")

      stack =
        run("""
        42 Some
        MATCH
          None { 0 }
          Some { 1 ADD }
        END
        """, env)

      assert [43] = stack
    end

    test "match with nullary constructors only" do
      env = define("TYPE dir = North | South | East | West")

      stack =
        run("""
        South
        MATCH
          North { 0 }
          South { 1 }
          East  { 2 }
          West  { 3 }
        END
        """, env)

      assert [1] = stack
    end

    test "match Ok arm in result type" do
      env = define("TYPE result = Ok int | Err str")

      stack =
        run("""
        42 Ok
        MATCH
          Ok { 1 ADD }
          Err { DROP 0 }
        END
        """, env)

      assert [43] = stack
    end

    test "match Err arm pops str, returns default" do
      env = define("TYPE result = Ok int | Err str")

      stack =
        run("""
        "failure" Err
        MATCH
          Ok { 1 ADD }
          Err { DROP 0 }
        END
        """, env)

      assert [0] = stack
    end

    test "match in function body with user type signature" do
      {_, env} =
        Axiom.eval_with_env("""
        TYPE option = None | Some int
        DEF unwrap : option -> int
          MATCH
            None { 0 }
            Some { }
          END
        END
        """)

      # Call: 42 Some unwrap → stack before call = [Some(42)], option on top
      stack = run("42 Some unwrap", env)
      assert [42] = stack
    end

    test "non-exhaustive MATCH raises StaticError (caught by checker)" do
      env = define("TYPE option = None | Some int")

      assert_raise Axiom.StaticError, fn ->
        run("""
        42 Some
        MATCH
          None { 0 }
        END
        """, env)
      end
    end

    test "MATCH on non-variant raises StaticError (caught by checker)" do
      env = define("TYPE option = None | Some int")

      assert_raise Axiom.StaticError, fn ->
        run("""
        42
        MATCH
          None { 0 }
          Some { }
        END
        """, env)
      end
    end

    test "MATCH on empty stack raises StaticError (caught by checker)" do
      env = define("TYPE option = None | Some int")

      assert_raise Axiom.StaticError, fn ->
        run("""
        MATCH
          None { 0 }
          Some { }
        END
        """, env)
      end
    end

    test "multiple fields in arm - Pair" do
      env = define("TYPE pair = Pair int int")

      stack =
        run("""
        3 7 Pair
        MATCH
          Pair { ADD }
        END
        """, env)

      assert [10] = stack
    end
  end

  # ── Evaluator: constructor in larger programs ──

  describe "Evaluator: constructors in larger programs" do
    test "constructor result passed to function" do
      {_, env} =
        Axiom.eval_with_env("""
        TYPE option = None | Some int
        DEF from_option : option -> int
          MATCH
            None { -1 }
            Some { }
          END
        END
        """)

      stack = run("42 Some from_option 100 Some from_option None from_option", env)
      assert [-1, 100, 42] = stack
    end

    test "variant value constructed and stored" do
      env = define("TYPE option = None | Some int")
      stack = run("42 Some", env)
      assert [{:variant, "option", "Some", [42]}] = stack
    end
  end

  # ── Static checker ──

  describe "Checker: TYPE registration" do
    test "TYPE registers constructors - nullary ctor is valid" do
      env = define("TYPE option = None | Some int")
      check_ok("None", env)
    end

    test "TYPE registers constructors - unary ctor is valid" do
      env = define("TYPE option = None | Some int")
      check_ok("42 Some", env)
    end

    test "constructor with wrong field type is an error" do
      env = define("TYPE option = None | Some int")
      errors = check_errors(~s("hello" Some), env)
      assert Enum.any?(errors, fn e -> String.contains?(e.message, "Some") end)
    end

    test "unknown constructor in expression is an error" do
      env = define("TYPE option = None | Some int")
      errors = check_errors("Unknown", env)
      assert Enum.any?(errors, fn e -> String.contains?(e.message, "Unknown") end)
    end

    test "nullary constructor pushes user_type" do
      env = define("TYPE option = None | Some int")
      check_ok("None DROP", env)
    end
  end

  describe "Checker: MATCH type checking" do
    test "basic MATCH is ok" do
      {_, env} =
        Axiom.eval_with_env("""
        TYPE option = None | Some int
        """)

      check_ok("""
      42 Some
      MATCH
        None { 0 }
        Some { 1 ADD }
      END
      DROP
      """, env)
    end

    test "non-exhaustive MATCH is a static error" do
      {_, env} =
        Axiom.eval_with_env("""
        TYPE option = None | Some int
        """)

      errors =
        check_errors("""
        42 Some
        MATCH
          Some { 1 ADD }
        END
        """, env)

      assert Enum.any?(errors, fn e ->
               String.contains?(e.message, "exhaustive") and
                 String.contains?(e.message, "None")
             end)
    end

    test "MATCH on non-variant is a static error" do
      env = define("TYPE option = None | Some int")

      errors =
        check_errors("""
        42
        MATCH
          None { 0 }
          Some { 1 ADD }
        END
        """, env)

      assert Enum.any?(errors, fn e -> String.contains?(e.message, "variant") end)
    end

    test "MATCH on empty stack is a static error" do
      env = define("TYPE option = None | Some int")

      errors =
        check_errors("""
        MATCH
          None { 0 }
          Some { 1 ADD }
        END
        """, env)

      assert Enum.any?(errors, fn e -> String.contains?(e.message, "underflow") end)
    end
  end

  # ── Full pipeline ──

  describe "Full pipeline: TYPE + MATCH + DEF" do
    test "unwrap_or pattern" do
      # param_types = [option, int]: option is TOP of stack, int is below
      # Call: push default(int) first, then push option last (so option is on top)
      # Body: MATCH pops option (top); Some arm gets field on stack with default below
      {_, env} =
        Axiom.eval_with_env("""
        TYPE option = None | Some int
        DEF unwrap_or : option int -> int
          MATCH
            None { }
            Some { SWAP DROP }
          END
        END
        """)

      # Call: 0 42 Some unwrap_or → stack before call = [Some(42), 0] (Some on top)
      stack = run("0 42 Some unwrap_or", env)
      assert [42] = stack
    end

    test "unwrap_or returns default for None" do
      {_, env} =
        Axiom.eval_with_env("""
        TYPE option = None | Some int
        DEF unwrap_or : option int -> int
          MATCH
            None { }
            Some { SWAP DROP }
          END
        END
        """)

      # Call: 99 None unwrap_or → stack before call = [None, 99] (None on top)
      stack = run("99 None unwrap_or", env)
      assert [99] = stack
    end

    test "result type safe divide" do
      {_, env} =
        Axiom.eval_with_env("""
        TYPE result = Ok int | Err str
        DEF safe_div : int int -> result
          DUP 0 EQ
          IF
            DROP DROP "division by zero" Err
          ELSE
            DIV Ok
          END
        END
        """)

      stack =
        run("""
        10 2 safe_div
        MATCH
          Ok { }
          Err { DROP 0 }
        END
        """, env)

      assert [5] = stack
    end

    test "result type safe divide by zero" do
      {_, env} =
        Axiom.eval_with_env("""
        TYPE result = Ok int | Err str
        DEF safe_div : int int -> result
          DUP 0 EQ
          IF
            DROP DROP "division by zero" Err
          ELSE
            DIV Ok
          END
        END
        """)

      stack =
        run("""
        10 0 safe_div
        MATCH
          Ok { }
          Err { DROP -1 }
        END
        """, env)

      assert [-1] = stack
    end

    test "multiple TYPE declarations register all constructors" do
      env = define("TYPE color = Red | Green | Blue TYPE size = Small | Large")

      stack =
        run("""
        Green
        MATCH
          Red   { 0 }
          Green { 1 }
          Blue  { 2 }
        END
        """, env)

      assert [1] = stack
    end

    test "VERIFY still works after TYPE declaration" do
      {_, env} =
        Axiom.eval_with_env("""
        TYPE option = None | Some int
        DEF id : int -> int END
        """)

      assert Map.has_key?(env, "__types__")
      assert Map.has_key?(env, "__constructors__")
      assert Map.has_key?(env, "id")
      # Constructors are in __constructors__, not top-level env
      assert Map.has_key?(env["__constructors__"], "Some")
      assert Map.has_key?(env["__constructors__"], "None")
    end
  end

  # ── Unify: user_type ──

  describe "Unify: user_type" do
    alias Axiom.Checker.Unify

    test "same user_type unifies" do
      assert {:ok, {:user_type, "option"}} =
               Unify.unify({:user_type, "option"}, {:user_type, "option"})
    end

    test "different user_types do not unify" do
      assert :error = Unify.unify({:user_type, "option"}, {:user_type, "result"})
    end

    test "user_type unifies with any" do
      assert {:ok, {:user_type, "option"}} =
               Unify.unify({:user_type, "option"}, :any)
    end
  end
end
