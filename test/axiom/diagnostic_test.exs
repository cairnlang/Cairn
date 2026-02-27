defmodule Axiom.DiagnosticTest do
  use ExUnit.Case, async: true

  alias Axiom.Checker.Error

  test "formats static diagnostics with location and details" do
    path = Path.join(System.tmp_dir!(), "axiom_diag_static.ax")
    File.write!(path, "1 \"x\" ADD\n")

    ex =
      Axiom.StaticError.exception([
        %Error{position: 2, message: "ADD expected int but got str"},
        %Error{position: 1, message: "extra detail"}
      ])

    diag = Axiom.Diagnostic.from_exception(ex, path)
    lines = Axiom.Diagnostic.format_text(diag)

    assert Enum.any?(lines, &String.contains?(&1, "ERROR kind=static"))
    assert Enum.any?(lines, &String.contains?(&1, "location:"))
    assert Enum.any?(lines, &String.contains?(&1, "snippet:"))
    assert Enum.any?(lines, &String.contains?(&1, "details:"))
  end

  test "formats runtime diagnostics as json" do
    path = Path.join(System.tmp_dir!(), "axiom_diag_runtime.ax")
    File.write!(path, "foo\n")

    ex = %Axiom.RuntimeError{message: "undefined 'foo' at word 1"}
    diag = Axiom.Diagnostic.from_exception(ex, path)
    json = Axiom.Diagnostic.format_json(diag)

    assert json =~ "\"kind\":\"runtime\""
    assert json =~ "\"word\":1"
    assert json =~ "\"location\":"
    assert json =~ "\"hint\":"
  end
end
