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

  test "detects non-complement contradictory comparison conjunctions" do
    input = {:and, {:gt, {:var, "x"}, {:const, 5}}, {:lte, {:var, "x"}, {:const, 3}}}
    assert PreNormalize.normalize(input) == false
  end

  test "detects non-complement tautological comparison disjunctions" do
    input = {:or, {:gt, {:var, "x"}, {:const, 5}}, {:lte, {:var, "x"}, {:const, 7}}}
    assert PreNormalize.normalize(input) == true
  end

  test "detects contradictory eq and strict bound conjunction" do
    input = {:and, {:eq, {:var, "x"}, {:const, 2}}, {:lt, {:var, "x"}, {:const, 2}}}
    assert PreNormalize.normalize(input) == false
  end

  test "merges compatible lower bounds to tighter one" do
    input = {:and, {:gt, {:var, "x"}, {:const, 3}}, {:gte, {:var, "x"}, {:const, 5}}}
    assert PreNormalize.normalize(input) == {:gte, {:var, "x"}, {:const, 5}}
  end

  test "collapses closed singleton interval to equality" do
    input = {:and, {:gte, {:var, "x"}, {:const, 5}}, {:lte, {:var, "x"}, {:const, 5}}}
    assert PreNormalize.normalize(input) == {:eq, {:var, "x"}, {:const, 5}}
  end

  test "detects contradiction after interval merge" do
    input = {:and, {:gte, {:var, "x"}, {:const, 5}}, {:lt, {:var, "x"}, {:const, 5}}}
    assert PreNormalize.normalize(input) == false
  end

  test "factors shared conjunct in disjunction of conjunctions" do
    a = {:eq, {:var, "p0_tag"}, {:const, 1}}
    b = {:gt, {:var, "x"}, {:const, 0}}
    c = {:lte, {:var, "x"}, {:const, 0}}
    input = {:or, {:and, a, b}, {:and, a, c}}

    assert PreNormalize.normalize(input) == a
  end

  test "does not over-factor unrelated conjunction disjunction" do
    a = {:eq, {:var, "p0_tag"}, {:const, 1}}
    b = {:gt, {:var, "x"}, {:const, 0}}
    c = {:lt, {:var, "y"}, {:const, 3}}
    d = {:neq, {:var, "z"}, {:const, 2}}
    input = {:or, {:and, a, b}, {:and, c, d}}

    assert PreNormalize.normalize(input) == {:or, {:and, a, b}, {:and, c, d}}
  end

  test "distributes guarded OR over conjunction for narrowing atom" do
    a = {:eq, {:var, "tag"}, {:const, 1}}
    b = {:gt, {:var, "x"}, {:const, 0}}
    c = {:lte, {:var, "x"}, {:const, 0}}
    input = {:or, a, {:and, b, c}}

    assert PreNormalize.normalize(input) == a
  end

  test "does not distribute when outer OR side is not narrowing atom" do
    a = {:and, {:gt, {:var, "x"}, {:const, 0}}, {:lt, {:var, "x"}, {:const, 10}}}
    b = {:eq, {:var, "y"}, {:const, 1}}
    c = {:neq, {:var, "z"}, {:const, 3}}
    input = {:or, a, {:and, b, c}}

    normalized = PreNormalize.normalize(input)
    assert normalized in [{:or, a, {:and, b, c}}, {:or, {:and, b, c}, a}]
  end

  test "reduces consensus form to shared disjunct" do
    a = {:eq, {:var, "p0_tag"}, {:const, 1}}
    b = {:gt, {:var, "x"}, {:const, 0}}
    input = {:and, {:or, a, b}, {:or, a, {:not, b}}}

    assert PreNormalize.normalize(input) == a
  end

  test "does not reduce non-consensus OR pair in conjunction" do
    a = {:eq, {:var, "p0_tag"}, {:const, 1}}
    b = {:gt, {:var, "x"}, {:const, 0}}
    c = {:lt, {:var, "x"}, {:const, 10}}
    input = {:and, {:or, a, b}, {:or, a, c}}

    normalized = PreNormalize.normalize(input)

    assert normalized in [
             {:and, {:or, a, b}, {:or, a, c}},
             {:and, {:or, b, a}, {:or, c, a}}
           ]
  end

  test "normalize_with_rewrites captures consensus rewrite metadata" do
    a = {:eq, {:var, "p0_tag"}, {:const, 1}}
    b = {:gt, {:var, "x"}, {:const, 0}}
    input = {:and, {:or, a, b}, {:or, a, {:not, b}}}

    {normalized, rewrites} = PreNormalize.normalize_with_rewrites(input)

    assert normalized == a
    assert Enum.any?(rewrites, fn r -> Map.get(r, :rule) == "and_reduce_consensus" end)
  end
end
