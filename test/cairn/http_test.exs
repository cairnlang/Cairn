defmodule Cairn.HTTPTest do
  use ExUnit.Case, async: false

  test "HTTP_SERVE serves the configured html file for GET /" do
    path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, path, about_path)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Content-Type: text/html; charset=utf-8"
    assert response =~ "<h1>Hello from Cairn</h1>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE returns 404 for paths other than /" do
    path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, path, about_path)

    response = http_get(port, "/nope")

    assert response =~ "HTTP/1.1 404 Not Found"
    assert response =~ "Content-Type: text/plain; charset=utf-8"
    assert response =~ "not found"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE can reject non-GET methods with 405" do
    path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, path, about_path)

    response = http_request(port, "POST", "/")

    assert response =~ "HTTP/1.1 405 Method Not Allowed"
    assert response =~ "Content-Type: text/plain; charset=utf-8"
    assert response =~ "method not allowed"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE handles multiple requests on the same listener" do
    path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, path, about_path)

    ok_response = http_get(port, "/")
    about_response = http_get(port, "/about")
    not_found_response = http_get(port, "/missing")

    assert ok_response =~ "HTTP/1.1 200 OK"
    assert ok_response =~ "<h1>Hello from Cairn</h1>"
    assert about_response =~ "HTTP/1.1 200 OK"
    assert about_response =~ "<h1>About This Tiny Cairn Server</h1>"
    assert not_found_response =~ "HTTP/1.1 404 Not Found"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE can bind to an explicit outward-facing address literal" do
    path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("0.0.0.0", port, path, about_path)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "<h1>Hello from Cairn</h1>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE keeps accepting while an earlier client stays idle" do
    path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, path, about_path)
    idle_socket = wait_for_connect(port, 50)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "<h1>Hello from Cairn</h1>"

    :gen_tcp.close(idle_socket)
    assert nil == Task.shutdown(task, :brutal_kill)
  end

  defp http_get(port, path) do
    http_request(port, "GET", path)
  end

  defp http_request(port, method, path) do
    connect_and_request(port, method, path, 50)
  end

  defp wait_for_connect(_port, 0), do: flunk("server did not accept an idle client in time")

  defp wait_for_connect(port, attempts) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :raw, active: false], 100) do
      {:ok, socket} ->
        socket

      {:error, _reason} ->
        Process.sleep(20)
        wait_for_connect(port, attempts - 1)
    end
  end

  defp connect_and_request(_port, _method, _path, 0), do: flunk("server did not start in time")

  defp connect_and_request(port, method, path, attempts) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :raw, active: false], 100) do
      {:ok, socket} ->
        :ok =
          :gen_tcp.send(
            socket,
            [
              method,
              " ",
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
        connect_and_request(port, method, path, attempts - 1)
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

  defp start_server(bind_host, port, path, about_path) do
    Task.async(fn ->
      source = """
      "#{bind_host}" #{port} {
        LET path
        LET method
        method "GET" EQ
        IF
          path DUP "/" EQ
          IF
            DROP
            200
            "text/html; charset=utf-8"
            "#{path}" READ_FILE!
          ELSE
            DUP "/about" EQ
            IF
              DROP
              200
              "text/html; charset=utf-8"
              "#{about_path}" READ_FILE!
            ELSE
              DROP
              404
              "text/plain; charset=utf-8"
              "not found\\n"
            END
          END
        ELSE
          path DROP
          405
          "text/plain; charset=utf-8"
          "method not allowed\\n"
        END
      } HTTP_SERVE
      """

      Cairn.eval(source)
    end)
  end
end
