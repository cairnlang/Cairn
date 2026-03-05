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

  @tag :web_edge
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

  test "web todo app parity flow works on Postgres backend when enabled" do
    if System.get_env("CAIRN_PG_TEST") == "1" do
      case clear_postgres_kv_table() do
        :ok ->
          with_postgres_backend(fn ->
            port = free_port()
            task = start_todo_app(port)

            add_response = http_post_form(port, "/add", %{"title" => "book flight"})
            done_response = http_post_form(port, "/done", %{"id" => "1"})

            assert add_response =~ "HTTP/1.1 200 OK"
            assert add_response =~ "book flight"
            assert done_response =~ "HTTP/1.1 200 OK"
            assert done_response =~ "todo-item-done"
            assert done_response =~ "<span class=\"todo-status\">done</span>"
            assert done_response =~ "<span class=\"todo-title\">book flight</span>"
            assert done_response =~ "Open: 0 | Done: 1 | Total: 1"

            assert nil == Task.shutdown(task, :brutal_kill)

            next_port = free_port()
            restarted_task = start_todo_app(next_port)
            persisted_response = http_get(next_port, "/")

            assert persisted_response =~ "todo-item-done"
            assert persisted_response =~ "<span class=\"todo-title\">book flight</span>"
            assert persisted_response =~ "Open: 0 | Done: 1 | Total: 1"

            assert nil == Task.shutdown(restarted_task, :brutal_kill)
          end)

          _ = clear_postgres_kv_table()

        {:error, _reason} ->
          :ok
      end
    else
      :ok
    end
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

  @tag :web_edge
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

  @tag :web_edge
  test "web session demo can remember and clear a server-side session through cookies" do
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

    port = free_port()
    task = start_session_app(port)

    first_response = http_get(port, "/")

    assert first_response =~ "HTTP/1.1 200 OK"
    assert first_response =~ "Remember me"

    remember_response = http_post_form(port, "/remember", %{"name" => "Cairn"})

    assert remember_response =~ "HTTP/1.1 200 OK"
    assert remember_response =~ "Hello, <strong>Cairn</strong>."
    assert remember_response =~ "Set-Cookie: cairn_session="

    set_cookie = extract_header(remember_response, "set-cookie")
    assert is_binary(set_cookie)

    session_id =
      set_cookie
      |> String.split(";", parts: 2)
      |> hd()
      |> String.trim_leading("cairn_session=")

    assert Cairn.SessionStore.load(session_id) == {:ok, %{"name" => "Cairn"}}

    remembered_response =
      http_request(port, "GET", "/", [{"Cookie", "cairn_session=#{session_id}"}], "")

    assert remembered_response =~ "HTTP/1.1 200 OK"
    assert remembered_response =~ "Hello, <strong>Cairn</strong>."

    logout_response =
      http_request(port, "POST", "/logout", [{"Cookie", "cairn_session=#{session_id}"}], "")

    assert logout_response =~ "HTTP/1.1 200 OK"
    assert logout_response =~ "Remember me"

    assert logout_response =~
             "Set-Cookie: cairn_session=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"

    assert Cairn.SessionStore.load(session_id) == :error

    assert nil == Task.shutdown(task, :brutal_kill)

    Cairn.DB.restart_for_tests!()

    next_port = free_port()
    restarted_task = start_session_app(next_port)

    after_restart =
      http_request(next_port, "GET", "/", [{"Cookie", "cairn_session=#{session_id}"}], "")

    assert after_restart =~ "HTTP/1.1 200 OK"
    assert after_restart =~ "Remember me"

    assert nil == Task.shutdown(restarted_task, :brutal_kill)
  end

  @tag :web_edge
  test "web login demo can log in, persist identity in session, and log out" do
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

    port = free_port()
    task = start_login_app(port)

    first_response = http_get(port, "/")

    assert first_response =~ "HTTP/1.1 200 OK"
    assert first_response =~ "Login Demo"
    assert first_response =~ "action=\"/login\""

    invalid_response =
      http_post_form(port, "/login", %{
        "username" => "alice",
        "password" => "wrong"
      })

    assert invalid_response =~ "HTTP/1.1 200 OK"
    assert invalid_response =~ "Invalid username or password."
    assert is_nil(extract_header(invalid_response, "set-cookie"))

    login_response =
      http_post_form(port, "/login", %{
        "username" => "alice",
        "password" => "cairn"
      })

    assert login_response =~ "HTTP/1.1 200 OK"
    assert login_response =~ "Protected Home"
    assert login_response =~ "Hello, <strong>alice</strong>."
    assert login_response =~ "Your role is <strong>admin</strong>."
    assert login_response =~ "Set-Cookie: cairn_session="

    set_cookie = extract_header(login_response, "set-cookie")
    assert is_binary(set_cookie)

    session_id =
      set_cookie
      |> String.split(";", parts: 2)
      |> hd()
      |> String.trim_leading("cairn_session=")

    assert Cairn.SessionStore.load(session_id) == {:ok, %{"role" => "admin", "user" => "alice"}}

    remembered_response =
      http_request(port, "GET", "/", [{"Cookie", "cairn_session=#{session_id}"}], "")

    assert remembered_response =~ "HTTP/1.1 200 OK"
    assert remembered_response =~ "Hello, <strong>alice</strong>."

    profile_response =
      http_request(port, "GET", "/profile", [{"Cookie", "cairn_session=#{session_id}"}], "")

    assert profile_response =~ "HTTP/1.1 200 OK"
    assert profile_response =~ "Profile"
    assert profile_response =~ "Signed in as <strong>alice</strong>."

    admin_response =
      http_request(port, "GET", "/admin", [{"Cookie", "cairn_session=#{session_id}"}], "")

    assert admin_response =~ "HTTP/1.1 200 OK"
    assert admin_response =~ "Admin Area"
    assert admin_response =~ "You cleared the admin guard."

    bob_response =
      http_post_form(port, "/login", %{
        "username" => "bob",
        "password" => "cairn"
      })

    bob_cookie = extract_header(bob_response, "set-cookie")
    assert is_binary(bob_cookie)

    bob_session_id =
      bob_cookie
      |> String.split(";", parts: 2)
      |> hd()
      |> String.trim_leading("cairn_session=")

    forbidden_response =
      http_request(port, "GET", "/admin", [{"Cookie", "cairn_session=#{bob_session_id}"}], "")

    assert forbidden_response =~ "HTTP/1.1 403 Forbidden"
    assert forbidden_response =~ "forbidden"

    bob_profile_response =
      http_request(port, "GET", "/profile", [{"Cookie", "cairn_session=#{bob_session_id}"}], "")

    assert bob_profile_response =~ "HTTP/1.1 200 OK"
    assert bob_profile_response =~ "Profile"
    assert bob_profile_response =~ "Signed in as <strong>bob</strong>."

    unauth_profile_response = http_get(port, "/profile")
    assert unauth_profile_response =~ "HTTP/1.1 401 Unauthorized"
    assert unauth_profile_response =~ "login required"

    unauth_response = http_get(port, "/admin")
    assert unauth_response =~ "HTTP/1.1 401 Unauthorized"
    assert unauth_response =~ "login required"

    logout_response =
      http_request(port, "POST", "/logout", [{"Cookie", "cairn_session=#{session_id}"}], "")

    assert logout_response =~ "HTTP/1.1 200 OK"
    assert logout_response =~ "Login Demo"

    assert logout_response =~
             "Set-Cookie: cairn_session=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"

    assert Cairn.SessionStore.load(session_id) == :error

    assert nil == Task.shutdown(task, :brutal_kill)
  end

  defp http_get(port, path) do
    http_request(port, "GET", path)
  end

  defp http_post_form(port, path, fields) do
    body = URI.encode_query(fields)

    http_request(
      port,
      "POST",
      path,
      [{"Content-Type", "application/x-www-form-urlencoded"}],
      body
    )
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
        header_lines = Enum.map(headers, fn {name, value} -> [name, ": ", value, "\r\n"] end)

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
        LET session
        headers DROP
        session DROP

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

  defp start_session_app(port) do
    Task.async(fn ->
      Process.put(:cairn_argv, ["127.0.0.1", Integer.to_string(port)])
      Cairn.eval_file("examples/web/session_demo.crn")
    end)
  end

  defp start_login_app(port) do
    Task.async(fn ->
      Process.put(:cairn_argv, ["127.0.0.1", Integer.to_string(port)])
      Cairn.eval_file("examples/web/login_app.crn")
    end)
  end

  defp extract_header(response, header_name) do
    wanted = String.downcase(header_name)

    response
    |> String.split("\r\n")
    |> Enum.find_value(fn line ->
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          if String.downcase(name) == wanted do
            String.trim(value)
          else
            nil
          end

        _ ->
          nil
      end
    end)
  end

  defp temp_db_dir do
    dir = System.tmp_dir!()
    Path.join(dir, "cairn_http_db_#{System.unique_integer([:positive])}")
  end

  defp with_postgres_backend(fun) when is_function(fun, 0) do
    previous_backend = Application.get_env(:cairn, :data_store_backend)
    previous_backend_env = System.get_env("CAIRN_DATA_STORE_BACKEND")

    Application.put_env(:cairn, :data_store_backend, Cairn.DataStore.Backend.Postgres)
    System.put_env("CAIRN_DATA_STORE_BACKEND", "postgres")

    try do
      fun.()
    after
      if previous_backend do
        Application.put_env(:cairn, :data_store_backend, previous_backend)
      else
        Application.delete_env(:cairn, :data_store_backend)
      end

      if previous_backend_env do
        System.put_env("CAIRN_DATA_STORE_BACKEND", previous_backend_env)
      else
        System.delete_env("CAIRN_DATA_STORE_BACKEND")
      end
    end
  end

  defp clear_postgres_kv_table do
    case Postgrex.start_link(postgres_options()) do
      {:ok, conn} ->
        result = Postgrex.query(conn, "DROP TABLE IF EXISTS cairn_kv", [])
        GenServer.stop(conn)

        case result do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp postgres_options do
    [
      hostname: System.get_env("CAIRN_PG_HOST", "127.0.0.1"),
      port: String.to_integer(System.get_env("CAIRN_PG_PORT", "5432")),
      database: System.get_env("CAIRN_PG_DATABASE", "cairn"),
      username: System.get_env("CAIRN_PG_USER", "postgres"),
      password: System.get_env("CAIRN_PG_PASSWORD", "postgres"),
      ssl: System.get_env("CAIRN_PG_SSLMODE", "disable") == "require",
      timeout: String.to_integer(System.get_env("CAIRN_PG_TIMEOUT_MS", "5000"))
    ]
  end
end
