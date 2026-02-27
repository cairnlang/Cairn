defmodule Axiom.ConcurrencyRuntimeTest do
  use ExUnit.Case, async: false

  test "SPAWN can create a one-shot actor and SEND delivers a message to RECEIVE" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert [] =
                 Axiom.eval("""
                 TYPE msg = Ping | Pong

                 SPAWN msg {
                   RECEIVE
                     Ping { "got_ping" SAID }
                     Pong { "got_pong" SAID }
                   END
                 }
                 DUP Ping SEND
                 DROP
                 """)

        Process.sleep(30)
      end)

    assert output =~ "got_ping"
  end

  test "spawned block begins with self pid on stack" do
    assert [] =
             Axiom.eval("""
             TYPE msg = Ping
             SPAWN msg { DROP }
             DROP
             """)
  end

  test "runtime example runs end-to-end" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Axiom.eval_file("examples/concurrency/ping_once.ax")
        Process.sleep(30)
      end)

    assert output =~ "got_ping"
  end
end
