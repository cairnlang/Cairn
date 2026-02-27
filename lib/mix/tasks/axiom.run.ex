defmodule Mix.Tasks.Axiom.Run do
  @moduledoc """
  Runs an Axiom (.ax) source file.

  ## Usage

      mix axiom.run path/to/program.ax

  The file is read, parsed, and evaluated. The final stack is printed to stdout.
  """

  use Mix.Task

  @shortdoc "Run an Axiom (.ax) source file"

  @prelude_modules [
    {"lib/prelude/result.ax", ["result_is_ok", "result_is_err", "result_unwrap_or"]},
    {"lib/prelude/str.ax", ["lines_nonempty", "csv_ints"]},
    {"lib/prelude.ax", ["to_int_or", "to_float_or", "read_file_or", "ask_or"]}
  ]
  @example_groups [
    {"basics", ["examples/hello_world.ax", "examples/collatz.ax", "examples/recur.ax", "examples/bank.ax"]},
    {"practical", ["examples/practical/all_practical.ax", "examples/practical/main.ax", "examples/practical/ledger.ax", "examples/practical/todo.ax", "examples/practical/ledger_cli.ax", "examples/practical/expenses.ax", "examples/practical/cashflow.ax", "examples/practical/cashflow_alerts.ax", "examples/imports/main.ax", "examples/json/demo.ax"]},
    {"concurrency", ["examples/concurrency/ping_pong_types.ax", "examples/concurrency/traffic_light_types.ax", "examples/concurrency/traffic_light.ax", "examples/concurrency/ping_once.ax", "examples/concurrency/self_boot.ax", "examples/concurrency/two_pings.ax", "examples/concurrency/counter.ax", "examples/concurrency/notifier.ax", "examples/concurrency/restart_once.ax", "examples/concurrency/supervisor_worker.ax"]},
    {"prelude", ["examples/prelude/result_flow.ax", "examples/prelude/csv_parse.ax", "examples/prelude/io_safe.ax"]},
    {"diagnostics", ["examples/diagnostics/static_type.ax", "examples/diagnostics/runtime_div_zero.ax", "examples/diagnostics/contract_fail.ax"]},
    {"prove", ["examples/prove/all_proven.ax", "examples/prove/proven_option.ax", "examples/prove/proven_shape_trace.ax"]}
  ]

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} =
      OptionParser.parse(args,
        strict: [
          help: :boolean,
          show_prelude: :boolean,
          verbose: :boolean,
          json_errors: :boolean,
          examples: :boolean
        ]
      )

    cond do
      invalid != [] ->
        Mix.shell().error("Invalid option(s): #{format_invalid_options(invalid)}")
        print_help()

      opts[:help] ->
        print_help()

      opts[:examples] ->
        print_examples()

      true ->
        case rest do
          [path | argv] ->
            Process.put(:axiom_argv, argv)
            maybe_print_prelude_banner(opts)
            run_file(path, opts)

          [] ->
            Mix.shell().error("Usage: mix axiom.run <file.ax> [args...]")
            Mix.shell().error("Run `mix axiom.run --help` for options, or `mix axiom.run --examples` for runnable samples.")
        end
    end
  end

  defp run_file(path, opts) do
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
        emit_diagnostic(e, path, opts)
        elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
        IO.puts(:stderr, "RUN SUMMARY: status=error kind=static elapsed_ms=#{elapsed_ms}")
        System.halt(1)

      e in Axiom.RuntimeError ->
        emit_diagnostic(e, path, opts)
        elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
        IO.puts(:stderr, "RUN SUMMARY: status=error kind=runtime elapsed_ms=#{elapsed_ms}")
        System.halt(1)

      e in Axiom.ContractError ->
        emit_diagnostic(e, path, opts)
        elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
        IO.puts(:stderr, "RUN SUMMARY: status=error kind=contract elapsed_ms=#{elapsed_ms}")
        System.halt(1)
    end
  end

  defp format_value(list) when is_list(list), do: inspect(list)
  defp format_value(true), do: "T"
  defp format_value(false), do: "F"
  defp format_value(val) when is_binary(val), do: val
  defp format_value(val) when is_number(val), do: to_string(val)
  defp format_value(val) when is_atom(val), do: to_string(val)
  defp format_value(val), do: inspect(val)

  defp maybe_print_prelude_banner(opts) do
    if opts[:show_prelude] || opts[:verbose] do
      if System.get_env("AXIOM_NO_PRELUDE") in ["1", "true", "TRUE"] do
        IO.puts(:stderr, "PRELUDE: disabled (AXIOM_NO_PRELUDE=1)")
      else
        IO.puts(:stderr, "PRELUDE: auto-load enabled")

        Enum.each(@prelude_modules, fn {file, functions} ->
          IO.puts(:stderr, "  #{file}: #{Enum.join(functions, ", ")}")
        end)
      end
    end
  end

  defp format_invalid_options(invalid) do
    invalid
    |> Enum.map(fn {key, _value} -> "--#{key}" end)
    |> Enum.join(", ")
  end

  defp print_help do
    IO.puts("""
    Usage:
      mix axiom.run [options] <file.ax> [args...]

    Options:
      --help            Show this help text
      --examples        Show categorized runnable example files
      --show-prelude    Print loaded prelude modules/functions to stderr before running
      --verbose         Alias for --show-prelude
      --json-errors     Emit structured JSON diagnostics for failures

    Environment:
      AXIOM_NO_PRELUDE=1               Disable auto-loading lib/prelude.ax in file mode
      AXIOM_PROVE_TRACE=summary|verbose|json
                                      Enable PROVE MATCH trace diagnostics (stderr)
    """)
  end

  defp print_examples do
    IO.puts("Examples:")

    Enum.each(@example_groups, fn {group, files} ->
      IO.puts("  #{group}:")
      Enum.each(files, &IO.puts("    #{&1}"))
    end)
  end

  defp emit_diagnostic(error, path, opts) do
    diag = Axiom.Diagnostic.from_exception(error, path)

    if opts[:json_errors] do
      IO.puts(:stderr, Axiom.Diagnostic.format_json(diag))
    else
      Enum.each(Axiom.Diagnostic.format_text(diag), &IO.puts(:stderr, &1))
    end
  end
end
