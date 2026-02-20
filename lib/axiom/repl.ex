defmodule Axiom.REPL do
  @moduledoc """
  Interactive REPL for Axiom.

  Provides an `ax>` prompt for evaluating Axiom expressions.
  Function definitions persist within the session.
  """

  @doc """
  Starts the REPL loop.
  """
  def start do
    IO.puts("Axiom v0.0.1 REPL")
    IO.puts("Type 'quit' to exit.\n")
    loop([], %{})
  end

  defp loop(stack, env) do
    prompt =
      if stack == [] do
        "ax> "
      else
        "ax #{inspect_stack(stack)}> "
      end

    case IO.gets(prompt) do
      :eof ->
        IO.puts("\nBye!")

      input ->
        input = String.trim(to_string(input))

        cond do
          input in ["quit", "exit", ":q"] ->
            IO.puts("Bye!")

          input == "stack" ->
            IO.puts(inspect_stack(stack))
            loop(stack, env)

          input == "clear" ->
            loop([], env)

          input == "env" ->
            env
            |> Map.keys()
            |> Enum.each(fn name ->
              func = Map.get(env, name)
              types = Enum.map(func.param_types, &inspect/1) |> Enum.join(" ")
              IO.puts("  #{name} : #{types} -> #{inspect(func.return_type)}")
            end)

            loop(stack, env)

          input == "" ->
            loop(stack, env)

          true ->
            try do
              {new_stack, new_env} = Axiom.eval_with_env(input, env, stack)

              # For expressions, show the new stack state
              if new_stack != stack do
                IO.puts(inspect_stack(new_stack))
              end

              loop(new_stack, new_env)
            rescue
              e in Axiom.RuntimeError ->
                IO.puts("ERROR: #{e.message}")
                loop(stack, env)

              e in Axiom.ContractError ->
                IO.puts("CONTRACT VIOLATION: #{e.message}")
                IO.puts("  stack was: #{inspect(e.stack)}")
                loop(stack, env)
            end
        end
    end
  end

  defp inspect_stack([]), do: "[]"

  defp inspect_stack(stack) do
    items =
      stack
      |> Enum.map(&format_value/1)
      |> Enum.join(" ")

    "[#{items}]"
  end

  defp format_value(list) when is_list(list), do: inspect(list)
  defp format_value(val), do: inspect(val)
end
