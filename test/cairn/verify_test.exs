defmodule Cairn.VerifyTest do
  use ExUnit.Case

  # ── Lexer + Parser ──

  describe "VERIFY parsing" do
    test "lexer tokenizes VERIFY keyword" do
      assert {:ok, [{:verify_kw, "VERIFY", 0}, {:ident, "foo", 1}, {:int_lit, 100, 2}]} =
               Cairn.Lexer.tokenize("VERIFY foo 100")
    end

    test "parser produces verify item" do
      {:ok, tokens} = Cairn.Lexer.tokenize("VERIFY foo 100")
      {:ok, [item]} = Cairn.Parser.parse(tokens)
      assert {:verify, "foo", 100} = item
    end

    test "parser handles VERIFY after function def" do
      source = "DEF double : int -> int DUP ADD END VERIFY double 50"
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert length(items) == 2
      assert %Cairn.Types.Function{name: "double"} = hd(items)
      assert {:verify, "double", 50} = List.last(items)
    end

    test "parser handles VERIFY between expressions" do
      source = "DEF id : int -> int END VERIFY id 10 5 id"
      {:ok, tokens} = Cairn.Lexer.tokenize(source)
      {:ok, items} = Cairn.Parser.parse(tokens)
      assert length(items) == 3
    end
  end

  # ── Verify execution ──

  describe "VERIFY passing" do
    test "simple function without contracts" do
      source = "DEF double : int -> int DUP ADD END VERIFY double 50"
      # Should not raise — no contracts to violate
      assert {[], _env} = Cairn.eval_with_env(source)
    end

    test "function with PRE and POST that always hold" do
      source = """
      DEF square : int -> int
        DUP MUL
        POST DUP 0 GTE
      END
      VERIFY square 100
      """
      assert {[], _env} = Cairn.eval_with_env(source)
    end

    test "function with PRE filtering" do
      source = """
      DEF pos_double : int -> int
        PRE { DUP 0 GTE }
        DUP ADD
        POST DUP 0 GTE
      END
      VERIFY pos_double 50
      """
      assert {[], _env} = Cairn.eval_with_env(source)
    end

    test "multi-param function" do
      source = """
      DEF safe_add : int int -> int
        PRE { OVER 0 GTE SWAP 0 GTE AND }
        ADD
        POST DUP 0 GTE
      END
      VERIFY safe_add 100
      """
      assert {[], _env} = Cairn.eval_with_env(source)
    end
  end

  describe "VERIFY failing" do
    test "finds counterexample for bad POST" do
      source = """
      DEF bad_negate : int -> int
        NEG
        POST DUP 0 GTE
      END
      VERIFY bad_negate 100
      """
      # NEG of positive numbers produces negative, violating POST
      assert_raise Cairn.ContractError, ~r/VERIFY bad_negate: FAILED/, fn ->
        Cairn.eval_with_env(source)
      end
    end

    test "finds counterexample for weak PRE" do
      source = """
      DEF weak_withdraw : int int -> int
        PRE { DUP 0 GT }
        SUB
        POST DUP 0 GTE
      END
      VERIFY weak_withdraw 100
      """
      # PRE doesn't check balance >= amount, so POST will fail
      assert_raise Cairn.ContractError, ~r/VERIFY weak_withdraw: FAILED/, fn ->
        Cairn.eval_with_env(source)
      end
    end

    test "counterexample message includes args" do
      source = """
      DEF bad : int -> int
        NEG
        POST DUP 0 GT
      END
      VERIFY bad 100
      """
      try do
        Cairn.eval_with_env(source)
        flunk("expected ContractError")
      rescue
        e in Cairn.ContractError ->
          assert e.message =~ "counterexample:"
          assert e.message =~ "(int)"
      end
    end
  end

  describe "VERIFY edge cases" do
    test "undefined function raises error" do
      source = "VERIFY nonexistent 10"
      assert_raise Cairn.RuntimeError, ~r/undefined function/, fn ->
        Cairn.eval_with_env(source)
      end
    end

    test "function with no contracts just checks no runtime crash" do
      source = "DEF id : any -> any END VERIFY id 50"
      assert {[], _env} = Cairn.eval_with_env(source)
    end

    test "VERIFY works with string params" do
      source = """
      DEF echo : str -> str
      END
      VERIFY echo 20
      """
      assert {[], _env} = Cairn.eval_with_env(source)
    end

    test "VERIFY works with list params" do
      source = """
      DEF sum_list : [int] -> int
        SUM
      END
      VERIFY sum_list 20
      """
      assert {[], _env} = Cairn.eval_with_env(source)
    end

    test "VERIFY works with bool params" do
      source = """
      DEF flip : bool -> bool
        NOT
      END
      VERIFY flip 20
      """
      assert {[], _env} = Cairn.eval_with_env(source)
    end

    test "VERIFY works with bounded string-list practical helpers" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {[], _env} = Cairn.eval_file("examples/practical/mini_grep_verify.crn")
        end)

      assert output =~ "VERIFY leading_flag_count_bounded: OK"
    end
  end

  # ── Bank example as integration test ──

  describe "Safe Bank integration" do
    test "deposit passes verification" do
      source = """
      DEF deposit : int int -> int
        PRE { OVER 0 GTE SWAP 0 GT AND }
        ADD
        POST DUP 0 GTE
      END
      VERIFY deposit 200
      """
      assert {[], _env} = Cairn.eval_with_env(source)
    end

    test "withdraw passes verification" do
      source = """
      DEF withdraw : int int -> int
        PRE { OVER OVER GTE SWAP 0 GT AND }
        SUB
        POST DUP 0 GTE
      END
      VERIFY withdraw 200
      """
      assert {[], _env} = Cairn.eval_with_env(source)
    end

    test "buggy withdraw fails verification" do
      source = """
      DEF withdraw_buggy : int int -> int
        PRE { DUP 0 GT }
        SUB
        POST DUP 0 GTE
      END
      VERIFY withdraw_buggy 200
      """
      assert_raise Cairn.ContractError, ~r/VERIFY withdraw_buggy: FAILED/, fn ->
        Cairn.eval_with_env(source)
      end
    end
  end
end
