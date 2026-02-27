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
          cond do
            has_complement_pair?(canonical) -> false
            pair_short_circuit?(canonical, :and) -> false
            true -> build_constraint(:and, canonical)
          end
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
          cond do
            has_complement_pair?(canonical) -> true
            pair_short_circuit?(canonical, :or) -> true
            true -> build_constraint(:or, canonical)
          end
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

  defp pair_short_circuit?(terms, mode) when mode in [:and, :or] do
    terms
    |> Enum.with_index()
    |> Enum.any?(fn {left, i} ->
      terms
      |> Enum.drop(i + 1)
      |> Enum.any?(fn right ->
        case pair_relation(left, right) do
          :contradiction -> mode == :and
          :tautology -> mode == :or
          :none -> false
        end
      end)
    end)
  end

  defp pair_relation(left, right) do
    with {:ok, cmp1} <- normalized_cmp(left),
         {:ok, cmp2} <- normalized_cmp(right),
         true <- comparable_cmp?(cmp1, cmp2) do
      cond do
        contradiction_cmp?(cmp1, cmp2) -> :contradiction
        tautology_cmp?(cmp1, cmp2) -> :tautology
        true -> :none
      end
    else
      _ -> :none
    end
  end

  defp normalized_cmp({op, expr, {:const, k}})
       when op in [:eq, :neq, :gt, :gte, :lt, :lte] and is_integer(k) do
    {:ok, {op, expr, k}}
  end

  defp normalized_cmp({op, {:const, k}, expr})
       when op in [:eq, :neq, :gt, :gte, :lt, :lte] and is_integer(k) do
    {:ok, {flip_op(op), expr, k}}
  end

  defp normalized_cmp(_), do: :error

  defp flip_op(:eq), do: :eq
  defp flip_op(:neq), do: :neq
  defp flip_op(:gt), do: :lt
  defp flip_op(:gte), do: :lte
  defp flip_op(:lt), do: :gt
  defp flip_op(:lte), do: :gte

  defp comparable_cmp?({_op1, expr, _k1}, {_op2, expr, _k2}), do: true
  defp comparable_cmp?(_, _), do: false

  defp contradiction_cmp?(cmp1, cmp2) do
    case {cmp_interval(cmp1), cmp_interval(cmp2)} do
      {{:ok, i1}, {:ok, i2}} -> interval_intersection_empty?(i1, i2)
      _ -> false
    end
  end

  defp tautology_cmp?(cmp1, cmp2) do
    with {:ok, n1} <- negate_cmp(cmp1),
         {:ok, n2} <- negate_cmp(cmp2) do
      contradiction_cmp?(n1, n2)
    else
      _ -> false
    end
  end

  defp negate_cmp({:eq, expr, k}), do: {:ok, {:neq, expr, k}}
  defp negate_cmp({:neq, expr, k}), do: {:ok, {:eq, expr, k}}
  defp negate_cmp({:gt, expr, k}), do: {:ok, {:lte, expr, k}}
  defp negate_cmp({:gte, expr, k}), do: {:ok, {:lt, expr, k}}
  defp negate_cmp({:lt, expr, k}), do: {:ok, {:gte, expr, k}}
  defp negate_cmp({:lte, expr, k}), do: {:ok, {:gt, expr, k}}

  defp cmp_interval({:gt, _expr, k}), do: {:ok, %{lb: k, lb_inc: false, ub: nil, ub_inc: true}}
  defp cmp_interval({:gte, _expr, k}), do: {:ok, %{lb: k, lb_inc: true, ub: nil, ub_inc: true}}
  defp cmp_interval({:lt, _expr, k}), do: {:ok, %{lb: nil, lb_inc: true, ub: k, ub_inc: false}}
  defp cmp_interval({:lte, _expr, k}), do: {:ok, %{lb: nil, lb_inc: true, ub: k, ub_inc: true}}
  defp cmp_interval({:eq, _expr, k}), do: {:ok, %{lb: k, lb_inc: true, ub: k, ub_inc: true}}
  defp cmp_interval({:neq, _expr, _k}), do: :unsupported

  defp interval_intersection_empty?(i1, i2) do
    lb = tighter_lower(i1, i2)
    ub = tighter_upper(i1, i2)

    cond do
      lb.value == nil or ub.value == nil ->
        false

      lb.value < ub.value ->
        false

      lb.value > ub.value ->
        true

      true ->
        not (lb.inclusive and ub.inclusive)
    end
  end

  defp tighter_lower(i1, i2) do
    pick_tighter_bound(i1.lb, i1.lb_inc, i2.lb, i2.lb_inc, :max)
  end

  defp tighter_upper(i1, i2) do
    pick_tighter_bound(i1.ub, i1.ub_inc, i2.ub, i2.ub_inc, :min)
  end

  defp pick_tighter_bound(nil, _inc1, v2, inc2, _mode), do: %{value: v2, inclusive: inc2}
  defp pick_tighter_bound(v1, inc1, nil, _inc2, _mode), do: %{value: v1, inclusive: inc1}

  defp pick_tighter_bound(v1, inc1, v2, inc2, :max) do
    cond do
      v1 > v2 -> %{value: v1, inclusive: inc1}
      v2 > v1 -> %{value: v2, inclusive: inc2}
      true -> %{value: v1, inclusive: inc1 and inc2}
    end
  end

  defp pick_tighter_bound(v1, inc1, v2, inc2, :min) do
    cond do
      v1 < v2 -> %{value: v1, inclusive: inc1}
      v2 < v1 -> %{value: v2, inclusive: inc2}
      true -> %{value: v1, inclusive: inc1 and inc2}
    end
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
