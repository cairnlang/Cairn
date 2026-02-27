defmodule Mix.Tasks.Axiom.Run do
  @moduledoc """
  Runs an Axiom (.ax) source file.

  ## Usage

      mix axiom.run path/to/program.ax

  The file is read, parsed, and evaluated. The final stack is printed to stdout.
  """

  use Mix.Task

  @shortdoc "Run an Axiom (.ax) source file"

  @impl Mix.Task
  def run(args) do
    case args do
      [path | argv] ->
        Process.put(:axiom_argv, argv)
        run_file(path)

      [] ->
        Mix.shell().error("Usage: mix axiom.run <file.ax> [args...]")
    end
  end

  defp run_file(path) do
    started_at_ms = System.monotonic_time(:millisecond)

    try do
      {stack, _env} = Axiom.eval_file(path)

      stack
      |> Enum.reverse()
      |> Enum.each(fn val -> IO.puts(format_value(val)) end)

      elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
      IO.puts(:stderr, "RUN SUMMARY: status=ok values=#{length(stack)} elapsed_ms=#{elapsed_ms}")
    rescue
      e in Axiom.StaticError ->
        Mix.shell().error("Static type error: #{e.message}")
        elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
        IO.puts(:stderr, "RUN SUMMARY: status=error kind=static elapsed_ms=#{elapsed_ms}")
        System.halt(1)

      e in Axiom.RuntimeError ->
        Mix.shell().error("Runtime error: #{e.message}")
        elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
        IO.puts(:stderr, "RUN SUMMARY: status=error kind=runtime elapsed_ms=#{elapsed_ms}")
        System.halt(1)

      e in Axiom.ContractError ->
        Mix.shell().error("Contract violation: #{e.message}")
        Mix.shell().error("  stack: #{inspect(e.stack)}")
        elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
        IO.puts(:stderr, "RUN SUMMARY: status=error kind=contract elapsed_ms=#{elapsed_ms}")
        System.halt(1)
    end
  end

  defp format_value(list) when is_list(list), do: inspect(list)
  defp format_value(true), do: "T"
  defp format_value(false), do: "F"
  defp format_value(val), do: to_string(val)
end
