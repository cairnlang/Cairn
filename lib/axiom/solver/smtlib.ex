defmodule Axiom.Solver.SmtLib do
  @moduledoc """
  Converts formula ASTs to SMT-LIB v2 strings.

  Handles recursive AST → string conversion, variable declaration collection,
  and full script assembly for Z3.
  """

  alias Axiom.Solver.Formula

  @doc """
  Build a complete SMT-LIB v2 script for checking `PRE ∧ ¬POST` unsatisfiability.

  Takes a list of variable names, the PRE constraint, and the POST constraint.
  Returns a string ready to send to Z3.
  """
  @spec build_script([String.t()], Formula.constraint(), Formula.constraint()) :: String.t()
  def build_script(vars, pre_constraint, post_constraint) do
    declarations = Enum.map(vars, &"(declare-const #{&1} Int)")
    pre_assertion = "(assert #{emit_constraint(pre_constraint)})"
    post_assertion = "(assert (not #{emit_constraint(post_constraint)}))"

    lines =
      ["(set-logic QF_NIA)"] ++
        declarations ++
        [pre_assertion, post_assertion, "(check-sat)", "(get-model)"]

    Enum.join(lines, "\n") <> "\n"
  end

  @doc """
  Emit a constraint (boolean formula) as an SMT-LIB v2 string.
  """
  @spec emit_constraint(Formula.constraint()) :: String.t()
  def emit_constraint(true), do: "true"
  def emit_constraint(false), do: "false"
  def emit_constraint({:gte, a, b}), do: "(>= #{emit_expr(a)} #{emit_expr(b)})"
  def emit_constraint({:gt, a, b}), do: "(> #{emit_expr(a)} #{emit_expr(b)})"
  def emit_constraint({:lte, a, b}), do: "(<= #{emit_expr(a)} #{emit_expr(b)})"
  def emit_constraint({:lt, a, b}), do: "(< #{emit_expr(a)} #{emit_expr(b)})"
  def emit_constraint({:eq, a, b}), do: "(= #{emit_expr(a)} #{emit_expr(b)})"
  def emit_constraint({:neq, a, b}), do: "(not (= #{emit_expr(a)} #{emit_expr(b)}))"
  def emit_constraint({:and, a, b}), do: "(and #{emit_constraint(a)} #{emit_constraint(b)})"
  def emit_constraint({:or, a, b}), do: "(or #{emit_constraint(a)} #{emit_constraint(b)})"
  def emit_constraint({:not, a}), do: "(not #{emit_constraint(a)})"
  def emit_constraint({:ite_bool, cond, t, e}), do: "(ite #{emit_constraint(cond)} #{emit_constraint(t)} #{emit_constraint(e)})"

  @doc """
  Emit an integer expression as an SMT-LIB v2 string.
  """
  @spec emit_expr(Formula.expr()) :: String.t()
  def emit_expr({:var, name}), do: name
  def emit_expr({:const, n}) when n >= 0, do: Integer.to_string(n)
  def emit_expr({:const, n}), do: "(- #{Integer.to_string(abs(n))})"
  def emit_expr({:add, a, b}), do: "(+ #{emit_expr(a)} #{emit_expr(b)})"
  def emit_expr({:sub, a, b}), do: "(- #{emit_expr(a)} #{emit_expr(b)})"
  def emit_expr({:mul, a, b}), do: "(* #{emit_expr(a)} #{emit_expr(b)})"
  def emit_expr({:div, a, b}), do: "(div #{emit_expr(a)} #{emit_expr(b)})"
  def emit_expr({:mod, a, b}), do: "(mod #{emit_expr(a)} #{emit_expr(b)})"
  def emit_expr({:neg, a}), do: "(- #{emit_expr(a)})"
  def emit_expr({:ite, cond, t, e}), do: "(ite #{emit_constraint(cond)} #{emit_expr(t)} #{emit_expr(e)})"

  @doc """
  Collect all variable names referenced in a constraint.
  """
  @spec collect_vars(Formula.constraint()) :: MapSet.t(String.t())
  def collect_vars(constraint) do
    do_collect_constraint_vars(constraint, MapSet.new())
  end

  defp do_collect_constraint_vars(true, acc), do: acc
  defp do_collect_constraint_vars(false, acc), do: acc

  defp do_collect_constraint_vars({op, a, b}, acc)
       when op in [:and, :or] do
    acc = do_collect_constraint_vars(a, acc)
    do_collect_constraint_vars(b, acc)
  end

  defp do_collect_constraint_vars({:not, a}, acc) do
    do_collect_constraint_vars(a, acc)
  end

  defp do_collect_constraint_vars({:ite_bool, cond, t, e}, acc) do
    acc = do_collect_constraint_vars(cond, acc)
    acc = do_collect_constraint_vars(t, acc)
    do_collect_constraint_vars(e, acc)
  end

  defp do_collect_constraint_vars({_cmp, a, b}, acc) do
    acc = do_collect_expr_vars(a, acc)
    do_collect_expr_vars(b, acc)
  end

  defp do_collect_expr_vars({:var, name}, acc), do: MapSet.put(acc, name)
  defp do_collect_expr_vars({:const, _}, acc), do: acc
  defp do_collect_expr_vars({:neg, a}, acc), do: do_collect_expr_vars(a, acc)

  defp do_collect_expr_vars({:ite, cond, t, e}, acc) do
    acc = do_collect_constraint_vars(cond, acc)
    acc = do_collect_expr_vars(t, acc)
    do_collect_expr_vars(e, acc)
  end

  defp do_collect_expr_vars({_op, a, b}, acc) do
    acc = do_collect_expr_vars(a, acc)
    do_collect_expr_vars(b, acc)
  end
end
