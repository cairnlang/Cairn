defmodule Cairn.EffectsStyleTest do
  use ExUnit.Case, async: true

  @scoped_dirs [
    "lib/prelude",
    "examples/practical/lib",
    "examples/web/lib"
  ]

  test "shared library surface uses explicit EFFECT on every DEF" do
    issues =
      @scoped_dirs
      |> scoped_files()
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _line_no} ->
          String.starts_with?(line, "DEF ") and not String.contains?(line, " EFFECT ")
        end)
        |> Enum.map(fn {_line, line_no} -> "#{file}:#{line_no}" end)
      end)

    assert issues == [],
           "missing explicit EFFECT on DEF lines:\n" <> Enum.join(issues, "\n")
  end

  test "shared library surface avoids bare result return signatures" do
    issues =
      @scoped_dirs
      |> scoped_files()
      |> Enum.flat_map(fn file ->
        file
        |> File.read!()
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _line_no} ->
          String.starts_with?(line, "DEF ") and Regex.match?(~r/->\s*result(\s|$)/, line)
        end)
        |> Enum.map(fn {_line, line_no} -> "#{file}:#{line_no}" end)
      end)

    assert issues == [],
           "bare result signature found; use result[T E]:\n" <> Enum.join(issues, "\n")
  end

  defp scoped_files(dirs) do
    dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.crn")))
    |> Enum.sort()
  end
end
