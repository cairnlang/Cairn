defmodule Cairn.HTTPTest do
  use ExUnit.Case, async: false

  test "HTTP_SERVE serves the configured html file for GET /" do
    path = Path.expand("examples/web/static/index.html", File.cwd!())
    port = free_port()

    task = start_server(port, path)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Content-Type: text/html; charset=utf-8"
    assert response =~ "<h1>Hello from Cairn</h1>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE returns 404 for paths other than /" do
    path = Path.expand("examples/web/static/index.html", File.cwd!())
    port = free_port()

    task = start_server(port, path)

    response = http_get(port, "/nope")

    assert response =~ "HTTP/1.1 404 Not Found"
    assert response =~ "Content-Type: text/plain; charset=utf-8"
    assert response =~ "not found"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE handles multiple requests on the same listener" do
    path = Path.expand("examples/web/static/index.html", File.cwd!())
    port = free_port()

    task = start_server(port, path)

    ok_response = http_get(port, "/")
    not_found_response = http_get(port, "/missing")

    assert ok_response =~ "HTTP/1.1 200 OK"
    assert ok_response =~ "<h1>Hello from Cairn</h1>"
    assert not_found_response =~ "HTTP/1.1 404 Not Found"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  defp http_get(port, path) do
    connect_and_request(port, path, 50)
  end

  defp connect_and_request(_port, _path, 0), do: flunk("server did not start in time")

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

  defp start_server(port, path) do
    Task.async(fn ->
      source = """
      #{port} {
        DUP "/" EQ
        IF
          DROP
          200
          "text/html; charset=utf-8"
          "#{path}" READ_FILE!
        ELSE
          DROP
          404
          "text/plain; charset=utf-8"
          "not found\\n"
        END
      } HTTP_SERVE
      """

      Cairn.eval(source)
    end)
  end
end
