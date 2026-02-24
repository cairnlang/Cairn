defmodule Axiom.MapTest do
  use ExUnit.Case

  defp eval(source), do: Axiom.eval(source)

  defp check(source) do
    {:ok, tokens} = Axiom.Lexer.tokenize(source)
    {:ok, items} = Axiom.Parser.parse(tokens)
    Axiom.Checker.check(items)
  end

  # ── Lexer ──

  describe "Lexer — map tokens" do
    test "tokenizes M[ as map_open" do
      {:ok, tokens} = Axiom.Lexer.tokenize("M[")
      assert [{:map_open, "M[", 0}] = tokens
    end

    test "tokenizes M[] as empty map literal" do
      {:ok, tokens} = Axiom.Lexer.tokenize("M[]")
      assert [{:map_lit, %{}, 0}] = tokens
    end

    test "tokenizes M[ with contents and ]" do
      {:ok, tokens} = Axiom.Lexer.tokenize("M[ \"a\" 1 ]")
      types = Enum.map(tokens, fn {type, _, _} -> type end)
      assert types == [:map_open, :str_lit, :int_lit, :list_close]
    end

    test "tokenizes map operators" do
      for op <- ~w(GET PUT DEL KEYS VALUES HAS MLEN MERGE) do
        {:ok, [{:op, atom, 0}]} = Axiom.Lexer.tokenize(op)
        assert atom == String.to_atom(String.downcase(op))
      end
    end

    test "tokenizes map[str int] type" do
      {:ok, [{:type, type, 0}]} = Axiom.Lexer.tokenize("map[str int]")
      assert type == {:map, :str, :int}
    end

    test "tokenizes map[int bool] type" do
      {:ok, [{:type, type, 0}]} = Axiom.Lexer.tokenize("map[int bool]")
      assert type == {:map, :int, :bool}
    end

    test "tokenizes map with list value type" do
      {:ok, [{:type, type, 0}]} = Axiom.Lexer.tokenize("map[str [int]]")
      assert type == {:map, :str, {:list, :int}}
    end
  end

  # ── Evaluator ──

  describe "Evaluator — map construction" do
    test "empty map literal M[]" do
      assert [%{}] = eval("M[]")
    end

    test "map with string keys and int values" do
      assert [%{"a" => 1, "b" => 2}] = eval("M[ \"a\" 1 \"b\" 2 ]")
    end

    test "map with int keys" do
      assert [%{1 => "one", 2 => "two"}] = eval("M[ 1 \"one\" 2 \"two\" ]")
    end

    test "map with boolean values" do
      assert [%{"x" => true, "y" => false}] = eval("M[ \"x\" T \"y\" F ]")
    end

    test "map with float values" do
      assert [%{"pi" => 3.14}] = eval("M[ \"pi\" 3.14 ]")
    end

    test "single key-value pair" do
      assert [%{"key" => 42}] = eval("M[ \"key\" 42 ]")
    end
  end

  # ── Runtime — GET ──

  describe "Runtime — GET" do
    test "gets value by key" do
      assert [1] = eval("M[ \"a\" 1 \"b\" 2 ] \"a\" GET")
    end

    test "raises on missing key" do
      assert_raise KeyError, fn ->
        eval("M[ \"a\" 1 ] \"z\" GET")
      end
    end
  end

  # ── Runtime — PUT ──

  describe "Runtime — PUT" do
    test "adds a new key-value pair" do
      assert [%{"a" => 1, "b" => 2}] = eval("M[ \"a\" 1 ] \"b\" 2 PUT")
    end

    test "overwrites existing key" do
      assert [%{"a" => 99}] = eval("M[ \"a\" 1 ] \"a\" 99 PUT")
    end
  end

  # ── Runtime — DEL ──

  describe "Runtime — DEL" do
    test "removes a key" do
      assert [%{"b" => 2}] = eval("M[ \"a\" 1 \"b\" 2 ] \"a\" DEL")
    end

    test "no-op on missing key" do
      assert [%{"a" => 1}] = eval("M[ \"a\" 1 ] \"z\" DEL")
    end
  end

  # ── Runtime — KEYS ──

  describe "Runtime — KEYS" do
    test "returns list of keys" do
      [keys] = eval("M[ \"a\" 1 \"b\" 2 ] KEYS")
      assert Enum.sort(keys) == ["a", "b"]
    end

    test "empty map returns empty list" do
      assert [[]] = eval("M[] KEYS")
    end
  end

  # ── Runtime — VALUES ──

  describe "Runtime — VALUES" do
    test "returns list of values" do
      [vals] = eval("M[ \"a\" 1 \"b\" 2 ] VALUES")
      assert Enum.sort(vals) == [1, 2]
    end

    test "empty map returns empty list" do
      assert [[]] = eval("M[] VALUES")
    end
  end

  # ── Runtime — HAS ──

  describe "Runtime — HAS" do
    test "returns true for existing key" do
      assert [true] = eval("M[ \"a\" 1 ] \"a\" HAS")
    end

    test "returns false for missing key" do
      assert [false] = eval("M[ \"a\" 1 ] \"z\" HAS")
    end

    test "works on empty map" do
      assert [false] = eval("M[] \"x\" HAS")
    end
  end

  # ── Runtime — MLEN ──

  describe "Runtime — MLEN" do
    test "returns map size" do
      assert [2] = eval("M[ \"a\" 1 \"b\" 2 ] MLEN")
    end

    test "empty map has size 0" do
      assert [0] = eval("M[] MLEN")
    end
  end

  # ── Runtime — MERGE ──

  describe "Runtime — MERGE" do
    test "merges two maps" do
      assert [%{"a" => 1, "b" => 2}] = eval("M[ \"a\" 1 ] M[ \"b\" 2 ] MERGE")
    end

    test "right map wins on conflict" do
      assert [%{"a" => 99}] = eval("M[ \"a\" 1 ] M[ \"a\" 99 ] MERGE")
    end

    test "merge with empty map" do
      assert [%{"a" => 1}] = eval("M[ \"a\" 1 ] M[] MERGE")
    end
  end

  # ── Type Checker ──

  describe "Checker — map literals" do
    test "M[] is well-typed" do
      assert :ok = check("M[]")
    end

    test "M[ with values is well-typed" do
      assert :ok = check("M[ \"a\" 1 \"b\" 2 ]")
    end
  end

  describe "Checker — map operators" do
    test "GET type checks" do
      assert :ok = check("M[ \"a\" 1 ] \"a\" GET")
    end

    test "PUT type checks" do
      assert :ok = check("M[ \"a\" 1 ] \"b\" 2 PUT")
    end

    test "DEL type checks" do
      assert :ok = check("M[ \"a\" 1 ] \"a\" DEL")
    end

    test "KEYS type checks" do
      assert :ok = check("M[ \"a\" 1 ] KEYS")
    end

    test "VALUES type checks" do
      assert :ok = check("M[ \"a\" 1 ] VALUES")
    end

    test "HAS pushes bool" do
      assert :ok = check("M[ \"a\" 1 ] \"a\" HAS")
    end

    test "MLEN pushes int" do
      assert :ok = check("M[ \"a\" 1 ] MLEN")
    end

    test "MERGE type checks" do
      assert :ok = check("M[ \"a\" 1 ] M[ \"b\" 2 ] MERGE")
    end
  end

  describe "Checker — map in function signatures" do
    test "function with map param type checks" do
      source = """
      DEF map_size : map[str int] -> int
        MLEN
      END
      """
      assert :ok = check(source)
    end
  end

  # ── Unification ──

  describe "Unification — maps" do
    test "map[str int] unifies with itself" do
      assert {:ok, {:map, :str, :int}} =
               Axiom.Checker.Unify.unify({:map, :str, :int}, {:map, :str, :int})
    end

    test "map[any any] unifies with map[str int]" do
      assert {:ok, {:map, :str, :int}} =
               Axiom.Checker.Unify.unify({:map, :any, :any}, {:map, :str, :int})
    end

    test "map[str int] does not unify with map[int str]" do
      assert :error = Axiom.Checker.Unify.unify({:map, :str, :int}, {:map, :int, :str})
    end

    test "map does not unify with list" do
      assert :error = Axiom.Checker.Unify.unify({:map, :str, :int}, {:list, :str})
    end
  end

  # ── Integration: chained operations ──

  describe "Integration — chained map operations" do
    test "build, put, get" do
      assert [42] = eval("M[] \"x\" 42 PUT \"x\" GET")
    end

    test "build, put multiple, keys" do
      [keys] = eval("M[] \"a\" 1 PUT \"b\" 2 PUT KEYS")
      assert Enum.sort(keys) == ["a", "b"]
    end

    test "build, merge, mlen" do
      assert [3] = eval("M[ \"a\" 1 ] M[ \"b\" 2 \"c\" 3 ] MERGE MLEN")
    end

    test "has after del" do
      assert [false] = eval("M[ \"a\" 1 ] \"a\" DEL \"a\" HAS")
    end

    test "dup a map" do
      assert [%{"a" => 1}, %{"a" => 1}] = eval("M[ \"a\" 1 ] DUP")
    end
  end

  # ── Full pipeline with functions ──

  describe "Pipeline — map in full programs" do
    test "function using map operators" do
      {stack, _env} = Axiom.eval_with_env("""
      DEF get_a : map[str int] -> int
        "a" GET
      END
      M[ "a" 42 ] get_a
      """)
      assert stack == [42]
    end

    test "function that checks map size" do
      {stack, _env} = Axiom.eval_with_env("""
      DEF count : map[str int] -> int
        MLEN
      END
      M[ "x" 1 "y" 2 "z" 3 ] count
      """)
      assert stack == [3]
    end
  end

  # ── VERIFY with maps ──

  describe "VERIFY — map parameter generation" do
    test "generates map values for verification" do
      {_stack, _env} = Axiom.eval_with_env("""
      DEF map_id : map[str int] -> map[str int]
        PRE { DUP MLEN 0 GTE }
      END
      VERIFY map_id 20
      """)
    end
  end
end
