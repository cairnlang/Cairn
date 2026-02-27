defmodule Axiom.SolverTest do
  use ExUnit.Case, async: true

  alias Axiom.Solver.{Formula, Symbolic, SmtLib, Z3, Prove}
  alias Axiom.Types.Function

  # ============================================================
  # Formula module tests
  # ============================================================

  describe "Formula helpers" do
    test "var constructor" do
      assert Formula.var("p0") == {:var, "p0"}
    end

    test "const constructor" do
      assert Formula.const(42) == {:const, 42}
    end

    test "arithmetic constructors" do
      assert Formula.add({:var, "a"}, {:var, "b"}) == {:add, {:var, "a"}, {:var, "b"}}
      assert Formula.sub({:var, "a"}, {:var, "b"}) == {:sub, {:var, "a"}, {:var, "b"}}
      assert Formula.mul({:var, "a"}, {:var, "b"}) == {:mul, {:var, "a"}, {:var, "b"}}
      assert Formula.sdiv({:var, "a"}, {:var, "b"}) == {:div, {:var, "a"}, {:var, "b"}}
      assert Formula.smod({:var, "a"}, {:var, "b"}) == {:mod, {:var, "a"}, {:var, "b"}}
      assert Formula.neg({:var, "a"}) == {:neg, {:var, "a"}}
    end

    test "comparison constructors" do
      assert Formula.gte({:var, "a"}, {:const, 0}) == {:gte, {:var, "a"}, {:const, 0}}
      assert Formula.gt({:var, "a"}, {:const, 0}) == {:gt, {:var, "a"}, {:const, 0}}
      assert Formula.lte({:var, "a"}, {:const, 0}) == {:lte, {:var, "a"}, {:const, 0}}
      assert Formula.lt({:var, "a"}, {:const, 0}) == {:lt, {:var, "a"}, {:const, 0}}
      assert Formula.eq({:var, "a"}, {:const, 0}) == {:eq, {:var, "a"}, {:const, 0}}
      assert Formula.neq({:var, "a"}, {:const, 0}) == {:neq, {:var, "a"}, {:const, 0}}
    end

    test "logical constructors" do
      a = {:gte, {:var, "a"}, {:const, 0}}
      b = {:gt, {:var, "b"}, {:const, 0}}
      assert Formula.sand(a, b) == {:and, a, b}
      assert Formula.sor(a, b) == {:or, a, b}
      assert Formula.snot(a) == {:not, a}
    end

    test "sym_val constructors" do
      assert Formula.int_expr({:var, "p0"}) == {:int_expr, {:var, "p0"}}
      assert Formula.bool_expr(true) == {:bool_expr, true}
    end
  end

  # ============================================================
  # Symbolic execution tests
  # ============================================================

  describe "Symbolic.build_initial_stack" do
    test "builds stack for int params" do
      assert {:ok, stack, vars, base} = Symbolic.build_initial_stack([:int, :int])
      assert vars == ["p0", "p1"]
      assert stack == [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert base == true
    end

    test "single int param" do
      assert {:ok, stack, vars, base} = Symbolic.build_initial_stack([:int])
      assert vars == ["p0"]
      assert stack == [{:int_expr, {:var, "p0"}}]
      assert base == true
    end

    test "supports option params with tag domain constraints" do
      assert {:ok, stack, vars, base} = Symbolic.build_initial_stack([{:user_type, "option"}, :int])

      assert vars == ["p0_tag", "p0_val", "p1"]
      assert stack == [{:option_expr, {:var, "p0_tag"}, {:var, "p0_val"}}, {:int_expr, {:var, "p1"}}]
      assert base == {:or, {:eq, {:var, "p0_tag"}, {:const, 0}}, {:eq, {:var, "p0_tag"}, {:const, 1}}}
    end

    test "supports result params with tag domain constraints" do
      assert {:ok, stack, vars, base} = Symbolic.build_initial_stack([{:user_type, "result"}])

      assert vars == ["p0_tag", "p0_ok"]
      assert stack == [{:result_expr, {:var, "p0_tag"}, {:var, "p0_ok"}, "p0_err"}]
      assert base == {:or, {:eq, {:var, "p0_tag"}, {:const, 0}}, {:eq, {:var, "p0_tag"}, {:const, 1}}}
    end

    test "supports non-recursive int-field user ADTs when env types are available" do
      env = %{
        "__types__" => %{
          "shape" => %Axiom.Types.TypeDef{
            name: "shape",
            variants: %{"Circle" => [:int], "Square" => [:int]}
          }
        }
      }

      assert {:ok, stack, vars, base} = Symbolic.build_initial_stack([{:user_type, "shape"}], env)
      assert vars == ["p0_tag", "p0_Square_0", "p0_Circle_0"]

      assert stack == [
               {:variant_expr, "shape", {:var, "p0_tag"},
                %{
                  "Circle" => [{:int_expr, {:var, "p0_Circle_0"}}],
                  "Square" => [{:int_expr, {:var, "p0_Square_0"}}]
                }}
             ]

      assert base ==
               {:or, {:eq, {:var, "p0_tag"}, {:const, 0}},
                {:eq, {:var, "p0_tag"}, {:const, 1}}}
    end

    test "rejects non-int params" do
      assert {:unsupported, reason} = Symbolic.build_initial_stack([:int, :bool])
      assert reason =~ "supported: int, option, result"
    end

    test "rejects float params" do
      assert {:unsupported, _} = Symbolic.build_initial_stack([:float])
    end

    test "rejects list params" do
      assert {:unsupported, _} = Symbolic.build_initial_stack([{:list, :int}])
    end
  end

  describe "Symbolic.execute — arithmetic ops" do
    test "ADD" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:add, {:var, "p1"}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :add, 0}], stack)
    end

    test "SUB" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:sub, {:var, "p1"}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :sub, 0}], stack)
    end

    test "MUL" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:mul, {:var, "p1"}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :mul, 0}], stack)
    end

    test "DIV" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:div, {:var, "p1"}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :div, 0}], stack)
    end

    test "MOD" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:mod, {:var, "p1"}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :mod, 0}], stack)
    end

    test "NEG" do
      stack = [{:int_expr, {:var, "p0"}}]
      assert {:ok, [{:int_expr, {:neg, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :neg, 0}], stack)
    end

    test "SQ" do
      stack = [{:int_expr, {:var, "p0"}}]
      assert {:ok, [{:int_expr, {:mul, {:var, "p0"}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :sq, 0}], stack)
    end
  end

  describe "Symbolic.execute — comparisons" do
    test "GTE" do
      stack = [{:int_expr, {:const, 0}}, {:int_expr, {:var, "p0"}}]
      assert {:ok, [{:bool_expr, {:gte, {:var, "p0"}, {:const, 0}}}]} =
               Symbolic.execute([{:op, :gte, 0}], stack)
    end

    test "GT" do
      stack = [{:int_expr, {:const, 0}}, {:int_expr, {:var, "p0"}}]
      assert {:ok, [{:bool_expr, {:gt, {:var, "p0"}, {:const, 0}}}]} =
               Symbolic.execute([{:op, :gt, 0}], stack)
    end

    test "LTE" do
      stack = [{:int_expr, {:const, 0}}, {:int_expr, {:var, "p0"}}]
      assert {:ok, [{:bool_expr, {:lte, {:var, "p0"}, {:const, 0}}}]} =
               Symbolic.execute([{:op, :lte, 0}], stack)
    end

    test "LT" do
      stack = [{:int_expr, {:const, 0}}, {:int_expr, {:var, "p0"}}]
      assert {:ok, [{:bool_expr, {:lt, {:var, "p0"}, {:const, 0}}}]} =
               Symbolic.execute([{:op, :lt, 0}], stack)
    end

    test "EQ" do
      stack = [{:int_expr, {:const, 0}}, {:int_expr, {:var, "p0"}}]
      assert {:ok, [{:bool_expr, {:eq, {:var, "p0"}, {:const, 0}}}]} =
               Symbolic.execute([{:op, :eq, 0}], stack)
    end

    test "NEQ" do
      stack = [{:int_expr, {:const, 0}}, {:int_expr, {:var, "p0"}}]
      assert {:ok, [{:bool_expr, {:neq, {:var, "p0"}, {:const, 0}}}]} =
               Symbolic.execute([{:op, :neq, 0}], stack)
    end
  end

  describe "Symbolic.execute — logic ops" do
    test "AND" do
      stack = [{:bool_expr, {:gt, {:var, "p0"}, {:const, 0}}},
               {:bool_expr, {:gte, {:var, "p1"}, {:const, 0}}}]
      assert {:ok, [{:bool_expr, {:and, {:gte, {:var, "p1"}, {:const, 0}},
                                        {:gt, {:var, "p0"}, {:const, 0}}}}]} =
               Symbolic.execute([{:op, :and, 0}], stack)
    end

    test "OR" do
      stack = [{:bool_expr, {:gt, {:var, "p0"}, {:const, 0}}},
               {:bool_expr, {:gte, {:var, "p1"}, {:const, 0}}}]
      assert {:ok, [{:bool_expr, {:or, _, _}}]} =
               Symbolic.execute([{:op, :or, 0}], stack)
    end

    test "NOT" do
      stack = [{:bool_expr, {:gt, {:var, "p0"}, {:const, 0}}}]
      assert {:ok, [{:bool_expr, {:not, {:gt, {:var, "p0"}, {:const, 0}}}}]} =
               Symbolic.execute([{:op, :not, 0}], stack)
    end
  end

  describe "Symbolic.execute — stack ops" do
    test "DUP" do
      stack = [{:int_expr, {:var, "p0"}}]
      assert {:ok, [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p0"}}]} =
               Symbolic.execute([{:op, :dup, 0}], stack)
    end

    test "DROP" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:var, "p1"}}]} =
               Symbolic.execute([{:op, :drop, 0}], stack)
    end

    test "SWAP" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:var, "p1"}}, {:int_expr, {:var, "p0"}}]} =
               Symbolic.execute([{:op, :swap, 0}], stack)
    end

    test "OVER" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:var, "p1"}}, {:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]} =
               Symbolic.execute([{:op, :over, 0}], stack)
    end

    test "ROT" do
      stack = [{:int_expr, {:var, "a"}}, {:int_expr, {:var, "b"}}, {:int_expr, {:var, "c"}}]
      assert {:ok, [{:int_expr, {:var, "c"}}, {:int_expr, {:var, "a"}}, {:int_expr, {:var, "b"}}]} =
               Symbolic.execute([{:op, :rot, 0}], stack)
    end
  end

  describe "Symbolic.execute — literals" do
    test "integer literal" do
      assert {:ok, [{:int_expr, {:const, 42}}]} =
               Symbolic.execute([{:int_lit, 42, 0}], [])
    end

    test "boolean true literal" do
      assert {:ok, [{:bool_expr, true}]} =
               Symbolic.execute([{:bool_lit, true, 0}], [])
    end

    test "boolean false literal" do
      assert {:ok, [{:bool_expr, false}]} =
               Symbolic.execute([{:bool_lit, false, 0}], [])
    end

    test "negative integer literal" do
      assert {:ok, [{:int_expr, {:const, -5}}]} =
               Symbolic.execute([{:int_lit, -5, 0}], [])
    end
  end

  describe "Symbolic.execute — ABS, MIN, MAX" do
    test "ABS produces ite expression" do
      stack = [{:int_expr, {:var, "p0"}}]
      assert {:ok, [{:int_expr, {:ite, {:lt, {:var, "p0"}, {:const, 0}}, {:neg, {:var, "p0"}}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :abs, 0}], stack)
    end

    test "MIN produces ite expression" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:ite, {:lt, {:var, "p1"}, {:var, "p0"}}, {:var, "p1"}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :min, 0}], stack)
    end

    test "MAX produces ite expression" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:ite, {:gt, {:var, "p1"}, {:var, "p0"}}, {:var, "p1"}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :max, 0}], stack)
    end
  end

  describe "Symbolic.execute — unsupported ops" do
    test "FILTER returns unsupported" do
      assert {:unsupported, reason} = Symbolic.execute([{:op, :filter, 0}], [])
      assert reason =~ "FILTER"
    end

    test "function call returns unsupported" do
      assert {:unsupported, reason} = Symbolic.execute([{:ident, "foo", 0}], [])
      assert reason =~ "foo"
    end

    test "float literal returns unsupported" do
      assert {:unsupported, _} = Symbolic.execute([{:float_lit, 3.14, 0}], [])
    end

    test "list literal returns unsupported" do
      assert {:unsupported, _} = Symbolic.execute([{:list_open, "[", 0}], [])
    end

    test "IF without bool condition on stack returns unsupported" do
      assert {:unsupported, _} = Symbolic.execute([{:if_kw, "IF", 0}], [{:int_expr, {:var, "p0"}}])
    end
  end

  describe "Symbolic.execute — IF/ELSE" do
    test "IF/END (no ELSE) — identity on false branch" do
      # DUP 0 LT IF NEG END — abs via IF without ELSE
      stack = [{:int_expr, {:var, "p0"}}]
      tokens = [
        {:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :lt, 2},
        {:if_kw, "IF", 3}, {:op, :neg, 4}, {:fn_end, "END", 5}
      ]
      assert {:ok, [{:int_expr, result}]} = Symbolic.execute(tokens, stack)
      # Should be ite(p0 < 0, -p0, p0)
      assert {:ite, {:lt, {:var, "p0"}, {:const, 0}}, {:neg, {:var, "p0"}}, {:var, "p0"}} = result
    end

    test "IF/ELSE/END — both branches" do
      # DUP 0 GTE IF ELSE NEG END — abs via IF/ELSE
      stack = [{:int_expr, {:var, "p0"}}]
      tokens = [
        {:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gte, 2},
        {:if_kw, "IF", 3}, {:else_kw, "ELSE", 4}, {:op, :neg, 5}, {:fn_end, "END", 6}
      ]
      assert {:ok, [{:int_expr, result}]} = Symbolic.execute(tokens, stack)
      # true branch is identity (p0), false branch is NEG (neg p0)
      assert {:ite, {:gte, {:var, "p0"}, {:const, 0}}, {:var, "p0"}, {:neg, {:var, "p0"}}} = result
    end

    test "IF/ELSE with operations in both branches" do
      # DUP 0 GT IF 1 ADD ELSE 1 SUB END
      stack = [{:int_expr, {:var, "p0"}}]
      tokens = [
        {:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gt, 2},
        {:if_kw, "IF", 3},
        {:int_lit, 1, 4}, {:op, :add, 5},
        {:else_kw, "ELSE", 6},
        {:int_lit, 1, 7}, {:op, :sub, 8},
        {:fn_end, "END", 9}
      ]
      assert {:ok, [{:int_expr, result}]} = Symbolic.execute(tokens, stack)
      assert {:ite, {:gt, {:var, "p0"}, {:const, 0}},
              {:add, {:var, "p0"}, {:const, 1}},
              {:sub, {:var, "p0"}, {:const, 1}}} = result
    end

    test "IF with continuation tokens after END" do
      # DUP 0 LT IF NEG END 1 ADD
      stack = [{:int_expr, {:var, "p0"}}]
      tokens = [
        {:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :lt, 2},
        {:if_kw, "IF", 3}, {:op, :neg, 4}, {:fn_end, "END", 5},
        {:int_lit, 1, 6}, {:op, :add, 7}
      ]
      assert {:ok, [{:int_expr, result}]} = Symbolic.execute(tokens, stack)
      # abs(p0) + 1
      assert {:add, {:ite, {:lt, {:var, "p0"}, {:const, 0}}, {:neg, {:var, "p0"}}, {:var, "p0"}}, {:const, 1}} = result
    end

    test "ROT4" do
      stack = [{:int_expr, {:var, "a"}}, {:int_expr, {:var, "b"}},
               {:int_expr, {:var, "c"}}, {:int_expr, {:var, "d"}}]
      assert {:ok, [{:int_expr, {:var, "d"}}, {:int_expr, {:var, "a"}},
                     {:int_expr, {:var, "b"}}, {:int_expr, {:var, "c"}}]} =
               Symbolic.execute([{:op, :rot4, 0}], stack)
    end
  end

  describe "Symbolic.execute — MATCH on option" do
    test "option MATCH merges Some/None branches with ite" do
      stack = [{:option_expr, {:var, "p0_tag"}, {:var, "p0_val"}}, {:int_expr, {:var, "p1"}}]

      tokens = [
        {:match_kw, "MATCH", 0},
        {:constructor, "None", 1}, {:block_open, "{", 2}, {:block_close, "}", 3},
        {:constructor, "Some", 4}, {:block_open, "{", 5}, {:op, :swap, 6}, {:op, :drop, 7}, {:block_close, "}", 8},
        {:fn_end, "END", 9}
      ]

      assert {:ok, [{:int_expr, result}]} = Symbolic.execute(tokens, stack)
      assert {:ite, {:eq, {:var, "p0_tag"}, {:const, 1}}, {:var, "p0_val"}, {:var, "p1"}} = result
    end
  end

  describe "Symbolic.execute — MATCH on result" do
    test "result MATCH merges Ok/Err branches with ite" do
      stack = [{:result_expr, {:var, "p0_tag"}, {:var, "p0_ok"}, "p0_err"}, {:int_expr, {:var, "fallback"}}]

      tokens = [
        {:match_kw, "MATCH", 0},
        {:constructor, "Err", 1}, {:block_open, "{", 2}, {:op, :drop, 3}, {:block_close, "}", 4},
        {:constructor, "Ok", 5}, {:block_open, "{", 6}, {:op, :swap, 7}, {:op, :drop, 8}, {:block_close, "}", 9},
        {:fn_end, "END", 10}
      ]

      assert {:ok, [{:int_expr, result}]} = Symbolic.execute(tokens, stack)
      assert {:ite, {:eq, {:var, "p0_tag"}, {:const, 1}}, {:var, "p0_ok"}, {:var, "fallback"}} = result
    end
  end

  describe "Symbolic.execute — MATCH on generic user ADT" do
    test "generic MATCH merges constructor branches with ite" do
      stack = [
        {:variant_expr, "shape", {:var, "p0_tag"},
         %{
           "Circle" => [{:int_expr, {:var, "p0_Circle_0"}}],
           "Square" => [{:int_expr, {:var, "p0_Square_0"}}]
         }}
      ]

      tokens = [
        {:match_kw, "MATCH", 0},
        {:constructor, "Circle", 1},
        {:block_open, "{", 2},
        {:op, :dup, 3},
        {:op, :mul, 4},
        {:block_close, "}", 5},
        {:constructor, "Square", 6},
        {:block_open, "{", 7},
        {:block_close, "}", 8},
        {:fn_end, "END", 9}
      ]

      env = %{
        "__types__" => %{
          "shape" => %Axiom.Types.TypeDef{
            name: "shape",
            variants: %{"Circle" => [:int], "Square" => [:int]}
          }
        }
      }

      assert {:ok, [{:int_expr, result}]} = Symbolic.execute(tokens, stack, env)

      assert {:ite, {:eq, {:var, "p0_tag"}, {:const, 1}}, {:var, "p0_Square_0"},
              {:mul, {:var, "p0_Circle_0"}, {:var, "p0_Circle_0"}}} = result
    end

    test "known constructor tag from PRE assumptions prunes unreachable unsupported branch" do
      stack = [
        {:variant_expr, "shape", {:var, "p0_tag"},
         %{
           "Circle" => [{:int_expr, {:var, "p0_Circle_0"}}],
           "Square" => [{:int_expr, {:var, "p0_Square_0"}}]
         }}
      ]

      tokens = [
        {:match_kw, "MATCH", 0},
        {:constructor, "Circle", 1},
        {:block_open, "{", 2},
        {:op, :len, 3},
        {:block_close, "}", 4},
        {:constructor, "Square", 5},
        {:block_open, "{", 6},
        {:op, :abs, 7},
        {:block_close, "}", 8},
        {:fn_end, "END", 9}
      ]

      env = %{
        "__types__" => %{
          "shape" => %Axiom.Types.TypeDef{
            name: "shape",
            variants: %{"Circle" => [:int], "Square" => [:int]}
          }
        },
        "__prove_tag_assumptions__" => %{"p0_tag" => 1}
      }

      assert {:ok, [{:int_expr, {:ite, {:lt, {:var, "p0_Square_0"}, {:const, 0}},
                                {:neg, {:var, "p0_Square_0"}}, {:var, "p0_Square_0"}}}]} =
               Symbolic.execute(tokens, stack, env)
    end

    test "neq-style assumptions can also prune to a single reachable branch" do
      stack = [
        {:variant_expr, "shape", {:var, "p0_tag"},
         %{
           "Circle" => [{:int_expr, {:var, "p0_Circle_0"}}],
           "Square" => [{:int_expr, {:var, "p0_Square_0"}}]
         }}
      ]

      tokens = [
        {:match_kw, "MATCH", 0},
        {:constructor, "Circle", 1},
        {:block_open, "{", 2},
        {:op, :len, 3},
        {:block_close, "}", 4},
        {:constructor, "Square", 5},
        {:block_open, "{", 6},
        {:op, :abs, 7},
        {:block_close, "}", 8},
        {:fn_end, "END", 9}
      ]

      env = %{
        "__types__" => %{
          "shape" => %Axiom.Types.TypeDef{
            name: "shape",
            variants: %{"Circle" => [:int], "Square" => [:int]}
          }
        },
        "__prove_tag_assumptions__" => %{
          "p0_tag" => %{eq: nil, neq: MapSet.new([0])}
        }
      }

      assert {:ok, [{:int_expr, {:ite, {:lt, {:var, "p0_Square_0"}, {:const, 0}},
                                {:neg, {:var, "p0_Square_0"}}, {:var, "p0_Square_0"}}}]} =
               Symbolic.execute(tokens, stack, env)
    end
  end

  describe "Symbolic.execute — compound operations" do
    test "deposit PRE: OVER 0 GTE SWAP 0 GT AND" do
      # Stack: [p0 (amount on top), p1 (balance)]
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      tokens = [
        {:op, :over, 0},   # [p1, p0, p1]
        {:int_lit, 0, 1},  # [0, p1, p0, p1]
        {:op, :gte, 2},    # [p1>=0, p0, p1]
        {:op, :swap, 3},   # [p0, p1>=0, p1]
        {:int_lit, 0, 4},  # [0, p0, p1>=0, p1]
        {:op, :gt, 5},     # [p0>0, p1>=0, p1]
        {:op, :and, 6}     # [(p1>=0)∧(p0>0), p1]
      ]
      assert {:ok, [{:bool_expr, pre_constraint}, {:int_expr, {:var, "p1"}}]} =
               Symbolic.execute(tokens, stack)

      # Should be AND of (p1 >= 0) and (p0 > 0)
      assert {:and, {:gte, {:var, "p1"}, {:const, 0}}, {:gt, {:var, "p0"}, {:const, 0}}} =
               pre_constraint
    end

    test "deposit body: ADD" do
      stack = [{:int_expr, {:var, "p0"}}, {:int_expr, {:var, "p1"}}]
      assert {:ok, [{:int_expr, {:add, {:var, "p1"}, {:var, "p0"}}}]} =
               Symbolic.execute([{:op, :add, 0}], stack)
    end

    test "deposit POST: DUP 0 GTE" do
      result_stack = [{:int_expr, {:add, {:var, "p1"}, {:var, "p0"}}}]
      tokens = [
        {:op, :dup, 0},
        {:int_lit, 0, 1},
        {:op, :gte, 2}
      ]
      assert {:ok, [{:bool_expr, post_constraint}, {:int_expr, _}]} =
               Symbolic.execute(tokens, result_stack)

      assert {:gte, {:add, {:var, "p1"}, {:var, "p0"}}, {:const, 0}} = post_constraint
    end
  end

  describe "Symbolic.extract_bool_constraint" do
    test "extracts from bool_expr" do
      stack = [{:bool_expr, {:gt, {:var, "p0"}, {:const, 0}}}]
      assert {:ok, {:gt, {:var, "p0"}, {:const, 0}}} = Symbolic.extract_bool_constraint(stack)
    end

    test "error on int_expr top" do
      stack = [{:int_expr, {:var, "p0"}}]
      assert {:error, _} = Symbolic.extract_bool_constraint(stack)
    end

    test "error on empty stack" do
      assert {:error, _} = Symbolic.extract_bool_constraint([])
    end
  end

  # ============================================================
  # SMT-LIB generation tests
  # ============================================================

  describe "SmtLib.emit_expr" do
    test "variable" do
      assert SmtLib.emit_expr({:var, "p0"}) == "p0"
    end

    test "positive constant" do
      assert SmtLib.emit_expr({:const, 42}) == "42"
    end

    test "zero constant" do
      assert SmtLib.emit_expr({:const, 0}) == "0"
    end

    test "negative constant" do
      assert SmtLib.emit_expr({:const, -5}) == "(- 5)"
    end

    test "add" do
      assert SmtLib.emit_expr({:add, {:var, "p0"}, {:var, "p1"}}) == "(+ p0 p1)"
    end

    test "sub" do
      assert SmtLib.emit_expr({:sub, {:var, "p0"}, {:const, 1}}) == "(- p0 1)"
    end

    test "mul" do
      assert SmtLib.emit_expr({:mul, {:var, "p0"}, {:var, "p0"}}) == "(* p0 p0)"
    end

    test "div" do
      assert SmtLib.emit_expr({:div, {:var, "p0"}, {:const, 2}}) == "(div p0 2)"
    end

    test "mod" do
      assert SmtLib.emit_expr({:mod, {:var, "p0"}, {:const, 3}}) == "(mod p0 3)"
    end

    test "neg" do
      assert SmtLib.emit_expr({:neg, {:var, "p0"}}) == "(- p0)"
    end

    test "nested expression" do
      expr = {:add, {:mul, {:var, "p0"}, {:var, "p0"}}, {:const, 1}}
      assert SmtLib.emit_expr(expr) == "(+ (* p0 p0) 1)"
    end

    test "ite expression" do
      expr = {:ite, {:lt, {:var, "p0"}, {:const, 0}}, {:neg, {:var, "p0"}}, {:var, "p0"}}
      assert SmtLib.emit_expr(expr) == "(ite (< p0 0) (- p0) p0)"
    end
  end

  describe "SmtLib.emit_constraint" do
    test "true" do
      assert SmtLib.emit_constraint(true) == "true"
    end

    test "false" do
      assert SmtLib.emit_constraint(false) == "false"
    end

    test "gte" do
      assert SmtLib.emit_constraint({:gte, {:var, "p0"}, {:const, 0}}) == "(>= p0 0)"
    end

    test "gt" do
      assert SmtLib.emit_constraint({:gt, {:var, "p0"}, {:const, 0}}) == "(> p0 0)"
    end

    test "lte" do
      assert SmtLib.emit_constraint({:lte, {:var, "p0"}, {:const, 10}}) == "(<= p0 10)"
    end

    test "lt" do
      assert SmtLib.emit_constraint({:lt, {:var, "p0"}, {:const, 0}}) == "(< p0 0)"
    end

    test "eq" do
      assert SmtLib.emit_constraint({:eq, {:var, "p0"}, {:const, 0}}) == "(= p0 0)"
    end

    test "neq" do
      assert SmtLib.emit_constraint({:neq, {:var, "p0"}, {:const, 0}}) == "(not (= p0 0))"
    end

    test "and" do
      c = {:and, {:gte, {:var, "p0"}, {:const, 0}}, {:gt, {:var, "p1"}, {:const, 0}}}
      assert SmtLib.emit_constraint(c) == "(and (>= p0 0) (> p1 0))"
    end

    test "or" do
      c = {:or, {:lt, {:var, "p0"}, {:const, 0}}, {:gt, {:var, "p0"}, {:const, 10}}}
      assert SmtLib.emit_constraint(c) == "(or (< p0 0) (> p0 10))"
    end

    test "not" do
      c = {:not, {:eq, {:var, "p0"}, {:const, 0}}}
      assert SmtLib.emit_constraint(c) == "(not (= p0 0))"
    end

    test "ite_bool" do
      c = {:ite_bool, {:lt, {:var, "p0"}, {:const, 0}}, {:gt, {:var, "p0"}, {:const, 0}}, false}
      assert SmtLib.emit_constraint(c) == "(ite (< p0 0) (> p0 0) false)"
    end
  end

  describe "SmtLib.build_script" do
    test "generates valid SMT-LIB for deposit" do
      pre = {:and, {:gte, {:var, "p1"}, {:const, 0}}, {:gt, {:var, "p0"}, {:const, 0}}}
      post = {:gte, {:add, {:var, "p1"}, {:var, "p0"}}, {:const, 0}}

      script = SmtLib.build_script(["p0", "p1"], pre, post)

      assert script =~ "(set-logic QF_NIA)"
      assert script =~ "(declare-const p0 Int)"
      assert script =~ "(declare-const p1 Int)"
      assert script =~ "(assert (and (>= p1 0) (> p0 0)))"
      assert script =~ "(assert (not (>= (+ p1 p0) 0)))"
      assert script =~ "(check-sat)"
      assert script =~ "(get-model)"
    end

    test "handles true PRE (no precondition)" do
      post = {:gte, {:var, "p0"}, {:const, 0}}
      script = SmtLib.build_script(["p0"], true, post)

      assert script =~ "(assert true)"
      assert script =~ "(assert (not (>= p0 0)))"
    end
  end

  describe "SmtLib.collect_vars" do
    test "collects variables from constraint" do
      c = {:and, {:gte, {:var, "p0"}, {:const, 0}}, {:gt, {:var, "p1"}, {:const, 0}}}
      vars = SmtLib.collect_vars(c)
      assert MapSet.member?(vars, "p0")
      assert MapSet.member?(vars, "p1")
    end

    test "true has no vars" do
      assert SmtLib.collect_vars(true) == MapSet.new()
    end

    test "nested expressions" do
      c = {:gte, {:add, {:var, "x"}, {:var, "y"}}, {:const, 0}}
      vars = SmtLib.collect_vars(c)
      assert MapSet.equal?(vars, MapSet.new(["x", "y"]))
    end

    test "collects vars through ite in expr" do
      # ite(p0 < 0, -p0, p0) >= 0
      c = {:gte, {:ite, {:lt, {:var, "p0"}, {:const, 0}}, {:neg, {:var, "p0"}}, {:var, "p0"}}, {:const, 0}}
      vars = SmtLib.collect_vars(c)
      assert MapSet.equal?(vars, MapSet.new(["p0"]))
    end

    test "collects vars through ite_bool in constraint" do
      c = {:ite_bool, {:lt, {:var, "x"}, {:const, 0}}, {:gt, {:var, "y"}, {:const, 0}}, {:gt, {:var, "z"}, {:const, 0}}}
      vars = SmtLib.collect_vars(c)
      assert MapSet.equal?(vars, MapSet.new(["x", "y", "z"]))
    end
  end

  # ============================================================
  # Z3 module tests
  # ============================================================

  describe "Z3.available?" do
    test "returns true when z3 is installed" do
      assert Z3.available?()
    end
  end

  describe "Z3.parse_model" do
    test "parses positive integers" do
      model = """
      (model
        (define-fun p0 () Int 1)
        (define-fun p1 () Int 42)
      )
      """
      assert Z3.parse_model(model) == %{"p0" => 1, "p1" => 42}
    end

    test "parses negative integers" do
      model = """
      (model
        (define-fun p0 () Int (- 5))
        (define-fun p1 () Int 0)
      )
      """
      assert Z3.parse_model(model) == %{"p0" => -5, "p1" => 0}
    end

    test "parses mixed positive and negative" do
      model = """
      (model
        (define-fun p0 () Int 100)
        (define-fun p1 () Int (- 3))
      )
      """
      assert Z3.parse_model(model) == %{"p0" => 100, "p1" => -3}
    end

    test "empty model" do
      assert Z3.parse_model("") == %{}
    end
  end

  describe "Z3.query — integration" do
    test "unsat result" do
      # p0 > 0 AND p0 < 0 is unsatisfiable
      script = """
      (set-logic QF_NIA)
      (declare-const p0 Int)
      (assert (> p0 0))
      (assert (< p0 0))
      (check-sat)
      (get-model)
      """
      assert :unsat = Z3.query(script)
    end

    test "sat result with model" do
      # p0 > 5 is satisfiable
      script = """
      (set-logic QF_NIA)
      (declare-const p0 Int)
      (assert (> p0 5))
      (check-sat)
      (get-model)
      """
      assert {:sat, model} = Z3.query(script)
      assert is_map(model)
      assert model["p0"] > 5
    end

    test "deposit formula is unsat (POST always holds given PRE)" do
      script = """
      (set-logic QF_NIA)
      (declare-const p0 Int)
      (declare-const p1 Int)
      (assert (and (>= p1 0) (> p0 0)))
      (assert (not (>= (+ p1 p0) 0)))
      (check-sat)
      (get-model)
      """
      assert :unsat = Z3.query(script)
    end

    test "withdraw_buggy formula is sat (POST can fail)" do
      # PRE: p0 > 0 (amount > 0, but no balance check)
      # POST: p1 - p0 >= 0 (result >= 0)
      script = """
      (set-logic QF_NIA)
      (declare-const p0 Int)
      (declare-const p1 Int)
      (assert (> p0 0))
      (assert (not (>= (- p1 p0) 0)))
      (check-sat)
      (get-model)
      """
      assert {:sat, model} = Z3.query(script)
      assert is_map(model)
      # The counterexample should have amount > balance
      assert model["p0"] > 0
    end
  end

  # ============================================================
  # Prove orchestration tests
  # ============================================================

  describe "Prove.prove — deposit (should be proven)" do
    test "proves deposit POST holds for all inputs satisfying PRE" do
      func = %Function{
        name: "deposit",
        param_types: [:int, :int],
        return_types: [:int],
        body: [{:op, :add, 0}],
        pre_condition: [
          {:op, :over, 0}, {:int_lit, 0, 1}, {:op, :gte, 2},
          {:op, :swap, 3}, {:int_lit, 0, 4}, {:op, :gt, 5},
          {:op, :and, 6}
        ],
        post_condition: [{:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gte, 2}]
      }

      assert {:proven, _} = Prove.prove(func)
    end
  end

  describe "Prove.prove — withdraw (should be proven)" do
    test "proves withdraw with strong PRE" do
      func = %Function{
        name: "withdraw",
        param_types: [:int, :int],
        return_types: [:int],
        body: [{:op, :sub, 0}],
        pre_condition: [
          {:op, :over, 0}, {:op, :over, 1}, {:op, :gte, 2},
          {:op, :swap, 3}, {:int_lit, 0, 4}, {:op, :gt, 5},
          {:op, :and, 6}
        ],
        post_condition: [{:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gte, 2}]
      }

      assert {:proven, _} = Prove.prove(func)
    end
  end

  describe "Prove.prove — withdraw_buggy (should be disproven)" do
    test "disproves buggy withdraw with counterexample" do
      func = %Function{
        name: "withdraw_buggy",
        param_types: [:int, :int],
        return_types: [:int],
        body: [{:op, :sub, 0}],
        pre_condition: [
          {:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gt, 2}
        ],
        post_condition: [{:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gte, 2}]
      }

      assert {:disproven, counterexample, model} = Prove.prove(func)
      assert is_binary(counterexample)
      assert is_map(model)
      # p0 (amount) should be > 0 per PRE, but p1 - p0 < 0
      assert model["p0"] > 0
    end
  end

  describe "Prove.prove — no PRE (vacuously proven if POST always holds)" do
    test "proves identity with no PRE and always-true POST" do
      # DEF id : int -> int body: (no-op, just identity) POST DUP DUP EQ
      # This is: result == result, always true
      func = %Function{
        name: "id",
        param_types: [:int],
        return_types: [:int],
        body: [],
        pre_condition: nil,
        post_condition: [{:op, :dup, 0}, {:op, :dup, 1}, {:op, :eq, 2}]
      }

      assert {:proven, _} = Prove.prove(func)
    end
  end

  describe "Prove.prove — no POST (vacuously true)" do
    test "no POST is vacuously proven" do
      func = %Function{
        name: "add",
        param_types: [:int, :int],
        return_types: [:int],
        body: [{:op, :add, 0}],
        pre_condition: nil,
        post_condition: nil
      }

      assert {:proven, _} = Prove.prove(func)
    end
  end

  describe "Prove.prove — abs with IF (should be proven)" do
    test "proves abs POST >= 0" do
      func = %Function{
        name: "my_abs",
        param_types: [:int],
        return_types: [:int],
        body: [
          {:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :lt, 2},
          {:if_kw, "IF", 3}, {:op, :neg, 4}, {:fn_end, "END", 5}
        ],
        pre_condition: nil,
        post_condition: [{:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gte, 2}]
      }

      assert {:proven, _} = Prove.prove(func)
    end
  end

  describe "Prove.prove — IF/ELSE disprovable" do
    test "disproves IF/ELSE with wrong postcondition" do
      # DEF bad : int -> int
      #   DUP 0 GT IF 1 ADD ELSE 1 SUB END
      #   POST DUP 0 GT  -- fails when input is 0 (0-1 = -1, not > 0)
      func = %Function{
        name: "bad",
        param_types: [:int],
        return_types: [:int],
        body: [
          {:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gt, 2},
          {:if_kw, "IF", 3},
          {:int_lit, 1, 4}, {:op, :add, 5},
          {:else_kw, "ELSE", 6},
          {:int_lit, 1, 7}, {:op, :sub, 8},
          {:fn_end, "END", 9}
        ],
        pre_condition: nil,
        post_condition: [{:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gt, 2}]
      }

      assert {:disproven, _, _} = Prove.prove(func)
    end
  end

  describe "Prove.prove — unsupported operations" do
    test "function with list ops returns unknown" do
      func = %Function{
        name: "list_op",
        param_types: [:int],
        return_types: [:int],
        body: [{:op, :len, 0}],
        pre_condition: nil,
        post_condition: [{:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gte, 2}]
      }

      assert {:unknown, reason} = Prove.prove(func)
      assert reason =~ "LEN"
    end

    test "function with non-int params returns unknown" do
      func = %Function{
        name: "bool_func",
        param_types: [:bool],
        return_types: [:bool],
        body: [],
        pre_condition: nil,
        post_condition: nil
      }

      assert {:unknown, reason} = Prove.prove(func)
      assert reason =~ "supported: int, option, result"
    end

    test "function with IF and unsupported body op returns unknown" do
      func = %Function{
        name: "if_func",
        param_types: [:int],
        return_types: [:int],
        body: [{:int_lit, 0, 0}, {:op, :gt, 1}, {:if_kw, "IF", 2}, {:op, :print, 3}, {:fn_end, "END", 4}],
        pre_condition: nil,
        post_condition: nil
      }

      assert {:unknown, reason} = Prove.prove(func)
      assert reason =~ "PRINT"
    end

    test "MATCH on result type can be disproven" do
      source = """
      TYPE result = Ok int | Err str

      DEF bad_match : result -> int
        MATCH
          Ok  { }
          Err { DROP 0 }
        END
        POST DUP 0 GTE
      END

      PROVE bad_match
      """

      assert_raise Axiom.ContractError, ~r/PROVE bad_match: DISPROVEN/, fn ->
        Axiom.eval(source)
      end
    end
  end

  describe "Prove.prove — option MATCH (v0.6.0a slice)" do
    test "proves unwrap_or_abs is non-negative" do
      source = """
      TYPE option = None | Some int

      DEF unwrap_or_abs : option int -> int
        MATCH
          None { ABS }
          Some { SWAP DROP ABS }
        END
        POST DUP 0 GTE
      END

      PROVE unwrap_or_abs
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE unwrap_or_abs: PROVEN"
    end

    test "proves is_some_bool has boolean tautology postcondition" do
      source = """
      TYPE option = None | Some int

      DEF is_some_bool : option -> bool
        MATCH
          None { F }
          Some { DROP T }
        END
        POST DUP NOT OR
      END

      PROVE is_some_bool
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE is_some_bool: PROVEN"
    end
  end

  describe "Prove.prove — result MATCH (v0.6.0b slice)" do
    test "proves unwrap_ok_or_default is non-negative" do
      source = """
      DEF unwrap_ok_or_default : result int -> int
        PRE { OVER 0 GTE }
        MATCH
          Ok  { ABS SWAP DROP }
          Err { DROP }
        END
        POST DUP 0 GTE
      END

      PROVE unwrap_ok_or_default
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE unwrap_ok_or_default: PROVEN"
    end

    test "proves is_ok_bool has boolean tautology postcondition" do
      source = """
      DEF is_ok_bool : result -> bool
        MATCH
          Ok  { DROP T }
          Err { DROP F }
        END
        POST DUP NOT OR
      END

      PROVE is_ok_bool
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE is_ok_bool: PROVEN"
    end
  end

  describe "Prove.prove — generic ADT MATCH (v0.6.0c slice)" do
    test "proves non-negativity on a user ADT beyond option/result" do
      source = """
      TYPE shape = Circle int | Square int

      DEF size_nonneg : shape -> int
        MATCH
          Circle { ABS }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE size_nonneg
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE size_nonneg: PROVEN"
    end

    test "PRE can prune unreachable MATCH branch during proving" do
      source = """
      TYPE shape = Circle int | Square int

      DEF square_only_abs : shape -> int
        PRE {
          MATCH
            Circle { DROP F }
            Square { DROP T }
          END
        }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs: PROVEN"
    end

    test "OR-shaped PRE form still infers constructor narrowing" do
      source = """
      TYPE shape = Circle int | Square int

      DEF square_only_abs_or : shape -> int
        PRE {
          MATCH
            Circle { DROP F }
            Square { DROP T }
          END
          DUP OR
        }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_or
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_or: PROVEN"
    end

    test "NOT-shaped PRE form still infers constructor narrowing" do
      source = """
      TYPE shape = Circle int | Square int

      DEF square_only_abs_not : shape -> int
        PRE {
          MATCH
            Circle { DROP T }
            Square { DROP F }
          END
          NOT
        }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_not
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_not: PROVEN"
    end

    test "helper boolean EQ true still infers constructor narrowing" do
      source = """
      TYPE shape = Circle int | Square int

      DEF is_square : shape -> bool
        MATCH
          Circle { DROP F }
          Square { DROP T }
        END
      END

      DEF square_only_abs_eq_true : shape -> int
        PRE { is_square T EQ }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_eq_true
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_eq_true: PROVEN"
    end

    test "composed helper with dead boolean branch still infers constructor narrowing" do
      source = """
      TYPE shape = Circle int | Square int

      DEF is_square : shape -> bool
        MATCH
          Circle { DROP F }
          Square { DROP T }
        END
      END

      DEF impossible_square : shape -> bool
        is_square
        DUP NOT
        AND
      END

      DEF square_by_composed_guard : shape -> bool
        DUP is_square
        SWAP impossible_square
        OR
      END

      DEF square_only_abs_composed : shape -> int
        PRE { square_by_composed_guard }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_composed
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_composed: PROVEN"
    end

    test "composed helper tautology does not narrow MATCH and remains UNKNOWN" do
      source = """
      TYPE shape = Circle int | Square int

      DEF is_square : shape -> bool
        MATCH
          Circle { DROP F }
          Square { DROP T }
        END
      END

      DEF any_shape : shape -> bool
        DUP is_square
        SWAP is_square NOT
        OR
      END

      DEF square_only_abs_tautology : shape -> int
        PRE { any_shape }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_tautology
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_tautology: UNKNOWN"
      assert output =~ "LEN is not supported by PROVE"
    end

    test "boolean split alias form in composed helper still narrows constructor" do
      source = """
      TYPE shape = Circle int | Square int

      DEF is_square : shape -> bool
        MATCH
          Circle { DROP F }
          Square { DROP T }
        END
      END

      DEF has_pos_payload : shape -> bool
        MATCH
          Circle { 0 GT }
          Square { 0 GT }
        END
      END

      DEF split_alias : bool bool -> bool
        OVER OVER AND
        ROT
        NOT
        AND
        OR
      END

      DEF square_guard_split : shape -> bool
        DUP is_square
        SWAP has_pos_payload
        SWAP
        split_alias
      END

      DEF square_only_abs_split : shape -> int
        PRE { square_guard_split }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_split
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_split: PROVEN"
    end

    test "implication plus antecedent in PRE narrows constructor" do
      source = """
      TYPE shape = Circle int | Square int

      DEF is_square : shape -> bool
        MATCH
          Circle { DROP F }
          Square { DROP T }
        END
      END

      DEF square_only_abs_implied : int shape -> int
        PRE {
          DUP 0 GT
          ROT
          is_square
          SWAP
          DUP NOT
          ROT
          OR
          AND
        }
        SWAP
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        SWAP DROP
        POST DUP 0 GTE
      END

      PROVE square_only_abs_implied
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_implied: PROVEN"
    end

    test "implication without antecedent does not narrow and remains UNKNOWN" do
      source = """
      TYPE shape = Circle int | Square int

      DEF is_square : shape -> bool
        MATCH
          Circle { DROP F }
          Square { DROP T }
        END
      END

      DEF square_only_abs_implication_only : int shape -> int
        PRE {
          DUP 0 GT
          NOT
          ROT
          is_square
          OR
        }
        SWAP
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        SWAP DROP
        POST DUP 0 GTE
      END

      PROVE square_only_abs_implication_only
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_implication_only: UNKNOWN"
      assert output =~ "LEN is not supported by PROVE"
    end

    test "noisy duplicated and reordered helper guard still narrows constructor" do
      source = """
      TYPE shape = Circle int | Square int

      DEF is_square : shape -> bool
        MATCH
          Circle { DROP F }
          Square { DROP T }
        END
      END

      DEF has_pos_payload : shape -> bool
        MATCH
          Circle { 0 GT }
          Square { 0 GT }
        END
      END

      # Equivalent to is_square, but intentionally noisy:
      # is_square AND is_square AND (has_pos OR NOT has_pos)
      DEF square_guard_noisy : shape -> bool
        DUP has_pos_payload
        SWAP is_square
        DUP
        ROT
        DUP NOT OR
        AND
        AND
      END

      DEF square_only_abs_noisy : shape -> int
        PRE { square_guard_noisy }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_noisy
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_noisy: PROVEN"
    end

    test "deMorgan plus comparison negation in PRE still narrows constructor" do
      source = """
      TYPE shape = Circle int | Square int

      DEF is_square : shape -> bool
        MATCH
          Circle { DROP F }
          Square { DROP T }
        END
      END

      # PRE computes NOT ((NOT is_square(shape)) OR (NOT (amount > 0)))
      # which normalizes to is_square(shape) AND (amount > 0).
      DEF square_only_abs_demorgan : int shape -> int
        PRE {
          DUP 0 GT NOT
          ROT
          is_square
          NOT
          OR
          NOT
        }
        SWAP
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        SWAP DROP
        POST DUP 0 GTE
      END

      PROVE square_only_abs_demorgan
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_demorgan: PROVEN"
    end

    test "non-complement contradictory comparison branch in PRE is pruned for narrowing" do
      source = """
      TYPE shape = Circle int | Square int

      DEF is_square : shape -> bool
        MATCH
          Circle { DROP F }
          Square { DROP T }
        END
      END

      # PRE computes:
      #   ((amount > 5) AND (amount <= 3)) OR is_square(shape)
      # first branch is contradictory and normalizes to false.
      DEF square_only_abs_pair_pruned : int shape -> int
        PRE {
          DUP 5 GT
          OVER 3 LTE
          AND
          ROT
          is_square
          OR
          SWAP DROP
        }
        SWAP
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        SWAP DROP
        POST DUP 0 GTE
      END

      PROVE square_only_abs_pair_pruned
      """

      output = ExUnit.CaptureIO.capture_io(fn -> Axiom.eval(source) end)
      assert output =~ "PROVE square_only_abs_pair_pruned: PROVEN"
    end

    test "trace summary mode prints to stderr (not stdout)" do
      source = """
      TYPE shape = Circle int | Square int

      DEF square_only_abs_trace : shape -> int
        PRE {
          MATCH
            Circle { DROP T }
            Square { DROP F }
          END
          NOT
        }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_trace
      """

      parent = self()

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          stdout =
            ExUnit.CaptureIO.capture_io(fn ->
              Axiom.eval_with_env(source, %{"__prove_trace__" => :summary})
            end)

          send(parent, {:captured_stdout, stdout})
        end)

      stdout =
        receive do
          {:captured_stdout, out} -> out
        end

      assert stdout =~ "PROVE square_only_abs_trace: PROVEN"
      refute stdout =~ "PROVE TRACE"
      assert stderr =~ "PROVE TRACE square_only_abs_trace (PROVEN, summary):"
      assert stderr =~ "MATCH shape:"
      refute stderr =~ "candidates="
    end

    test "trace verbose mode includes candidate details" do
      source = """
      TYPE shape = Circle int | Square int

      DEF square_only_abs_trace_verbose : shape -> int
        PRE {
          MATCH
            Circle { DROP T }
            Square { DROP F }
          END
          NOT
        }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_trace_verbose
      """

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Axiom.eval_with_env(source, %{"__prove_trace__" => :verbose})
        end)

      assert stderr =~ "PROVE TRACE square_only_abs_trace_verbose (PROVEN, verbose):"
      assert stderr =~ "candidates="
      assert stderr =~ "tag="
    end

    test "trace is silent by default" do
      source = """
      TYPE shape = Circle int | Square int

      DEF square_only_abs_trace_default : shape -> int
        PRE {
          MATCH
            Circle { DROP T }
            Square { DROP F }
          END
          NOT
        }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_trace_default
      """

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Axiom.eval(source)
        end)

      assert stderr == ""
    end

    test "trace json mode emits lifecycle + MATCH decision events to stderr" do
      source = """
      TYPE shape = Circle int | Square int

      DEF square_only_abs_trace_json : shape -> int
        PRE {
          MATCH
            Circle { DROP T }
            Square { DROP F }
          END
          NOT
        }
        MATCH
          Circle { LEN }
          Square { ABS }
        END
        POST DUP 0 GTE
      END

      PROVE square_only_abs_trace_json
      """

      parent = self()

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          stdout =
            ExUnit.CaptureIO.capture_io(fn ->
              Axiom.eval_with_env(source, %{"__prove_trace__" => :json})
            end)

          send(parent, {:captured_stdout, stdout})
        end)

      stdout =
        receive do
          {:captured_stdout, out} -> out
        end

      assert stdout =~ "PROVE square_only_abs_trace_json: PROVEN"
      refute stdout =~ "PROVE TRACE"
      refute stderr =~ "PROVE TRACE"
      assert stderr =~ "\"event\":\"prove_run_start\""
      assert stderr =~ "\"event\":\"prove_run_end\""
      assert stderr =~ "\"event\":\"pre_executed\""
      assert stderr =~ "\"event\":\"body_executed\""
      assert stderr =~ "\"event\":\"post_executed\""
      assert stderr =~ "\"event\":\"z3_query\""
      assert stderr =~ "\"event\":\"match_decision\""
      assert stderr =~ "\"trace_level\":\"json\""
      assert stderr =~ "\"function\":\"square_only_abs_trace_json\""
      assert stderr =~ "\"status\":\"PROVEN\""
      assert stderr =~ "\"event_index\":0"
      assert stderr =~ "\"type\":\"shape\""
      assert stderr =~ "\"phase\":\"pre\""
      assert stderr =~ "\"phase\":\"body\""
      assert stderr =~ "\"match_site_id\":\"square_only_abs_trace_json:body:"
      assert stderr =~ "\"assumptions\":"
      assert stderr =~ "\"elapsed_ms\":"
      assert stderr =~ "\"match_event_count\":"
      assert stderr =~ "\"pruned_branch_count\":"
      assert stderr =~ "\"body_stack_depth\":"
      assert stderr =~ "\"has_pre\":true"
      assert stderr =~ "\"has_post\":true"
      assert stderr =~ "\"unknown_reason\":null"
      assert stderr =~ "\"error_reason\":null"
      assert stderr =~ "\"var_count\":"
      assert stderr =~ "\"z3_result\":\"unsat\""
      assert stderr =~ "\"explored\":"
      assert stderr =~ "\"pruned\":"
      assert stderr =~ "\"reason\":"
    end

    test "trace json mode includes unknown_reason in run_end for UNKNOWN proofs" do
      source = """
      DEF trace_unknown_json : int -> int
        LEN
        POST DUP 0 GTE
      END

      PROVE trace_unknown_json
      """

      parent = self()

      stderr =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          stdout =
            ExUnit.CaptureIO.capture_io(fn ->
              Axiom.eval_with_env(source, %{"__prove_trace__" => :json})
            end)

          send(parent, {:captured_stdout, stdout})
        end)

      stdout =
        receive do
          {:captured_stdout, out} -> out
        end

      assert stdout =~ "PROVE trace_unknown_json: UNKNOWN"
      assert stderr =~ "\"event\":\"prove_run_end\""
      assert stderr =~ "\"status\":\"UNKNOWN\""
      assert stderr =~ "\"unknown_reason\":"
      assert stderr =~ "\"error_reason\":null"
      refute stderr =~ "\"event\":\"z3_query\""
    end
  end

  describe "Prove.prove — function call inlining" do
    test "proves function that calls another function" do
      abs_func = %Function{
        name: "my_abs",
        param_types: [:int],
        return_types: [:int],
        body: [
          {:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :lt, 2},
          {:if_kw, "IF", 3}, {:op, :neg, 4}, {:fn_end, "END", 5}
        ],
        pre_condition: nil,
        post_condition: nil
      }

      dist_func = %Function{
        name: "distance",
        param_types: [:int, :int],
        return_types: [:int],
        body: [{:op, :sub, 0}, {:ident, "my_abs", 1}],
        pre_condition: nil,
        post_condition: [{:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gte, 2}]
      }

      env = %{"my_abs" => abs_func, "distance" => dist_func}
      assert {:proven, _} = Prove.prove(dist_func, env)
    end

    test "inlining unknown function returns unsupported" do
      func = %Function{
        name: "caller",
        param_types: [:int],
        return_types: [:int],
        body: [{:ident, "unknown_fn", 0}],
        pre_condition: nil,
        post_condition: nil
      }

      assert {:unknown, reason} = Prove.prove(func, %{})
      assert reason =~ "unknown_fn"
    end

    test "deep recursion returns unsupported" do
      rec_func = %Function{
        name: "rec",
        param_types: [:int],
        return_types: [:int],
        body: [{:ident, "rec", 0}],
        pre_condition: nil,
        post_condition: nil
      }

      env = %{"rec" => rec_func}
      assert {:unknown, reason} = Prove.prove(rec_func, env)
      assert reason =~ "inlining depth"
    end
  end

  describe "Prove.prove — MUL provable (nonlinear arithmetic)" do
    test "DUP MUL with POST DUP 0 GTE is proven (squares are non-negative)" do
      func = %Function{
        name: "square",
        param_types: [:int],
        return_types: [:int],
        body: [{:op, :dup, 0}, {:op, :mul, 1}],
        pre_condition: nil,
        post_condition: [{:op, :dup, 0}, {:int_lit, 0, 1}, {:op, :gte, 2}]
      }

      assert {:proven, _} = Prove.prove(func)
    end
  end

  describe "Prove.format_counterexample" do
    test "formats model with param names" do
      func = %Function{
        name: "test",
        param_types: [:int, :int],
        return_types: [:int],
        body: [],
        pre_condition: nil,
        post_condition: nil
      }

      result = Prove.format_counterexample(%{"p0" => 5, "p1" => -3}, func)
      assert result == "p0 = 5, p1 = -3"
    end

    test "formats option/result params as constructor-shaped values" do
      func = %Function{
        name: "test_sum_types",
        param_types: [{:user_type, "option"}, {:user_type, "result"}],
        return_types: [:int],
        body: [],
        pre_condition: nil,
        post_condition: nil
      }

      model = %{"p0_tag" => 1, "p0_val" => 7, "p1_tag" => 0}
      result = Prove.format_counterexample(model, func)
      assert result == "p0 = Some(7), p1 = Err(_)"
    end

    test "formats generic user ADT params using ctor tag + payload vars" do
      func = %Function{
        name: "shape_test",
        param_types: [{:user_type, "shape"}],
        return_types: [:int],
        body: [],
        pre_condition: nil,
        post_condition: nil
      }

      env = %{
        "__types__" => %{
          "shape" => %Axiom.Types.TypeDef{
            name: "shape",
            variants: %{"Circle" => [:int], "Square" => [:int]}
          }
        }
      }

      model = %{"p0_tag" => 1, "p0_Square_0" => -3}
      result = Prove.format_counterexample(model, func, env)
      assert result == "p0 = Square(-3)"
    end
  end

  # ============================================================
  # Full pipeline integration tests (via Axiom.eval)
  # ============================================================

  describe "full PROVE pipeline — via Axiom.eval" do
    test "PROVE deposit succeeds" do
      source = """
      DEF deposit : int int -> int
        PRE { OVER 0 GTE SWAP 0 GT AND }
        ADD
        POST DUP 0 GTE
      END
      PROVE deposit
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Axiom.eval(source)
      end)
      assert output =~ "PROVE deposit: PROVEN"
    end

    test "PROVE withdraw succeeds" do
      source = """
      DEF withdraw : int int -> int
        PRE { OVER OVER GTE SWAP 0 GT AND }
        SUB
        POST DUP 0 GTE
      END
      PROVE withdraw
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Axiom.eval(source)
      end)
      assert output =~ "PROVE withdraw: PROVEN"
    end

    test "PROVE withdraw_buggy fails with counterexample" do
      source = """
      DEF withdraw_buggy : int int -> int
        PRE { DUP 0 GT }
        SUB
        POST DUP 0 GTE
      END
      PROVE withdraw_buggy
      """

      assert_raise Axiom.ContractError, ~r/DISPROVEN/, fn ->
        Axiom.eval(source)
      end
    end

    test "PROVE generic ADT failure prints decoded constructor counterexample" do
      source = """
      TYPE shape = Circle int | Square int

      DEF bad_shape_nonneg : shape -> int
        MATCH
          Circle { }
          Square { }
        END
        POST DUP 0 GTE
      END

      PROVE bad_shape_nonneg
      """

      assert_raise Axiom.ContractError, ~r/counterexample: p0 = (Circle|Square)\(-?[0-9]+\)/, fn ->
        Axiom.eval(source)
      end
    end

    test "PROVE abs_func with IF/ELSE is proven" do
      source = """
      DEF abs_func : int -> int
        DUP 0 GTE IF ELSE NEG END
        POST DUP 0 GTE
      END
      PROVE abs_func
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Axiom.eval(source)
      end)
      assert output =~ "PROVEN"
    end

    test "PROVE on function with unsupported ops prints UNKNOWN" do
      source = """
      DEF list_sum : int -> int
        RANGE SUM
        POST DUP 0 GTE
      END
      PROVE list_sum
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Axiom.eval(source)
      end)
      assert output =~ "UNKNOWN"
    end

    test "PROVE on undefined function raises error" do
      source = "PROVE nonexistent"

      assert_raise Axiom.RuntimeError, ~r/undefined function/, fn ->
        Axiom.eval(source)
      end
    end

    test "PROVE squares are non-negative (nonlinear)" do
      source = """
      DEF square : int -> int
        DUP MUL
        POST DUP 0 GTE
      END
      PROVE square
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Axiom.eval(source)
      end)
      assert output =~ "PROVEN"
    end

    test "PROVE with VERIFY in same file" do
      source = """
      DEF deposit : int int -> int
        PRE { OVER 0 GTE SWAP 0 GT AND }
        ADD
        POST DUP 0 GTE
      END
      VERIFY deposit 50
      PROVE deposit
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Axiom.eval(source)
      end)
      assert output =~ "VERIFY deposit: OK"
      assert output =~ "PROVE deposit: PROVEN"
    end

    test "PROVE function with no PRE and no POST is vacuously proven" do
      source = """
      DEF add_nums : int int -> int
        ADD
      END
      PROVE add_nums
      """

      output = ExUnit.CaptureIO.capture_io(fn ->
        Axiom.eval(source)
      end)
      assert output =~ "PROVEN"
    end
  end

  # ============================================================
  # Lexer/Parser tests for PROVE keyword
  # ============================================================

  describe "Lexer — PROVE keyword" do
    test "tokenizes PROVE" do
      {:ok, tokens} = Axiom.Lexer.tokenize("PROVE deposit")
      assert [{:prove_kw, "PROVE", 0}, {:ident, "deposit", 1}] = tokens
    end
  end

  describe "Parser — PROVE statement" do
    test "parses PROVE name" do
      {:ok, tokens} = Axiom.Lexer.tokenize("PROVE deposit")
      {:ok, items} = Axiom.Parser.parse(tokens)
      assert [{:prove, "deposit"}] = items
    end

    test "PROVE without name is error" do
      {:ok, tokens} = Axiom.Lexer.tokenize("PROVE")
      assert {:error, _} = Axiom.Parser.parse(tokens)
    end

    test "expression splitting works with PROVE" do
      {:ok, tokens} = Axiom.Lexer.tokenize("1 2 ADD PROVE foo")
      {:ok, items} = Axiom.Parser.parse(tokens)
      assert [{:expr, _}, {:prove, "foo"}] = items
    end
  end
end
