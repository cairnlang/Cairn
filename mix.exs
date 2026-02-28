defmodule Cairn.MixProject do
  use Mix.Project

  def project do
    [
      app: :cairn,
      version: "0.1.0",
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      preferred_cli_env: [
        "test.practical": :test
      ],
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:stream_data, "~> 0.5"}
    ]
  end

  defp aliases do
    [
      "test.practical": ["test test/practical/pipeline_test.exs"]
    ]
  end
end
