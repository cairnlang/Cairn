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

  test "HTTP_SERVE exposes parsed cookies to the handler" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

    response = http_request(port, "GET", "/cookie", [{"Cookie", "theme=night"}], "")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "cookie:night"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE allows handlers to return explicit response headers" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

    response = http_get(port, "/set-cookie")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Set-Cookie: theme=night; Path=/"
    assert response =~ "cookie set"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "HTTP_SERVE exposes parsed POST form parameters to the handler" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

    response =
      http_post_form(port, "/submit", %{
        "name" => "Cairn"
      })

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "posted, Cairn"

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

  test "HTTP_SERVE returns 413 for oversized form bodies" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task =
      start_server_with_options(
        "127.0.0.1",
        port,
        ~s|M[ "request_line_max" 4096 "read_timeout_ms" 500 "body_max" 8 ]|,
        index_path,
        about_path
      )

    response =
      http_request(
        port,
        "POST",
        "/submit",
        [{"Content-Type", "application/x-www-form-urlencoded"}],
        "name=CairnTooLong"
      )

    assert response =~ "HTTP/1.1 413 Payload Too Large"
    assert response =~ "payload too large"

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

  test "HTTP_SERVE returns 415 for unsupported POST content types" do
    index_path = Path.expand("examples/web/static/index.html", File.cwd!())
    about_path = Path.expand("examples/web/static/about.html", File.cwd!())
    port = free_port()

    task = start_server("127.0.0.1", port, index_path, about_path)

    response =
      http_request(
        port,
        "POST",
        "/submit",
        [{"Content-Type", "text/plain"}],
        "name=Cairn"
      )

    assert response =~ "HTTP/1.1 415 Unsupported Media Type"
    assert response =~ "unsupported media type"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "web todo app renders Mnesia-backed items as escaped HTML" do
    previous = System.get_env("CAIRN_DB_DIR")
    db_dir = temp_db_dir()
    System.put_env("CAIRN_DB_DIR", db_dir)
    Cairn.DB.reset_for_tests!()

    on_exit(fn ->
      Cairn.DB.reset_for_tests!()

      if previous do
        System.put_env("CAIRN_DB_DIR", previous)
      else
        System.delete_env("CAIRN_DB_DIR")
      end
    end)

    :ok = Cairn.DB.put("todo:1", "open|buy milk")
    :ok = Cairn.DB.put("todo:2", "done|book train")
    :ok = Cairn.DB.put("todo:3", "open|<script>alert('hola')</script>")

    port = free_port()
    task = start_todo_app(port)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Content-Type: text/html; charset=utf-8"
    assert response =~ "Cairn Todo"
    assert response =~ "Open: 2 | Done: 1 | Total: 3"
    assert response =~ "@picocss/pico@2/css/pico.min.css"
    assert response =~ "todo-done-button"
    assert response =~ "todo-item-done"
    assert response =~ "buy milk"
    assert response =~ "&lt;script&gt;alert(&#39;hola&#39;)&lt;/script&gt;"
    refute response =~ "<script>alert('hola')</script>"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "web todo app can add and complete Mnesia-backed items through POST routes and survive app restart" do
    previous = System.get_env("CAIRN_DB_DIR")
    db_dir = temp_db_dir()
    System.put_env("CAIRN_DB_DIR", db_dir)
    Cairn.DB.reset_for_tests!()

    on_exit(fn ->
      Cairn.DB.reset_for_tests!()

      if previous do
        System.put_env("CAIRN_DB_DIR", previous)
      else
        System.delete_env("CAIRN_DB_DIR")
      end
    end)

    :ok = Cairn.DB.put("todo:1", "open|buy milk")
    :ok = Cairn.DB.put("todo:2", "open|prepare slides")

    port = free_port()
    task = start_todo_app(port)

    add_response = http_post_form(port, "/add", %{"title" => "book flight"})
    done_response = http_post_form(port, "/done", %{"id" => "1"})

    assert add_response =~ "HTTP/1.1 200 OK"
    assert add_response =~ "book flight"
    assert done_response =~ "HTTP/1.1 200 OK"
    assert done_response =~ "todo-item-done"
    assert done_response =~ "<span class=\"todo-status\">done</span>"
    assert done_response =~ "<span class=\"todo-title\">buy milk</span>"

    assert nil == Task.shutdown(task, :brutal_kill)

    Cairn.DB.restart_for_tests!()

    next_port = free_port()
    restarted_task = start_todo_app(next_port)
    persisted_response = http_get(next_port, "/")

    assert persisted_response =~ "todo-item-done"
    assert persisted_response =~ "prepare slides"
    assert persisted_response =~ "book flight"
    assert persisted_response =~ "Open: 2 | Done: 1 | Total: 3"

    assert nil == Task.shutdown(restarted_task, :brutal_kill)
  end

  test "web affordability app renders the input form on GET /" do
    port = free_port()
    task = start_afford_app(port)

    response = http_get(port, "/")

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Content-Type: text/html; charset=utf-8"
    assert response =~ "Can I Afford This?"
    assert response =~ "Estimate whether a proposed purchase or subscription is financially safe."
    assert response =~ "action=\"/evaluate\""
    assert response =~ "Enter your current numbers and evaluate a proposed cost."

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "web affordability app evaluates safe and unsafe scenarios through POST" do
    port = free_port()
    task = start_afford_app(port)

    safe_response =
      http_post_form(port, "/evaluate", %{
        "cash" => "1000",
        "income" => "500",
        "baseline" => "400",
        "proposed" => "20",
        "kind" => "recurring"
      })

    unsafe_response =
      http_post_form(port, "/evaluate", %{
        "cash" => "1000",
        "income" => "500",
        "baseline" => "400",
        "proposed" => "900",
        "kind" => "one_time"
      })

    assert safe_response =~ "HTTP/1.1 200 OK"
    assert safe_response =~ "Risk: safe"
    assert safe_response =~ "Safe to proceed"
    assert safe_response =~ "<strong>Score:</strong> 0"
    assert safe_response =~ "<strong>Projected monthly margin:</strong> 80"

    assert unsafe_response =~ "HTTP/1.1 200 OK"
    assert unsafe_response =~ "Risk: not safe"
    assert unsafe_response =~ "Not safe: delay or reduce the cost"
    assert unsafe_response =~ "<strong>Score:</strong> 2"
    assert unsafe_response =~ "<strong>Remaining cash after purchase:</strong> 100"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  test "web affordability app rejects invalid input cleanly" do
    port = free_port()
    task = start_afford_app(port)

    response =
      http_post_form(port, "/evaluate", %{
        "cash" => "oops",
        "income" => "500",
        "baseline" => "400",
        "proposed" => "20",
        "kind" => "one_time"
      })

    assert response =~ "HTTP/1.1 200 OK"
    assert response =~ "Input error"
    assert response =~ "All numeric fields must be non-negative integers"

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  defp http_get(port, path) do
    http_request(port, "GET", path)
  end

  defp http_post_form(port, path, fields) do
    body = URI.encode_query(fields)
    http_request(port, "POST", path, [{"Content-Type", "application/x-www-form-urlencoded"}], body)
  end

  defp http_request(port, method, path) do
    http_request(port, method, path, [], "")
  end

  defp http_request(port, method, path, headers, body) do
    connect_and_request(port, method, path, headers, body, 50)
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

  defp connect_and_request(_port, _method, _path, _headers, _body, 0),
    do: flunk("server did not start in time")

  defp connect_and_request(port, method, path, headers, body, attempts) do
    case :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: :raw, active: false], 100) do
      {:ok, socket} ->
        header_lines =
          Enum.map(headers, fn {name, value} -> [name, ": ", value, "\r\n"] end)

        content_length_line =
          if body == "" do
            []
          else
            ["Content-Length: ", Integer.to_string(byte_size(body)), "\r\n"]
          end

        :ok =
          :gen_tcp.send(
            socket,
            [
              method,
              " ",
              path,
              " HTTP/1.1\r\n",
              "Host: localhost\r\n",
              header_lines,
              content_length_line,
              "Connection: close\r\n\r\n",
              body
            ]
          )

        response = recv_all(socket, "")
        :gen_tcp.close(socket)
        response

      {:error, _reason} ->
        Process.sleep(20)
        connect_and_request(port, method, path, headers, body, attempts - 1)
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
        LET form
        LET headers
        LET cookies
        headers DROP

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
                DUP "/cookie" EQ
                IF
                  DROP
                  200
                  "text/plain; charset=utf-8"
                  cookies DUP "theme" HAS
                  IF
                    "theme" GET
                  ELSE
                    DROP
                    "none"
                  END
                  "cookie:{}\\n" FMT
                ELSE
                  DUP "/set-cookie" EQ
                  IF
                    DROP
                    200
                    M[
                      "Content-Type" "text/plain; charset=utf-8"
                      "Set-Cookie" "theme=night; Path=/"
                    ]
                    "cookie set\\n"
                  ELSE
                    DROP
                    404
                    "text/plain; charset=utf-8"
                    "not found\\n"
                  END
                END
              END
            END
          END
        ELSE
          method "POST" EQ
          IF
            path "/submit" EQ
            IF
              200
              "text/plain; charset=utf-8"
              form "name" HAS
              IF
                form "name" GET
              ELSE
                "friend"
              END
              "posted, {}\\n" FMT
            ELSE
              405
              "text/plain; charset=utf-8"
              "method not allowed\\n"
            END
          ELSE
            405
            "text/plain; charset=utf-8"
            "method not allowed\\n"
          END
        END
      } HTTP_SERVE
      """

      Cairn.eval(source)
    end)
  end

  defp start_todo_app(port) do
    Task.async(fn ->
      Process.put(:cairn_argv, ["127.0.0.1", Integer.to_string(port)])
      Cairn.eval_file("examples/web/todo_app.crn")
    end)
  end

  defp start_afford_app(port) do
    Task.async(fn ->
      Process.put(:cairn_argv, ["127.0.0.1", Integer.to_string(port)])
      Cairn.eval_file("examples/web/afford_app.crn")
    end)
  end

  defp temp_db_dir do
    dir = System.tmp_dir!()
    Path.join(dir, "cairn_http_db_#{System.unique_integer([:positive])}")
  end
end
