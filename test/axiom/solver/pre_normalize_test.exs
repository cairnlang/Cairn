defmodule Axiom.Solver.PreNormalizeTest do
  use ExUnit.Case, async: true

  alias Axiom.Solver.PreNormalize

  test "flattens and deduplicates n-ary conjunctions" do
    input =
      {:and, {:eq, {:var, "p0_tag"}, {:const, 1}},
       {:and, {:eq, {:var, "p0_tag"}, {:const, 1}}, true}}

    assert PreNormalize.normalize(input) == {:eq, {:var, "p0_tag"}, {:const, 1}}
  end

  test "collapses complement pairs" do
    eq = {:eq, {:var, "p0_tag"}, {:const, 1}}

    assert PreNormalize.normalize({:and, eq, {:not, eq}}) == false
    assert PreNormalize.normalize({:or, eq, {:not, eq}}) == true
  end

  test "reduces implication with antecedent" do
    cond_expr = {:gt, {:var, "p0"}, {:const, 0}}
    rhs = {:eq, {:var, "p1_tag"}, {:const, 1}}
    implication = {:or, {:not, cond_expr}, rhs}

    assert PreNormalize.normalize({:and, implication, cond_expr}) ==
             {:and, rhs, cond_expr}
  end

  test "reduces split disjunction alias" do
    a = {:eq, {:var, "p0_tag"}, {:const, 1}}
    b = {:gt, {:var, "p1"}, {:const, 0}}
    input = {:or, {:and, a, b}, {:and, a, {:not, b}}}

    assert PreNormalize.normalize(input) == a
  end

  test "normalizes bool eq encoding with true constant" do
    a = {:eq, {:var, "p0_tag"}, {:const, 1}}
    encoded = {:or, {:and, a, true}, {:and, {:not, a}, {:not, true}}}

    assert PreNormalize.normalize(encoded) == a
  end
end
