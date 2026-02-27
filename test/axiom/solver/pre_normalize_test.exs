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

    normalized = PreNormalize.normalize({:and, implication, cond_expr})
    assert normalized in [{:and, rhs, cond_expr}, {:and, cond_expr, rhs}]
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

  test "pushes NOT through OR via DeMorgan" do
    a = {:eq, {:var, "p0_tag"}, {:const, 1}}
    b = {:gt, {:var, "p1"}, {:const, 0}}
    input = {:not, {:or, {:not, a}, {:not, b}}}

    assert PreNormalize.normalize(input) == {:and, a, b}
  end

  test "pushes NOT through AND via DeMorgan" do
    a = {:eq, {:var, "p0_tag"}, {:const, 1}}
    b = {:gt, {:var, "p1"}, {:const, 0}}
    input = {:not, {:and, a, b}}

    normalized = PreNormalize.normalize(input)
    assert normalized in [{:or, {:lte, {:var, "p1"}, {:const, 0}}, {:neq, {:var, "p0_tag"}, {:const, 1}}},
                          {:or, {:neq, {:var, "p0_tag"}, {:const, 1}}, {:lte, {:var, "p1"}, {:const, 0}}}]
  end

  test "negates comparison operators" do
    assert PreNormalize.normalize({:not, {:eq, {:var, "x"}, {:const, 1}}}) ==
             {:neq, {:var, "x"}, {:const, 1}}

    assert PreNormalize.normalize({:not, {:gt, {:var, "x"}, {:const, 0}}}) ==
             {:lte, {:var, "x"}, {:const, 0}}

    assert PreNormalize.normalize({:not, {:lte, {:var, "x"}, {:const, 0}}}) ==
             {:gt, {:var, "x"}, {:const, 0}}
  end
end
