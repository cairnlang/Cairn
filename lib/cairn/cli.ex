defmodule Cairn.CLI do
  @moduledoc """
  Shared CLI entrypoint for the standalone `cairn` executable and the Mix task.
  """

  @prelude_modules [
    {"lib/prelude/result.crn", ["result_is_ok", "result_is_err", "result_unwrap_or"]},
    {"lib/prelude/str.crn", ["lines_nonempty", "csv_ints"]},
    {"lib/prelude/config.crn", ["env_data_lines", "env_map", "env_keys", "env_fetch", "map_get_or"]},
    {"lib/prelude/ini.crn", ["ini_data_lines", "ini_map", "ini_sections", "ini_fetch"]},
    {"lib/prelude/web.crn", ["http_html_ok", "http_text_ok", "http_text_not_found", "http_text_method_not_allowed", "http_html_file_ok", "html_escape", "http_add_header", "route_html_file", "route_get_html_file", "route_text_ok", "route_get_text", "route_or", "route_finish", "route_finish_get"]},
    {"lib/prelude.crn", ["to_int_or", "to_float_or", "read_file_or", "ask_or"]}
  ]

  @example_groups [
    {"basics",
     [
       "examples/hello_world.crn",
       "examples/generics.crn",
       "examples/collatz.crn",
       "examples/recur.crn",
       "examples/bank.crn",
       "examples/collections.crn",
       "examples/math.crn",
       "examples/strings.crn",
       "examples/interop.crn"
     ]},
    {"practical",
     [
       "examples/practical/all_practical.crn",
       "examples/practical/main.crn",
       "examples/practical/ledger.crn",
       "examples/practical/todo.crn",
       "examples/practical/ledger_cli.crn",
       "examples/practical/expenses.crn",
       "examples/practical/cashflow.crn",
       "examples/practical/cashflow_alerts.crn",
       "examples/practical/mini_grep.crn",
       "examples/practical/mini_grep_verify.crn",
       "examples/practical/mini_env.crn",
       "examples/practical/mini_ini.crn",
       "examples/imports/main.crn",
       "examples/json/demo.crn"
     ]},
    {"concurrency",
     [
       "examples/concurrency/ping_pong_types.crn",
       "examples/concurrency/protocol_ping_pong.crn",
       "examples/concurrency/traffic_light_types.crn",
       "examples/concurrency/traffic_light.crn",
       "examples/concurrency/ping_once.crn",
       "examples/concurrency/self_boot.crn",
       "examples/concurrency/two_pings.crn",
       "examples/concurrency/counter.crn",
       "examples/concurrency/notifier.crn",
       "examples/concurrency/restart_once.crn",
       "examples/concurrency/supervisor_worker.crn",
       "examples/concurrency/guess_binary.crn"
     ]},
    {"ambitious",
     [
       "examples/ambitious/orchestrator.crn"
     ]},
    {"policy",
     [
       "examples/policy/approval/main.crn",
       "examples/policy/approval/verify.crn"
     ]},
    {"web",
     [
       "examples/web/hello_static.crn",
       "examples/web/todo_app.crn",
       "examples/web/afford_app.crn",
       "examples/web/afford_verify.crn"
     ]},
    {"prelude",
     [
       "examples/prelude/result_flow.crn",
       "examples/prelude/csv_parse.crn",
       "examples/prelude/io_safe.crn",
       "examples/prelude/env_parse.crn",
       "examples/prelude/ini_parse.crn",
       "examples/prelude/web_helpers.crn"
     ]},
    {"diagnostics",
     [
       "examples/diagnostics/static_type.crn",
       "examples/diagnostics/runtime_div_zero.crn",
       "examples/diagnostics/contract_fail.crn"
     ]},
    {"prove",
     [
       "examples/prove/all_proven.crn",
       "examples/prove/proven_option.crn",
       "examples/prove/proven_shape_trace.crn"
     ]}
  ]

  @type run_opt ::
          {:no_args, :repl | :usage}
          | {:halt_on_error, boolean()}
          | {:repl, (() -> any())}

  @spec main([String.t()]) :: :ok | :error
  def main(args) do
    run(args, no_args: :repl, halt_on_error: true)
  end

  @spec run([String.t()], [run_opt()]) :: :ok | :error
  def run(args, opts \\ []) do
    no_args = Keyword.get(opts, :no_args, :repl)
    halt_on_error = Keyword.get(opts, :halt_on_error, false)
    repl = Keyword.get(opts, :repl, &Cairn.REPL.start/0)

    {parsed_opts, rest, invalid} =
      OptionParser.parse_head(args,
        strict: [
          help: :boolean,
          test: :string,
          show_prelude: :boolean,
          verbose: :boolean,
          json_errors: :boolean,
          examples: :boolean
        ]
      )

    cond do
      invalid != [] ->
        IO.puts(:stderr, "Invalid option(s): #{format_invalid_options(invalid)}")
        print_help()
        :error

      parsed_opts[:help] ->
        print_help()
        :ok

      parsed_opts[:examples] ->
        print_examples()
        :ok

      parsed_opts[:test] && rest != [] ->
        IO.puts(:stderr, "Do not combine --test <file.crn> with a positional script path.")
        :error

      parsed_opts[:test] ->
        maybe_print_prelude_banner(parsed_opts)
        run_test_file(parsed_opts[:test], halt_on_error)

      rest == [] and no_args == :repl ->
        repl.()
        :ok

      rest == [] and no_args == :usage ->
        IO.puts(:stderr, "Usage: mix cairn.run <file.crn> [args...]")
        IO.puts(:stderr, "Run `mix cairn.run --help` for options, or `mix cairn.run --examples` for runnable samples.")
        :error

      true ->
        [path | argv] = rest
        Process.put(:cairn_argv, argv)
        maybe_print_prelude_banner(parsed_opts)
        run_file(path, parsed_opts, halt_on_error)
    end
  end

  defp run_file(path, opts, halt_on_error) do
    started_at_ms = System.monotonic_time(:millisecond)

    try do
      {stack, _env} = Cairn.eval_file(path)

      stack
      |> Enum.reverse()
      |> Enum.each(fn val -> IO.puts(format_value(val)) end)

      elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
      IO.puts(:stderr, "RUN SUMMARY: status=ok values=#{length(stack)} elapsed_ms=#{elapsed_ms}")
      :ok
    rescue
      e in Cairn.StaticError ->
        emit_diagnostic(e, path, opts)
        halt_or_error(:static, started_at_ms, halt_on_error)

      e in Cairn.RuntimeError ->
        emit_diagnostic(e, path, opts)
        halt_or_error(:runtime, started_at_ms, halt_on_error)

      e in Cairn.ContractError ->
        emit_diagnostic(e, path, opts)
        halt_or_error(:contract, started_at_ms, halt_on_error)
    end
  end

  defp run_test_file(path, halt_on_error) do
    started_at_ms = System.monotonic_time(:millisecond)

    try do
      {_stack, env} = Cairn.eval_file(path, %{"__test_mode__" => true})
      results = Map.get(env, "__test_results__", [])
      {passed, failed} = Enum.split_with(results, &(&1.status == :ok))

      Enum.each(passed, fn %{name: name} ->
        IO.puts("PASS #{name}")
      end)

      Enum.each(failed, fn %{name: name, message: message} ->
        IO.puts("FAIL #{name}")
        IO.puts("  #{message}")
      end)

      elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
      IO.puts(:stderr, "TEST SUMMARY: total=#{length(results)} passed=#{length(passed)} failed=#{length(failed)} elapsed_ms=#{elapsed_ms}")

      if failed == [] do
        :ok
      else
        if halt_on_error do
          System.halt(1)
        else
          :error
        end
      end
    rescue
      e in Cairn.StaticError ->
        Enum.each(Cairn.Diagnostic.format_text(Cairn.Diagnostic.from_exception(e, path)), &IO.puts(:stderr, &1))
        maybe_halt_test_error(started_at_ms, halt_on_error)

      e in Cairn.RuntimeError ->
        Enum.each(Cairn.Diagnostic.format_text(Cairn.Diagnostic.from_exception(e, path)), &IO.puts(:stderr, &1))
        maybe_halt_test_error(started_at_ms, halt_on_error)

      e in Cairn.ContractError ->
        Enum.each(Cairn.Diagnostic.format_text(Cairn.Diagnostic.from_exception(e, path)), &IO.puts(:stderr, &1))
        maybe_halt_test_error(started_at_ms, halt_on_error)
    end
  end

  defp maybe_halt_test_error(started_at_ms, halt_on_error) do
    elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
    IO.puts(:stderr, "TEST SUMMARY: status=error elapsed_ms=#{elapsed_ms}")

    if halt_on_error do
      System.halt(1)
    else
      :error
    end
  end

  defp halt_or_error(kind, started_at_ms, halt_on_error) do
    elapsed_ms = System.monotonic_time(:millisecond) - started_at_ms
    IO.puts(:stderr, "RUN SUMMARY: status=error kind=#{kind} elapsed_ms=#{elapsed_ms}")

    if halt_on_error do
      System.halt(1)
    else
      :error
    end
  end

  defp format_value(list) when is_list(list), do: inspect(list)
  defp format_value(true), do: "TRUE"
  defp format_value(false), do: "FALSE"
  defp format_value(val) when is_binary(val), do: val
  defp format_value(val) when is_number(val), do: to_string(val)
  defp format_value(val) when is_atom(val), do: to_string(val)
  defp format_value(val), do: inspect(val)

  defp maybe_print_prelude_banner(opts) do
    if opts[:show_prelude] || opts[:verbose] do
      if System.get_env("CAIRN_NO_PRELUDE") in ["1", "true", "TRUE"] do
        IO.puts(:stderr, "PRELUDE: disabled (CAIRN_NO_PRELUDE=1)")
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
      cairn [options]
      cairn [options] <file.crn> [args...]

    Modes:
      No file given     Start the REPL
      File given        Run the file with ARGV bound to remaining args

    Options:
      --help            Show this help text
      --test <file.crn> Run Cairn-native TEST blocks in a single file
      --examples        Show categorized runnable example files
      --show-prelude    Print loaded prelude modules/functions to stderr before running
      --verbose         Alias for --show-prelude
      --json-errors     Emit structured JSON diagnostics for failures

    Environment:
      CAIRN_NO_PRELUDE=1               Disable auto-loading lib/prelude.crn in file mode
      CAIRN_SKIP_ASSURANCE=1           Skip VERIFY and PROVE directives during evaluation
      CAIRN_PROVE_TRACE=summary|verbose|json
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
    diag = Cairn.Diagnostic.from_exception(error, path)

    if opts[:json_errors] do
      IO.puts(:stderr, Cairn.Diagnostic.format_json(diag))
    else
      Enum.each(Cairn.Diagnostic.format_text(diag), &IO.puts(:stderr, &1))
    end
  end
end
