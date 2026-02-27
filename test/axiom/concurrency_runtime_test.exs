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
                   DROP
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

  test "SELF can send a bootstrap message to the current actor" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Axiom.eval_file("examples/concurrency/self_boot.ax")
        Process.sleep(30)
      end)

    assert output =~ "booted"
  end

  test "implicit actor-local RECEIVE can process multiple messages without pid juggling" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Axiom.eval_file("examples/concurrency/two_pings.ax")
        Process.sleep(30)
      end)

    assert output =~ "ping1"
    assert output =~ "ping2"
  end

  test "stateful counter actor can carry stack state across repeated receives" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Axiom.eval_file("examples/concurrency/counter.ax")
        Process.sleep(30)
      end)

    assert output =~ "count=1"
  end

  test "traffic light actor can step through named phases" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Axiom.eval_file("examples/concurrency/traffic_light.ax")
        Process.sleep(30)
      end)

    assert output =~ "phase=green"
    assert output =~ "phase=yellow"
    assert output =~ "phase=red"
  end

  test "practical notifier actor can report queued and sent states" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Axiom.eval_file("examples/concurrency/notifier.ax")
        Process.sleep(30)
      end)

    assert output =~ "notifier=queued"
    assert output =~ "notifier=sent"
  end

  test "EXIT in an unlinked actor does not kill the caller" do
    assert [] =
             Axiom.eval("""
             TYPE msg = Fail

             SPAWN msg {
               SELF Fail SEND
               RECEIVE
                 Fail { "child_failed" SWAP DROP EXIT }
               END
             }
             DROP
             """)

    Process.sleep(30)
  end

  test "SPAWN_LINK propagates child EXIT to the linked caller" do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        Axiom.eval_file("examples/concurrency/linked_failure.ax")
        Process.sleep(100)
        send(parent, :unexpected_survival)
      end)

    refute_receive :unexpected_survival, 150

    assert_receive {:DOWN, ^ref, :process, ^pid, "child_failed"}, 200
  end

  test "MONITOR returns a non-blocking handle" do
    assert [{:monitor, {:user_type, "msg"}, pid, ref}] =
             Axiom.eval("""
             TYPE msg = Fail

             SPAWN msg {
               SELF Fail SEND
               RECEIVE
                 Fail { "child_failed" SWAP DROP EXIT }
               END
             }
             MONITOR
             """)

    assert is_pid(pid)
    assert is_reference(ref)
  end

  test "AWAIT returns the child exit reason without killing the caller" do
    assert ["child_failed"] =
             Axiom.eval("""
             TYPE msg = Fail

             SPAWN msg {
               SELF Fail SEND
               RECEIVE
                 Fail { "child_failed" SWAP DROP EXIT }
               END
             }
             MONITOR AWAIT
             """)
  end

  test "restart example can observe failure and complete a one-shot restart" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert {[], _env} = Axiom.eval_file("examples/concurrency/restart_once.ax")
      end)

    assert output =~ "first_exit=worker_failed"
    assert output =~ "worker_restarted"
    assert output =~ "second_exit=normal"
  end
end
