defmodule Cairn.TestHarnessTest do
  use ExUnit.Case, async: false

  test "lexer tokenizes TEST and assertion operators" do
    assert {:ok,
            [
              {:test_kw, "TEST", 0},
              {:str_lit, "example", 1},
              {:int_lit, 1, 2},
              {:int_lit, 1, 3},
              {:op, :assert_eq, 4},
              {:fn_end, "END", 5}
            ]} =
             Cairn.Lexer.tokenize(~s(TEST "example" 1 1 ASSERT_EQ END))
  end

  test "parser produces test item" do
    {:ok, tokens} = Cairn.Lexer.tokenize(~s(TEST "example" 1 1 ASSERT_EQ END))
    {:ok, [item]} = Cairn.Parser.parse(tokens)
    assert {:test, "example", _body} = item
  end

  test "TEST blocks are skipped outside explicit test mode" do
    source = ~s(TEST "skipped" 1 2 ASSERT_EQ END 3)
    assert {[3], env} = Cairn.eval_with_env(source)
    assert Map.get(env, "__test_results__", []) == []
  end

  test "TEST blocks run and report in explicit test mode" do
    assert {[], env} = Cairn.eval_file("examples/web/afford_test.crn", %{"__test_mode__" => true})

    results = Map.get(env, "__test_results__", [])
    assert length(results) == 6
    assert Enum.all?(results, &(&1.status == :ok))
  end

  test "failed assertions are captured as test failures instead of aborting the file" do
    source = ~s(
    TEST "bad equality"
      1 2 ASSERT_EQ
    END
    TEST "still runs"
      T ASSERT_TRUE
    END
    )

    assert {[], env} = Cairn.eval_with_env(source, %{"__test_mode__" => true})

    assert [
             %{name: "bad equality", status: :error, message: message},
             %{name: "still runs", status: :ok}
           ] = Map.get(env, "__test_results__")

    assert message =~ "ASSERT_EQ failed"
  end
end
