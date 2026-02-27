defmodule Axiom.Solver.Prove do
  @moduledoc """
  Orchestrates the PROVE pipeline: symbolic execution → proof obligation assembly →
  SMT-LIB generation → Z3 query → result formatting.
  """

  alias Axiom.Solver.{Symbolic, SmtLib, Z3}
  alias Axiom.Types.Function

  @type prove_result ::
          {:proven, String.t()}
          | {:disproven, String.t(), %{String.t() => integer()}}
          | {:unknown, String.t()}
          | {:error, String.t()}

  @doc """
  Prove that a function's POST condition holds for all inputs satisfying PRE.

  Steps:
  1. Build initial symbolic stack from param types
  2. Symbolically execute PRE → extract PRE constraint
  3. Symbolically execute body on initial stack
  4. Symbolically execute POST on result stack → extract POST constraint
  5. Assemble proof obligation: PRE ∧ ¬POST
  6. Generate SMT-LIB script and query Z3
  7. Return result
  """
  @spec prove(Function.t(), map()) :: prove_result()
  def prove(%Function{} = func, env \\ %{}) do
    with :ok <- check_z3_available(),
         {:ok, initial_stack, vars, base_constraint} <- Symbolic.build_initial_stack(func.param_types, env),
         {:ok, pre_constraint, body_stack} <- execute_pre(func, initial_stack, env),
         {:ok, result_stack} <- execute_body(func, body_stack, env),
         {:ok, post_constraint} <- execute_post(func, result_stack, env) do
      query_z3(vars, combine_constraints(base_constraint, pre_constraint), post_constraint, func)
    else
      {:unsupported, reason} -> {:unknown, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp check_z3_available do
    if Z3.available?(), do: :ok, else: {:error, z3_missing_message()}
  end

  defp z3_missing_message do
    "z3 not found on PATH. Install Z3 (https://github.com/Z3Prover/z3) to use PROVE."
  end

  # Execute PRE condition symbolically. If no PRE, use `true`.
  defp execute_pre(%Function{pre_condition: nil}, initial_stack, _env) do
    {:ok, true, initial_stack}
  end

  defp execute_pre(%Function{pre_condition: pre_tokens}, initial_stack, env) do
    case Symbolic.execute(pre_tokens, initial_stack, env) do
      {:ok, pre_stack} ->
        case Symbolic.extract_bool_constraint(pre_stack) do
          {:ok, constraint} -> {:ok, constraint, initial_stack}
          {:error, msg} -> {:error, "PRE: #{msg}"}
        end

      {:unsupported, reason} ->
        {:unsupported, reason}
    end
  end

  # Execute body symbolically
  defp execute_body(%Function{body: body}, stack, env) do
    case Symbolic.execute(body, stack, env) do
      {:ok, _} = result -> result
      {:unsupported, _} = result -> result
    end
  end

  # Execute POST condition symbolically. If no POST, use `true` (vacuously true).
  defp execute_post(%Function{post_condition: nil}, _result_stack, _env) do
    {:ok, true}
  end

  defp execute_post(%Function{post_condition: post_tokens}, result_stack, env) do
    case Symbolic.execute(post_tokens, result_stack, env) do
      {:ok, post_stack} ->
        case Symbolic.extract_bool_constraint(post_stack) do
          {:ok, constraint} -> {:ok, constraint}
          {:error, msg} -> {:error, "POST: #{msg}"}
        end

      {:unsupported, reason} ->
        {:unsupported, reason}
    end
  end

  # Generate SMT-LIB, query Z3, interpret result
  defp query_z3(vars, pre_constraint, post_constraint, func) do
    script = SmtLib.build_script(vars, pre_constraint, post_constraint)

    case Z3.query(script) do
      :unsat ->
        {:proven, "POST holds for all inputs satisfying PRE"}

      {:sat, model} ->
        {:disproven, format_counterexample(model, func), model}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Format a counterexample model into a human-readable string.

  Maps variable names (p0, p1, ...) back to parameter positions.
  """
  @spec format_counterexample(%{String.t() => integer()}, Function.t()) :: String.t()
  def format_counterexample(model, %Function{param_types: param_types}) do
    param_types
    |> Enum.with_index()
    |> Enum.map(fn {_type, i} ->
      var = "p#{i}"
      val = Map.get(model, var, "?")
      "#{var} = #{val}"
    end)
    |> Enum.join(", ")
  end

  defp combine_constraints(true, c), do: c
  defp combine_constraints(c, true), do: c
  defp combine_constraints(a, b), do: {:and, a, b}
end
