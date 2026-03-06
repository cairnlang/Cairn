defmodule Cairn.PebblesDashboardTest do
  use ExUnit.Case, async: false

  @dashboard_main "tools/pebbles/dashboard.crn"

  setup do
    previous_db_dir = System.get_env("CAIRN_DB_DIR")
    previous_backend = Application.get_env(:cairn, :data_store_backend)

    dir =
      Path.join(System.tmp_dir!(), "cairn_pebbles_dashboard_test_#{System.unique_integer([:positive])}")

    System.put_env("CAIRN_DB_DIR", dir)
    Application.put_env(:cairn, :data_store_backend, Cairn.DataStore.Backend.Mnesia)
    Cairn.DB.reset_for_tests!()

    on_exit(fn ->
      Cairn.DB.reset_for_tests!()

      if previous_db_dir do
        System.put_env("CAIRN_DB_DIR", previous_db_dir)
      else
        System.delete_env("CAIRN_DB_DIR")
      end

      if previous_backend do
        Application.put_env(:cairn, :data_store_backend, previous_backend)
      else
        Application.delete_env(:cairn, :data_store_backend)
      end
    end)

    :ok
  end

  test "cairn-native dashboard tests run through --test mode" do
    parent = self()

    stdout =
      ExUnit.CaptureIO.capture_io(fn ->
        stderr =
          ExUnit.CaptureIO.capture_io(:stderr, fn ->
            assert :ok = Cairn.CLI.run(["--test", "tools/pebbles/test_dashboard.crn"], halt_on_error: false)
          end)

        send(parent, {:captured_stderr, stderr})
      end)

    stderr =
      receive do
        {:captured_stderr, captured} -> captured
      end

    assert stdout =~ "PASS dashboard summary projects total and per-status counts"
    assert stdout =~ "PASS dashboard status filter returns only matching rows"
    assert stdout =~ "PASS dashboard status filter rejects unknown values"
    assert stdout =~ "PASS dashboard text filter matches title reason and notes"
    assert stdout =~ "PASS dashboard blockers keeps only blocked rows with a reason"
    assert stdout =~ "PASS dashboard row rendering escapes unsafe text"
    assert stdout =~ "PASS dashboard filter bar escapes user input"
    assert stdout =~ "PASS dashboard template wrapper renders the ctpl shell"
    assert stdout =~ "PASS dashboard summary tiles template renders projected counts"
    assert stdout =~ "PASS dashboard filter template keeps query and status escaped"
    assert stdout =~ "PASS dashboard section template renders escaped row payload"
    assert stderr =~ "TEST SUMMARY: total=11 passed=11 failed=0"
  end

  test "dashboard renders summary tiles grouped sections and blockers panel" do
    seed_pebble(1, "open", "Ship docs", "", [])
    seed_pebble(2, "doing", "Parser cleanup", "", [])
    seed_pebble(3, "blocked", "Auth flow", "waiting on review", ["ping reviewer"])
    seed_pebble(4, "done", "Release prep", "", ["cut tag"])

    port = free_port()
    task = start_dashboard(port)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Content-Type: text/html; charset=utf-8"
    assert response =~ "Pebbles Dashboard"
    assert response =~ "<h3>Total</h3><p>4</p>"
    assert response =~ "<h3>Open</h3><p>1</p>"
    assert response =~ "<h2>Open (1)</h2>"
    assert response =~ "<h2>Doing (1)</h2>"
    assert response =~ "<h2>Blocked (1)</h2>"
    assert response =~ "<h2>Done (1)</h2>"
    assert response =~ "<h2>Blockers</h2>"
    assert response =~ "waiting on review"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "dashboard status and text filters narrow visible groups" do
    seed_pebble(1, "open", "Ship docs", "", [])
    seed_pebble(2, "blocked", "Auth flow", "waiting on review", ["ping reviewer"])
    seed_pebble(3, "blocked", "Infra task", "waiting on deploy", [])

    port = free_port()
    task = start_dashboard(port)

    blocked_response = http_get(port, "/?status=blocked")
    assert blocked_response =~ "<h2>Blocked (2)</h2>"
    assert blocked_response =~ "Auth flow"
    assert blocked_response =~ "Infra task"
    refute blocked_response =~ "<code>#1 [open] Ship docs</code>"

    search_response = http_get(port, "/?status=all&q=review")
    assert search_response =~ "showing 1 of 3 items"
    assert search_response =~ "Auth flow"
    refute search_response =~ "Infra task"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "dashboard escapes rendered fields and reports invalid status filter" do
    seed_pebble(1, "blocked", "<script>alert('hola')</script>", "<b>bad</b>", ["<img src=x onerror=alert(1)>"])

    port = free_port()
    task = start_dashboard(port)

    response = http_get(port, "/?status=%3Cbad%3E&q=%3Cscript%3E")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "invalid status filter: &lt;bad&gt; (use all|open|doing|blocked|done)"
    assert response =~ "&lt;script&gt;alert(&#39;hola&#39;)&lt;/script&gt;"
    assert response =~ "&lt;b&gt;bad&lt;/b&gt;"
    refute response =~ "<script>alert('hola')</script>"
    refute response =~ "<b>bad</b>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  defp seed_pebble(id, status, title, reason, notes) do
    key = "pebble/" <> id_text(id)
    notes_blob = Enum.join(notes, "~")
    row = "#{status}|#{title}|#{reason}|#{notes_blob}"
    :ok = Cairn.DB.put(key, row)
    :ok = Cairn.DB.put("meta/next_id", Integer.to_string(id + 1))
  end

  defp id_text(id) do
    id
    |> Integer.to_string()
    |> String.pad_leading(12, "0")
  end

  defp start_dashboard(port) do
    Task.async(fn ->
      Process.put(:cairn_argv, ["127.0.0.1", Integer.to_string(port)])
      Cairn.eval_file(@dashboard_main)
    end)
  end

  defp http_get(port, path) do
    connect_and_request(port, path, 50)
  end

  defp connect_and_request(_port, _path, 0), do: flunk("dashboard server did not start in time")

  defp connect_and_request(port, path, attempts) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :raw, active: false], 100) do
      {:ok, socket} ->
        :ok =
          :gen_tcp.send(
            socket,
            [
              "GET ",
              path,
              " HTTP/1.1\r\n",
              "Host: localhost\r\n",
              "Connection: close\r\n\r\n"
            ]
          )

        response = recv_all(socket, "")
        :gen_tcp.close(socket)
        response

      {:error, _reason} ->
        Process.sleep(20)
        connect_and_request(port, path, attempts - 1)
    end
  end

  defp recv_all(socket, acc) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, chunk} -> recv_all(socket, acc <> chunk)
      {:error, :closed} -> acc
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, packet: :raw, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_ip, port}} = :inet.sockname(socket)
    :gen_tcp.close(socket)
    port
  end
end
