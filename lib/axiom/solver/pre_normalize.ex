defmodule Axiom.Solver.PreNormalize do
  @moduledoc """
  Canonical normalization for PROVE PRE boolean constraints.

  Keeps equivalent constraints in a stable shape so assumption extraction in
  `Axiom.Solver.Prove` is resilient to noisy/generated boolean structure.
  """

  @spec normalize(term()) :: term()
  def normalize({:and, a, b}) do
    [normalize(a), normalize(b)]
    |> flatten_terms(:and)
    |> simplify_and_terms()
  end

  def normalize({:or, a, b}) do
    [normalize(a), normalize(b)]
    |> flatten_terms(:or)
    |> simplify_or_terms()
  end

  def normalize({:not, c}) do
    c = normalize(c)

    cond do
      c == true -> false
      c == false -> true
      match?({:not, _}, c) -> elem(c, 1)
      match?({:and, _, _}, c) -> normalize(push_not_via_demorgan(c, :or))
      match?({:or, _, _}, c) -> normalize(push_not_via_demorgan(c, :and))
      negatable_comparison?(c) -> negate_comparison(c)
      true -> {:not, c}
    end
  end

  def normalize({:ite_bool, cond, true, false}) do
    normalize(cond)
  end

  def normalize({:ite_bool, cond, false, true}) do
    normalize({:not, cond})
  end

  def normalize(c), do: c

  defp push_not_via_demorgan({op, a, b}, new_op) when op in [:and, :or] do
    {new_op, {:not, a}, {:not, b}}
  end

  defp negatable_comparison?({:eq, _, _}), do: true
  defp negatable_comparison?({:neq, _, _}), do: true
  defp negatable_comparison?({:gt, _, _}), do: true
  defp negatable_comparison?({:gte, _, _}), do: true
  defp negatable_comparison?({:lt, _, _}), do: true
  defp negatable_comparison?({:lte, _, _}), do: true
  defp negatable_comparison?(_), do: false

  defp negate_comparison({:eq, a, b}), do: {:neq, a, b}
  defp negate_comparison({:neq, a, b}), do: {:eq, a, b}
  defp negate_comparison({:gt, a, b}), do: {:lte, a, b}
  defp negate_comparison({:gte, a, b}), do: {:lt, a, b}
  defp negate_comparison({:lt, a, b}), do: {:gte, a, b}
  defp negate_comparison({:lte, a, b}), do: {:gt, a, b}

  defp simplify_and_terms(terms) do
    cond do
      Enum.any?(terms, &(&1 == false)) ->
        false

      true ->
        terms
        |> Enum.reject(&(&1 == true))
        |> canonical_terms()
        |> reduce_implication_terms()
        |> remove_absorbed_terms(:and)
        |> flatten_terms(:and)
        |> canonical_terms()
        |> then(fn canonical ->
          if has_complement_pair?(canonical), do: false, else: build_constraint(:and, canonical)
        end)
    end
  end

  defp simplify_or_terms(terms) do
    cond do
      Enum.any?(terms, &(&1 == true)) ->
        true

      true ->
        terms
        |> Enum.reject(&(&1 == false))
        |> canonical_terms()
        |> reduce_or_pair_terms()
        |> remove_absorbed_terms(:or)
        |> flatten_terms(:or)
        |> canonical_terms()
        |> then(fn canonical ->
          if has_complement_pair?(canonical), do: true, else: build_constraint(:or, canonical)
        end)
    end
  end

  defp flatten_terms(terms, :and) do
    Enum.flat_map(terms, fn
      {:and, x, y} -> flatten_terms([x, y], :and)
      other -> [other]
    end)
  end

  defp flatten_terms(terms, :or) do
    Enum.flat_map(terms, fn
      {:or, x, y} -> flatten_terms([x, y], :or)
      other -> [other]
    end)
  end

  defp canonical_terms(terms) do
    terms
    |> Enum.uniq()
    |> Enum.sort_by(&constraint_sort_key/1)
  end

  defp constraint_sort_key(term), do: :erlang.term_to_binary(term)

  defp has_complement_pair?(terms) do
    terms
    |> Enum.with_index()
    |> Enum.any?(fn {left, i} ->
      terms
      |> Enum.drop(i + 1)
      |> Enum.any?(&constraint_complements?(left, &1))
    end)
  end

  defp build_constraint(:and, []), do: true
  defp build_constraint(:or, []), do: false
  defp build_constraint(_op, [single]), do: single

  defp build_constraint(op, [head | tail]) do
    Enum.reduce(tail, head, fn term, acc ->
      {op, acc, term}
    end)
  end

  # (NOT c OR a) AND c => a (and symmetric variants) when both terms are present
  defp reduce_implication_terms(terms) do
    Enum.map(terms, &reduce_implication_term(&1, terms))
  end

  defp reduce_implication_term({:or, left, right}, all_terms) do
    cond do
      Enum.any?(all_terms, &constraint_complements?(left, &1)) -> right
      Enum.any?(all_terms, &constraint_complements?(right, &1)) -> left
      true -> {:or, left, right}
    end
  end

  defp reduce_implication_term(term, _all_terms), do: term

  defp reduce_or_pair_terms(terms) do
    case find_reduced_or_pair(terms) do
      {:ok, reduced_terms} -> reduced_terms |> flatten_terms(:or) |> canonical_terms() |> reduce_or_pair_terms()
      :none -> terms
    end
  end

  defp find_reduced_or_pair(terms) do
    indexed = Enum.with_index(terms)

    Enum.reduce_while(indexed, :none, fn {left, i}, _acc ->
      right_candidates = Enum.drop(indexed, i + 1)

      case Enum.find_value(right_candidates, fn {right, j} ->
             case reduce_or_pair(left, right) do
               {:reduced, reduced} ->
                 remaining =
                   indexed
                   |> Enum.reject(fn {_term, idx} -> idx == i or idx == j end)
                   |> Enum.map(fn {term, _idx} -> term end)

                 {:ok, [reduced | remaining]}

               :none ->
                 nil
             end
           end) do
        nil -> {:cont, :none}
        {:ok, _} = found -> {:halt, found}
      end
    end)
  end

  defp reduce_or_pair(left, right) do
    expr = {:or, left, right}
    eq_reduced = reduce_bool_equivalence(expr)

    cond do
      eq_reduced != expr ->
        {:reduced, eq_reduced}

      true ->
        split_reduced = reduce_split_disjunction(expr)

        if split_reduced != expr do
          {:reduced, split_reduced}
        else
          :none
        end
    end
  end

  defp remove_absorbed_terms(terms, :and) do
    set = MapSet.new(terms)

    Enum.reject(terms, fn
      {:or, x, y} -> MapSet.member?(set, x) or MapSet.member?(set, y)
      _ -> false
    end)
  end

  defp remove_absorbed_terms(terms, :or) do
    set = MapSet.new(terms)

    Enum.reject(terms, fn
      {:and, x, y} -> MapSet.member?(set, x) or MapSet.member?(set, y)
      _ -> false
    end)
  end

  defp reduce_bool_equivalence({:or, {:and, l, r}, {:and, {:not, l2}, {:not, r2}}})
       when l == l2 and r == r2 do
    cond do
      r == true -> l
      l == true -> r
      r == false -> {:not, l}
      l == false -> {:not, r}
      true -> {:or, {:and, l, r}, {:and, {:not, l2}, {:not, r2}}}
    end
  end

  defp reduce_bool_equivalence({:or, {:and, l, r}, {:and, {:not, r2}, {:not, l2}}})
       when l == l2 and r == r2 do
    cond do
      r == true -> l
      l == true -> r
      r == false -> {:not, l}
      l == false -> {:not, r}
      true -> {:or, {:and, l, r}, {:and, {:not, r2}, {:not, l2}}}
    end
  end

  defp reduce_bool_equivalence(c), do: c

  # (a AND b) OR (a AND NOT b) => a (and symmetric variants)
  defp reduce_split_disjunction({:or, left, right}) do
    case {and_terms(left), and_terms(right)} do
      {{:ok, {l1, l2}}, {:ok, {r1, r2}}} ->
        cond do
          l1 == r1 and constraint_complements?(l2, r2) -> l1
          l1 == r2 and constraint_complements?(l2, r1) -> l1
          l2 == r1 and constraint_complements?(l1, r2) -> l2
          l2 == r2 and constraint_complements?(l1, r1) -> l2
          true -> {:or, left, right}
        end

      _ ->
        {:or, left, right}
    end
  end

  defp reduce_split_disjunction(c), do: c

  defp and_terms({:and, x, y}), do: {:ok, {x, y}}
  defp and_terms(_), do: :error

  defp constraint_complements?(a, {:not, b}), do: a == b
  defp constraint_complements?({:not, a}, b), do: a == b
  defp constraint_complements?({:eq, a, b}, {:neq, a, b}), do: true
  defp constraint_complements?({:neq, a, b}, {:eq, a, b}), do: true
  defp constraint_complements?({:gt, a, b}, {:lte, a, b}), do: true
  defp constraint_complements?({:lte, a, b}, {:gt, a, b}), do: true
  defp constraint_complements?({:gte, a, b}, {:lt, a, b}), do: true
  defp constraint_complements?({:lt, a, b}, {:gte, a, b}), do: true
  defp constraint_complements?(_, _), do: false
end
