defmodule Cairn.Solver.Z3 do
  @moduledoc """
  Manages the Z3 SMT solver process.

  Sends SMT-LIB v2 scripts to Z3 via a temporary file, parses sat/unsat responses,
  and extracts counterexample models when available.
  """

  @default_timeout 5_000

  @type result ::
          :unsat
          | {:sat, %{String.t() => integer()}}
          | {:error, String.t()}

  @doc """
  Check if Z3 is available on the system PATH.
  """
  @spec available?() :: boolean()
  def available? do
    System.find_executable("z3") != nil
  end

  @doc """
  Run an SMT-LIB v2 script through Z3 and return the result.

  Returns:
  - `:unsat` if the formula is unsatisfiable (proof holds)
  - `{:sat, model}` if satisfiable (counterexample found)
  - `{:error, reason}` on failure
  """
  @spec query(String.t(), keyword()) :: result()
  def query(script, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    unless available?() do
      {:error, "z3 not found on PATH. Install Z3 (https://github.com/Z3Prover/z3) to use PROVE."}
    else
      run_z3(script, timeout)
    end
  end

  defp run_z3(script, timeout) do
    tmp_path = System.tmp_dir!() |> Path.join("cairn_prove_#{:erlang.unique_integer([:positive])}.smt2")

    try do
      File.write!(tmp_path, script)

      {output, exit_code} =
        System.cmd("z3", ["-T:#{div(timeout, 1000)}", tmp_path],
          stderr_to_stdout: true
        )

      trimmed = String.trim(output)

      # Z3 may exit with code 1 when get-model follows unsat (no model available).
      # Parse the output first — if it starts with sat/unsat, that's our answer.
      cond do
        String.starts_with?(trimmed, "unsat") ->
          :unsat

        String.starts_with?(trimmed, "sat") ->
          lines = String.split(trimmed, "\n", trim: true)
          model = parse_model(Enum.join(tl(lines), "\n"))
          {:sat, model}

        String.starts_with?(trimmed, "unknown") ->
          {:error, "Z3 returned unknown (solver timeout or undecidable)"}

        exit_code != 0 ->
          {:error, "Z3 exited with code #{exit_code}: #{trimmed}"}

        true ->
          {:error, "unexpected Z3 output: #{trimmed}"}
      end
    rescue
      e ->
        {:error, "Z3 execution failed: #{Exception.message(e)}"}
    after
      File.rm(tmp_path)
    end
  end

  @doc """
  Parse a Z3 model output into a map of variable name → integer value.

  Z3 model format:
  ```
  (model
    (define-fun p0 () Int 1)
    (define-fun p1 () Int (- 5))
  )
  ```
  """
  @spec parse_model(String.t()) :: %{String.t() => integer()}
  def parse_model(model_str) do
    # Match both positive and negative integers
    # Positive: (define-fun p0 () Int 42)
    # Negative: (define-fun p0 () Int (- 42))
    positive_matches =
      Regex.scan(~r/define-fun\s+(\w+)\s+\(\)\s+Int\s+(\d+)/, model_str)
      |> Enum.map(fn [_, name, val] -> {name, String.to_integer(val)} end)

    negative_matches =
      Regex.scan(~r/define-fun\s+(\w+)\s+\(\)\s+Int\s+\(-\s*(\d+)\)/, model_str)
      |> Enum.map(fn [_, name, val] -> {name, -String.to_integer(val)} end)

    Map.new(positive_matches ++ negative_matches)
  end
end
