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

  @spec normalize_with_rewrites(term()) :: {term(), [map()]}
  def normalize_with_rewrites(term) do
    previous = Process.get(:axiom_pre_normalize_rewrites, :unset)
    Process.put(:axiom_pre_normalize_rewrites, [])
    normalized = normalize(term)
    rewrites = Process.get(:axiom_pre_normalize_rewrites, []) |> Enum.reverse()

    case previous do
      :unset -> Process.delete(:axiom_pre_normalize_rewrites)
      _ -> Process.put(:axiom_pre_normalize_rewrites, previous)
    end

    {normalized, rewrites}
  end

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
        canonicalized =
          terms
          |> Enum.reject(&(&1 == true))
          |> canonical_terms()

        simplified = merge_interval_terms(canonicalized)
        maybe_record_rewrite("and_merge_intervals", build_constraint(:and, canonicalized), simplified_to_constraint(simplified, :and))

        case simplified do
          :contradiction ->
            maybe_record_rewrite("and_contradiction", build_constraint(:and, canonicalized), false)
            false

          merged_terms ->
            after_implication = reduce_implication_terms(merged_terms)
            maybe_record_rewrite("and_reduce_implication", build_constraint(:and, merged_terms), build_constraint(:and, after_implication))
            after_consensus = reduce_consensus_terms(after_implication)
            maybe_record_rewrite("and_reduce_consensus", build_constraint(:and, after_implication), build_constraint(:and, after_consensus))
            after_absorption = remove_absorbed_terms(after_consensus, :and)
            maybe_record_rewrite("and_absorption", build_constraint(:and, after_consensus), build_constraint(:and, after_absorption))

            canonical =
              after_absorption
              |> flatten_terms(:and)
              |> canonical_terms()

            cond do
              has_complement_pair?(canonical) ->
                maybe_record_rewrite("and_complement_pair", build_constraint(:and, canonical), false)
                false

              pair_short_circuit?(canonical, :and) ->
                maybe_record_rewrite("and_pair_short_circuit", build_constraint(:and, canonical), false)
                false

              true ->
                build_constraint(:and, canonical)
            end
        end
    end
  end

  defp simplify_or_terms(terms) do
    cond do
      Enum.any?(terms, &(&1 == true)) ->
        true

      true ->
        canonicalized =
          terms
          |> Enum.reject(&(&1 == false))
          |> canonical_terms()

        after_pair = reduce_or_pair_terms(canonicalized)
        maybe_record_rewrite("or_pair_reduction", build_constraint(:or, canonicalized), build_constraint(:or, after_pair))
        after_absorption = remove_absorbed_terms(after_pair, :or)
        maybe_record_rewrite("or_absorption", build_constraint(:or, after_pair), build_constraint(:or, after_absorption))

        canonical =
          after_absorption
          |> flatten_terms(:or)
          |> canonical_terms()

        cond do
          has_complement_pair?(canonical) ->
            maybe_record_rewrite("or_complement_pair", build_constraint(:or, canonical), true)
            true

          pair_short_circuit?(canonical, :or) ->
            maybe_record_rewrite("or_pair_short_circuit", build_constraint(:or, canonical), true)
            true

          true ->
            build_constraint(:or, canonical)
        end
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

  defp maybe_record_rewrite(_rule, before_term, after_term) when before_term == after_term, do: :ok
  defp maybe_record_rewrite(_rule, :contradiction, :contradiction), do: :ok

  defp maybe_record_rewrite(rule, before_term, after_term) do
    case Process.get(:axiom_pre_normalize_rewrites, :disabled) do
      events when is_list(events) ->
        event = %{rule: rule, before: inspect(before_term), after: inspect(after_term)}
        Process.put(:axiom_pre_normalize_rewrites, [event | events])

      _ ->
        :ok
    end
  end

  defp simplified_to_constraint(:contradiction, _op), do: :contradiction
  defp simplified_to_constraint(terms, op), do: build_constraint(op, terms)

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

  defp merge_interval_terms(terms) do
    {comp_terms, other_terms} = Enum.split_with(terms, &match?({op, _, _} when op in [:eq, :neq, :gt, :gte, :lt, :lte], &1))

    grouped =
      Enum.reduce(comp_terms, %{}, fn term, acc ->
        case normalized_cmp(term) do
          {:ok, {_op, expr, _k}} ->
            Map.update(acc, expr, [term], fn current -> [term | current] end)

          :error ->
            acc
        end
      end)

    Enum.reduce_while(grouped, {:ok, other_terms}, fn {expr, expr_terms}, {:ok, acc_terms} ->
      case merge_expr_comparison_terms(expr, expr_terms) do
        :contradiction ->
          {:halt, :contradiction}

        merged_expr_terms ->
          {:cont, {:ok, merged_expr_terms ++ acc_terms}}
      end
    end)
    |> case do
      :contradiction -> :contradiction
      {:ok, merged} -> canonical_terms(merged)
    end
  end

  defp merge_expr_comparison_terms(expr, terms) do
    parsed =
      terms
      |> Enum.map(fn term ->
        {:ok, {op, _expr, k}} = normalized_cmp(term)
        {op, k}
      end)

    eq_values = parsed |> Enum.filter(fn {op, _k} -> op == :eq end) |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    neq_values = parsed |> Enum.filter(fn {op, _k} -> op == :neq end) |> Enum.map(&elem(&1, 1)) |> MapSet.new()
    lowers = parsed |> Enum.filter(fn {op, _k} -> op in [:gt, :gte] end)
    uppers = parsed |> Enum.filter(fn {op, _k} -> op in [:lt, :lte] end)

    cond do
      length(eq_values) > 1 ->
        :contradiction

      true ->
        eq_value = List.first(eq_values)
        lower = tightest_lower(lowers)
        upper = tightest_upper(uppers)

        cond do
          eq_value != nil and (not satisfies_lower?(eq_value, lower) or not satisfies_upper?(eq_value, upper)) ->
            :contradiction

          eq_value != nil and MapSet.member?(neq_values, eq_value) ->
            :contradiction

          eq_value != nil ->
            [{:eq, expr, {:const, eq_value}} | emit_neq_terms(expr, neq_values, eq_value)]

          interval_empty?(lower, upper) ->
            :contradiction

          lower != nil and upper != nil and interval_singleton?(lower, upper) ->
            v = elem(lower, 1)

            if MapSet.member?(neq_values, v) do
              :contradiction
            else
              [{:eq, expr, {:const, v}} | emit_neq_terms(expr, neq_values, v)]
            end

          true ->
            emit_bound_terms(expr, lower, upper) ++ emit_neq_terms(expr, neq_values, nil)
        end
    end
  end

  defp tightest_lower([]), do: nil

  defp tightest_lower(lowers) do
    Enum.reduce(lowers, nil, fn {op, k}, acc ->
      choose_tighter_lower(acc, {op, k})
    end)
  end

  defp tightest_upper([]), do: nil

  defp tightest_upper(uppers) do
    Enum.reduce(uppers, nil, fn {op, k}, acc ->
      choose_tighter_upper(acc, {op, k})
    end)
  end

  defp choose_tighter_lower(nil, candidate), do: candidate

  defp choose_tighter_lower({op1, k1}, {op2, k2}) do
    cond do
      k2 > k1 -> {op2, k2}
      k1 > k2 -> {op1, k1}
      true -> {if(op1 == :gt or op2 == :gt, do: :gt, else: :gte), k1}
    end
  end

  defp choose_tighter_upper(nil, candidate), do: candidate

  defp choose_tighter_upper({op1, k1}, {op2, k2}) do
    cond do
      k2 < k1 -> {op2, k2}
      k1 < k2 -> {op1, k1}
      true -> {if(op1 == :lt or op2 == :lt, do: :lt, else: :lte), k1}
    end
  end

  defp satisfies_lower?(_value, nil), do: true
  defp satisfies_lower?(value, {:gt, k}), do: value > k
  defp satisfies_lower?(value, {:gte, k}), do: value >= k

  defp satisfies_upper?(_value, nil), do: true
  defp satisfies_upper?(value, {:lt, k}), do: value < k
  defp satisfies_upper?(value, {:lte, k}), do: value <= k

  defp interval_empty?(nil, _upper), do: false
  defp interval_empty?(_lower, nil), do: false

  defp interval_empty?({lop, lk}, {uop, uk}) do
    cond do
      lk < uk -> false
      lk > uk -> true
      true -> not (lop == :gte and uop == :lte)
    end
  end

  defp interval_singleton?({:gte, k1}, {:lte, k2}), do: k1 == k2
  defp interval_singleton?(_, _), do: false

  defp emit_bound_terms(_expr, nil, nil), do: []

  defp emit_bound_terms(expr, lower, upper) do
    lower_term =
      case lower do
        nil -> []
        {op, k} -> [{op, expr, {:const, k}}]
      end

    upper_term =
      case upper do
        nil -> []
        {op, k} -> [{op, expr, {:const, k}}]
      end

    lower_term ++ upper_term
  end

  defp emit_neq_terms(expr, neq_values, skip_value) do
    neq_values
    |> MapSet.to_list()
    |> Enum.reject(fn v -> skip_value != nil and v == skip_value end)
    |> Enum.sort()
    |> Enum.map(fn v -> {:neq, expr, {:const, v}} end)
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

  # Consensus-style reduction (bounded, pairwise):
  # (A OR B) AND (A OR NOT B) => A
  defp reduce_consensus_terms(terms) do
    case find_consensus_pair(terms) do
      {:ok, reduced_terms} ->
        reduced_terms
        |> flatten_terms(:and)
        |> canonical_terms()
        |> reduce_consensus_terms()

      :none ->
        terms
    end
  end

  defp find_consensus_pair(terms) do
    indexed = Enum.with_index(terms)

    Enum.reduce_while(indexed, :none, fn {left, i}, _acc ->
      right_candidates = Enum.drop(indexed, i + 1)

      case Enum.find_value(right_candidates, fn {right, j} ->
             case reduce_consensus_pair(left, right) do
               {:reduced, reduced} ->
                 remaining =
                   indexed
                   |> Enum.reject(fn {_term, idx} -> idx == i or idx == j end)
                   |> Enum.map(fn {term, _idx} -> term end)

                 {:ok, [normalize(reduced) | remaining]}

               :none ->
                 nil
             end
           end) do
        nil -> {:cont, :none}
        {:ok, _} = found -> {:halt, found}
      end
    end)
  end

  defp reduce_consensus_pair(left, right) do
    case {or_terms(left), or_terms(right)} do
      {{:ok, {l1, l2}}, {:ok, {r1, r2}}} ->
        cond do
          l1 == r1 and constraint_complements?(l2, r2) -> {:reduced, l1}
          l1 == r2 and constraint_complements?(l2, r1) -> {:reduced, l1}
          l2 == r1 and constraint_complements?(l1, r2) -> {:reduced, l2}
          l2 == r2 and constraint_complements?(l1, r1) -> {:reduced, l2}
          true -> :none
        end

      _ ->
        :none
    end
  end

  defp or_terms({:or, x, y}), do: {:ok, {x, y}}
  defp or_terms(_), do: :error

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
                reduced = normalize(reduced)

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
    distributed = distribute_guarded_or(expr)
    factored = factor_common_and_term(expr)
    eq_reduced = reduce_bool_equivalence(expr)

    cond do
      distributed != expr ->
        {:reduced, distributed}

      factored != expr ->
        {:reduced, factored}

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

  # Guarded one-step distribution:
  # A OR (B AND C) => (A OR B) AND (A OR C)
  # only when A looks like a narrowing atom and expression size stays bounded.
  defp distribute_guarded_or({:or, a, {:and, b, c}}) do
    if likely_narrowing_atom?(a) and distributive_safe?(a, b, c) do
      {:and, {:or, a, b}, {:or, a, c}}
    else
      {:or, a, {:and, b, c}}
    end
  end

  defp distribute_guarded_or({:or, {:and, b, c}, a}) do
    if likely_narrowing_atom?(a) and distributive_safe?(a, b, c) do
      {:and, {:or, a, b}, {:or, a, c}}
    else
      {:or, {:and, b, c}, a}
    end
  end

  defp distribute_guarded_or(c), do: c

  defp likely_narrowing_atom?({op, _x, _y}) when op in [:eq, :neq, :gt, :gte, :lt, :lte], do: true
  defp likely_narrowing_atom?({:not, {op, _x, _y}}) when op in [:eq, :neq, :gt, :gte, :lt, :lte], do: true
  defp likely_narrowing_atom?(_), do: false

  defp distributive_safe?(a, b, c) do
    node_size(a) + node_size(b) + node_size(c) <= 30
  end

  defp node_size(term) when is_tuple(term) do
    term
    |> Tuple.to_list()
    |> Enum.reduce(1, fn v, acc -> acc + node_size(v) end)
  end

  defp node_size(term) when is_list(term) do
    Enum.reduce(term, 1, fn v, acc -> acc + node_size(v) end)
  end

  defp node_size(_), do: 1

  # (a AND b) OR (a AND c) => a AND (b OR c) (pairwise, bounded)
  defp factor_common_and_term({:or, left, right}) do
    case {and_terms(left), and_terms(right)} do
      {{:ok, {l1, l2}}, {:ok, {r1, r2}}} ->
        cond do
          l1 == r1 -> {:and, l1, {:or, l2, r2}}
          l1 == r2 -> {:and, l1, {:or, l2, r1}}
          l2 == r1 -> {:and, l2, {:or, l1, r2}}
          l2 == r2 -> {:and, l2, {:or, l1, r1}}
          true -> {:or, left, right}
        end

      _ ->
        {:or, left, right}
    end
  end

  defp factor_common_and_term(c), do: c

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
