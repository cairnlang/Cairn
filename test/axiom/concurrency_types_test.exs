defmodule Axiom.ConcurrencyTypesTest do
  use ExUnit.Case

  alias Axiom.Checker

  defp parse(source) do
    {:ok, tokens} = Axiom.Lexer.tokenize(source)
    {:ok, items} = Axiom.Parser.parse(tokens)
    items
  end

  defp check(source) do
    source
    |> parse()
    |> Checker.check()
  end

  defp check_ok(source), do: assert(:ok == check(source))

  defp check_errors(source) do
    assert {:error, errors} = check(source)
    errors
  end

  test "lexer tokenizes pid[user_type]" do
    assert {:ok, [{:type, {:pid, {:user_type, "msg"}}, 0}]} =
             Axiom.Lexer.tokenize("pid[msg]")
  end

  test "pid types parse in signatures and recursive type fields" do
    items =
      parse("""
      TYPE msg = Ping | Handoff pid[msg]
      DEF relay : pid[msg] -> str
        RECEIVE
          Ping { "ping" }
          Handoff { DROP "handoff" }
        END
      END
      """)

    assert [%Axiom.Types.TypeDef{name: "msg"}, %Axiom.Types.Function{name: "relay"}] = items
  end

  test "typed concurrency forms check successfully" do
    check_ok("""
    TYPE msg = Ping | Pong

    DEF send_ping : pid[msg] -> void
      Ping SEND
    END

    DEF receive_ping : pid[msg] -> str
      RECEIVE
        Ping { "ping" }
        Pong { "pong" }
      END
    END

    DEF spawn_peer : pid[msg]
      SPAWN msg { DROP "peer" SAID }
    END
    """)
  end

  test "SEND rejects mismatched payload types" do
    errors =
      check_errors("""
      TYPE msg = Ping

      DEF bad : pid[msg] -> void
        42 SEND
      END
      """)

    assert Enum.any?(errors, fn e -> e.message =~ "SEND expected msg, got int" end)
  end

  test "RECEIVE checks exhaustiveness" do
    errors =
      check_errors("""
      TYPE msg = Ping | Pong

      DEF bad : pid[msg] -> str
        RECEIVE
          Ping { "ping" }
        END
      END
      """)

    assert Enum.any?(errors, fn e -> e.message =~ "RECEIVE on 'msg' is not exhaustive" end)
  end

  test "SPAWN block must be stack-clean" do
    errors =
      check_errors("""
      TYPE msg = Ping

      DEF bad : pid[msg]
        SPAWN msg { "leak" }
      END
      """)

    assert Enum.any?(errors, fn e ->
             e.message =~ "SPAWN block must consume its self pid and leave an empty stack"
           end)
  end

  test "SELF is valid inside SPAWN blocks and invalid outside" do
    check_ok("""
    TYPE msg = Boot

    DEF actor : pid[msg]
      SPAWN msg { SELF DROP DROP }
    END
    """)

    errors = check_errors("SELF")
    assert Enum.any?(errors, fn e -> e.message =~ "SELF is only available inside a SPAWN block" end)
  end

  test "functions that use SELF require actor context at call sites" do
    check_ok("""
    TYPE msg = Boot

    DEF send_boot : void
      SELF Boot SEND
    END

    DEF actor : pid[msg]
      SPAWN msg { send_boot DROP }
    END
    """)

    errors =
      check_errors("""
      TYPE msg = Boot

      DEF send_boot : void
        SELF Boot SEND
      END

      send_boot
      """)

    assert Enum.any?(errors, fn e -> e.message =~ "function 'send_boot' requires actor context" end)
  end

  test "concurrency examples load successfully" do
    assert {[], _env} = Axiom.eval_file("examples/concurrency/ping_pong_types.ax")
    assert {[], _env} = Axiom.eval_file("examples/concurrency/traffic_light_types.ax")
    assert {[], _env} = Axiom.eval_file("examples/concurrency/self_boot.ax")
  end
end
