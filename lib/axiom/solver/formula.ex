defmodule Axiom.Solver.Formula do
  @moduledoc """
  Symbolic expression and constraint data structures for the PROVE solver.

  These represent the AST that gets converted to SMT-LIB v2.
  """

  # Symbolic integer expression
  @type expr ::
          {:var, String.t()}
          | {:const, integer()}
          | {:add, expr, expr}
          | {:sub, expr, expr}
          | {:mul, expr, expr}
          | {:div, expr, expr}
          | {:mod, expr, expr}
          | {:neg, expr}
          | {:ite, constraint, expr, expr}

  # Symbolic boolean (constraint formula)
  @type constraint ::
          {:gte, expr, expr}
          | {:gt, expr, expr}
          | {:lte, expr, expr}
          | {:lt, expr, expr}
          | {:eq, expr, expr}
          | {:neq, expr, expr}
          | {:and, constraint, constraint}
          | {:or, constraint, constraint}
          | {:not, constraint}
          | {:ite_bool, constraint, constraint, constraint}
          | true
          | false

  # Tagged stack value
  @type sym_val ::
          {:int_expr, expr}
          | {:bool_expr, constraint}
          | {:option_expr, expr, expr}
          | {:result_expr, expr, expr, String.t()}
          | {:opaque_expr, String.t()}
          | :unsupported

  # --- Helper constructors ---

  def var(name), do: {:var, name}
  def const(n), do: {:const, n}

  def add(a, b), do: {:add, a, b}
  def sub(a, b), do: {:sub, a, b}
  def mul(a, b), do: {:mul, a, b}
  def sdiv(a, b), do: {:div, a, b}
  def smod(a, b), do: {:mod, a, b}
  def neg(a), do: {:neg, a}

  def gte(a, b), do: {:gte, a, b}
  def gt(a, b), do: {:gt, a, b}
  def lte(a, b), do: {:lte, a, b}
  def lt(a, b), do: {:lt, a, b}
  def eq(a, b), do: {:eq, a, b}
  def neq(a, b), do: {:neq, a, b}

  def sand(a, b), do: {:and, a, b}
  def sor(a, b), do: {:or, a, b}
  def snot(a), do: {:not, a}

  def ite(cond, t, e), do: {:ite, cond, t, e}
  def ite_bool(cond, t, e), do: {:ite_bool, cond, t, e}

  def int_expr(e), do: {:int_expr, e}
  def bool_expr(c), do: {:bool_expr, c}
end
