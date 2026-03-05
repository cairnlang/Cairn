defmodule Cairn.IR.ExportTest do
  use ExUnit.Case, async: false

  setup do
    previous = System.get_env("CAIRN_NO_PRELUDE")
    System.put_env("CAIRN_NO_PRELUDE", "1")

    on_exit(fn ->
      if previous do
        System.put_env("CAIRN_NO_PRELUDE", previous)
      else
        System.delete_env("CAIRN_NO_PRELUDE")
      end
    end)

    :ok
  end

  test "exports deterministic IR JSON for parsed file items" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "cairn_ir_export_det.crn")

    File.write!(path, """
    DEF add1 : int -> int EFFECT pure
      1 ADD
    END

    42 add1
    """)

    {:ok, items} = Cairn.load_file_items(path)
    {:ok, ir1} = Cairn.IR.Export.from_items(items, source: path)
    {:ok, ir2} = Cairn.IR.Export.from_items(items, source: path)

    assert ir1.version == "cairn-ir-json-v1"
    assert is_list(ir1.functions)
    assert Enum.any?(ir1.functions, &(&1.name == "add1"))
    assert Cairn.IR.Export.encode_json(ir1) == Cairn.IR.Export.encode_json(ir2)
  end

  test "supports single-function filtering and reports unknown names" do
    dir = System.tmp_dir!()
    path = Path.join(dir, "cairn_ir_export_filter.crn")

    File.write!(path, """
    DEF left : int -> int EFFECT pure
      1 ADD
    END

    DEF right : int -> int EFFECT pure
      2 ADD
    END
    """)

    {:ok, items} = Cairn.load_file_items(path)

    {:ok, filtered} = Cairn.IR.Export.from_items(items, source: path, fn: "right")
    assert Enum.map(filtered.functions, & &1.name) == ["right"]

    assert {:error, msg} = Cairn.IR.Export.from_items(items, source: path, fn: "missing")
    assert msg =~ "unknown function 'missing'"
    assert msg =~ "left"
    assert msg =~ "right"
  end
end
