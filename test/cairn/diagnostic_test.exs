defmodule Cairn.DiagnosticTest do
  use ExUnit.Case, async: true

  alias Cairn.Checker.Error

  test "formats static diagnostics with location and details" do
    path = Path.join(System.tmp_dir!(), "cairn_diag_static.crn")
    File.write!(path, "1 \"x\" ADD\n")

    ex =
      Cairn.StaticError.exception([
        %Error{position: 2, message: "ADD expected int but got str"},
        %Error{position: 1, message: "extra detail"}
      ])

    diag = Cairn.Diagnostic.from_exception(ex, path)
    lines = Cairn.Diagnostic.format_text(diag)

    assert Enum.any?(lines, &String.contains?(&1, "ERROR kind=static"))
    assert Enum.any?(lines, &String.contains?(&1, "location:"))
    assert Enum.any?(lines, &String.contains?(&1, "snippet:"))
    assert Enum.any?(lines, &String.contains?(&1, "details:"))
  end

  test "formats runtime diagnostics as json" do
    path = Path.join(System.tmp_dir!(), "cairn_diag_runtime.crn")
    File.write!(path, "foo\n")

    ex = %Cairn.RuntimeError{message: "undefined 'foo' at word 1"}
    diag = Cairn.Diagnostic.from_exception(ex, path)
    json = Cairn.Diagnostic.format_json(diag)

    assert json =~ "\"kind\":\"runtime\""
    assert json =~ "\"word\":1"
    assert json =~ "\"location\":"
    assert json =~ "\"hint\":"
  end
end
