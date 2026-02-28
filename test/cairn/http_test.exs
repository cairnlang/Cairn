defmodule Cairn.HTTPTest do
  use ExUnit.Case, async: false

  test "HTTP_SERVE serves the configured html file for GET /" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Content-Type: text/html; charset=utf-8"
    assert response =~ "<h1>Hello from Cairn</h1>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE returns 404 for paths other than /" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

    response = http_get(port, "/nope")

    assert response =~ "HTTP/1.1 404 Not Found"
    assert response =~ "Content-Type: text/plain; charset=utf-8"
    assert response =~ "not found"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE can reject non-GET methods with 405" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

    response = http_request(port, "POST", "/")

    assert response =~ "HTTP/1.1 405 Method Not Allowed"
    assert response =~ "Content-Type: text/plain; charset=utf-8"
    assert response =~ "method not allowed"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE handles multiple requests on the same listener" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

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
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("0.0.0.0", port, index_path, about_path)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "<h1>Hello from Cairn</h1>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE keeps accepting while an earlier client stays idle" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)
    idle_socket = wait_for_connect(port, 50)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "<h1>Hello from Cairn</h1>"

    :gen_tcp.close(idle_socket)
    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE exposes parsed query parameters to the handler" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

    response = http_request(port, "GET", "/echo?name=Cairn")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Content-Type: text/plain; charset=utf-8"
    assert response =~ "hello, Cairn"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE returns 414 for oversized request lines and keeps listening" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task =
      start_server_with_options(
        "127.0.0.1",
        port,
        ~s|M[ "request_line_max" 64 "read_timeout_ms" 500 ]|,
        index_path,
        about_path
      )

    long_path = "/" <> String.duplicate("a", 128)
    long_response = http_get(port, long_path)
    ok_response = http_get(port, "/")

    assert long_response =~ "HTTP/1.1 414 URI Too Long"
    assert long_response =~ "uri too long"
    assert ok_response =~ "HTTP/1.1 200 OK"
    assert ok_response =~ "<h1>Hello from Cairn</h1>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE returns 400 for malformed request lines" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

    response = raw_request(port, "BROKEN\r\n\r\n")

    assert response =~ "HTTP/1.1 400 Bad Request"
    assert response =~ "bad request"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE closes idle clients after the configured read timeout without killing the listener" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task =
      start_server_with_options(
        "127.0.0.1",
        port,
        ~s|M[ "request_line_max" 4096 "read_timeout_ms" 100 ]|,
        index_path,
        about_path
      )

    idle_socket = wait_for_connect(port, 50)
    Process.sleep(180)

    assert {:error, :closed} = :gen_tcp.recv(idle_socket, 0, 200)

    ok_response = http_get(port, "/")

    assert ok_response =~ "HTTP/1.1 200 OK"
    assert ok_response =~ "<h1>Hello from Cairn</h1>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "web todo app renders file-backed items as escaped HTML" do
    port = free_port()
    todo_path = write_temp_todo_file(["open|buy milk", "done|book train", "open|<script>alert('hola')</script>"])

    task = start_todo_app(port, todo_path)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Content-Type: text/html; charset=utf-8"
    assert response =~ "Cairn Todo"
    assert response =~ "Open: 2 | Done: 1 | Total: 3"
    assert response =~ "@picocss/pico@2/css/pico.min.css"
    assert response =~ "buy milk"
    assert response =~ "&lt;script&gt;alert(&#39;hola&#39;)&lt;/script&gt;"
    refute response =~ "<script>alert('hola')</script>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "web todo app can add and complete file-backed items through GET routes" do
    port = free_port()
    todo_path = write_temp_todo_file(["open|buy milk", "open|prepare slides"])

    task = start_todo_app(port, todo_path)

    add_response = http_get(port, "/add?title=book%20flight")
    done_response = http_get(port, "/done?id=1")
    saved = File.read!(todo_path)

    assert add_response =~ "HTTP/1.1 200 OK"
    assert add_response =~ "book flight"
    assert done_response =~ "HTTP/1.1 200 OK"
    assert done_response =~ "<strong>done</strong> buy milk"
    assert saved =~ "done|buy milk"
    assert saved =~ "open|book flight"

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

  defp raw_request(port, request, attempts \\ 50)

  defp raw_request(_port, _request, 0) do
    flunk("server did not start in time for raw request")
  end

  defp raw_request(port, request, attempts) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :raw, active: false], 100) do
      {:ok, socket} ->
        :ok = :gen_tcp.send(socket, request)
        response = recv_all(socket, "")
        :gen_tcp.close(socket)
        response

      {:error, _reason} ->
        Process.sleep(20)
        raw_request(port, request, attempts - 1)
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

  defp start_server(bind_host, port, index_path, about_path) do
    start_server_with_options(bind_host, port, nil, index_path, about_path)
  end

  defp start_server_with_options(bind_host, port, options_source, index_path, about_path) do
    Task.async(fn ->
      prefix =
        case options_source do
          nil -> ~s|"#{bind_host}" #{port}|
          source -> source <> ~s| "#{bind_host}" #{port}|
        end

      source = """
      #{prefix} {
        LET path
        LET method
        LET query

        method "GET" EQ
        IF
          path DUP "/" EQ
          IF
            DROP
            200
            "text/html; charset=utf-8"
            "#{index_path}" READ_FILE!
          ELSE
            DUP "/about" EQ
            IF
              DROP
              200
              "text/html; charset=utf-8"
              "#{about_path}" READ_FILE!
            ELSE
              DUP "/echo" EQ
              IF
                DROP
                200
                "text/plain; charset=utf-8"
                query DUP "name" HAS
                IF
                  "name" GET
                ELSE
                  DROP
                  "friend"
                END
                "hello, {}\\n" FMT
              ELSE
                DROP
                404
                "text/plain; charset=utf-8"
                "not found\\n"
              END
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

  defp start_todo_app(port, todo_path) do
    Task.async(fn ->
      Process.put(:cairn_argv, ["127.0.0.1", Integer.to_string(port), todo_path])
      Cairn.eval_file("examples/web/todo_app.crn")
    end)
  end

  defp write_temp_todo_file(lines) do
    dir = System.tmp_dir!()
    path = Path.join(dir, "cairn_web_todo_#{System.unique_integer([:positive])}.txt")
    File.write!(path, Enum.join(lines, "\n"))
    path
  end
end
