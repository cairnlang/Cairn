defmodule Mix.Tasks.Cairn.Run do
  @moduledoc """
  Development wrapper around the standalone Cairn CLI.

  ## Usage

      mix cairn.run path/to/program.crn

  This delegates to `Cairn.CLI` in file mode so the Mix task and the standalone
  executable stay behaviorally aligned.
  """

  use Mix.Task

  @shortdoc "Run a Cairn (.crn) source file"

  @impl Mix.Task
  def run(args) do
    _ = Cairn.CLI.run(args, no_args: :usage, halt_on_error: true)
  end
end
