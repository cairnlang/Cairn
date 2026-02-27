defmodule Axiom.ExamplesSmokeTest do
  use ExUnit.Case, async: false

  @examples [
    "examples/hello_world.ax",
    "examples/imports/main.ax",
    "examples/prelude/result_flow.ax",
    "examples/practical/main.ax",
    "examples/practical/ledger.ax",
    "examples/practical/todo.ax"
  ]

  test "curated examples run end-to-end" do
    Enum.each(@examples, fn path ->
      assert {[], _env} = Axiom.eval_file(path)
    end)
  end
end
