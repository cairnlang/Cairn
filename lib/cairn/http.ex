defmodule Cairn.HTTP do
  @moduledoc """
  Minimal host-backed HTTP helpers for bounded serving primitives.

  The current slice stays intentionally narrow:
  - one long-lived listener
  - one lightweight worker per connection
  - minimal request parsing (`method`, `path`, `query`, `form`, `headers`, `cookies`, `session`)
  - simple response framing with optional response headers and server-side sessions

  This keeps the transport boundary honest while letting Cairn own routing and
  response decisions.
  """

  alias Cairn.SessionStore

  @listen_opts [:binary, packet: :raw, active: false, reuseaddr: true]
  @default_options %{
    "request_line_max" => 4096,
    "read_timeout_ms" => 5000,
    "body_max" => 8192
  }

  @spec serve(integer(), (String.t(), String.t(), map(), map() -> {integer(), String.t(), String.t()})) ::
          no_return()
  def serve(port, handler) when is_integer(port) and is_function(handler, 4) do
    serve("127.0.0.1", port, @default_options, handler)
  end

  @spec serve(
          integer(),
          (String.t(), String.t(), map(), map(), map(), map() ->
             {integer(), String.t(), String.t()} | {integer(), map(), String.t()})
        ) :: no_return()
  def serve(port, handler) when is_integer(port) and is_function(handler, 6) do
    serve("127.0.0.1", port, @default_options, handler)
  end

  @spec serve(
          integer(),
          (String.t(), String.t(), map(), map(), map(), map(), map() ->
             {integer(), String.t(), String.t()}
             | {integer(), map(), String.t()}
             | {integer(), map(), String.t(), map()})
        ) :: no_return()
  def serve(port, handler) when is_integer(port) and is_function(handler, 7) do
    serve("127.0.0.1", port, @default_options, handler)
  end

  @spec serve(integer(), map(), (String.t(), String.t(), map(), map() -> {integer(), String.t(), String.t()})) ::
          no_return()
  def serve(port, options, handler)
      when is_integer(port) and is_map(options) and is_function(handler, 4) do
    serve("127.0.0.1", port, options, handler)
  end

  @spec serve(
          integer(),
          map(),
          (String.t(), String.t(), map(), map(), map(), map() ->
             {integer(), String.t(), String.t()} | {integer(), map(), String.t()})
        ) :: no_return()
  def serve(port, options, handler)
      when is_integer(port) and is_map(options) and is_function(handler, 6) do
    serve("127.0.0.1", port, options, handler)
  end

  @spec serve(
          integer(),
          map(),
          (String.t(), String.t(), map(), map(), map(), map(), map() ->
             {integer(), String.t(), String.t()}
             | {integer(), map(), String.t()}
             | {integer(), map(), String.t(), map()})
        ) :: no_return()
  def serve(port, options, handler)
      when is_integer(port) and is_map(options) and is_function(handler, 7) do
    serve("127.0.0.1", port, options, handler)
  end

  @spec serve(String.t(), integer(), (String.t(), String.t(), map(), map() -> {integer(), String.t(), String.t()})) ::
          no_return()
  def serve(bind_host, port, handler)
      when is_binary(bind_host) and is_integer(port) and is_function(handler, 4) do
    serve(bind_host, port, @default_options, handler)
  end

  @spec serve(
          String.t(),
          integer(),
          (String.t(), String.t(), map(), map(), map(), map() ->
             {integer(), String.t(), String.t()} | {integer(), map(), String.t()})
        ) :: no_return()
  def serve(bind_host, port, handler)
      when is_binary(bind_host) and is_integer(port) and is_function(handler, 6) do
    serve(bind_host, port, @default_options, handler)
  end

  @spec serve(
          String.t(),
          integer(),
          (String.t(), String.t(), map(), map(), map(), map(), map() ->
             {integer(), String.t(), String.t()}
             | {integer(), map(), String.t()}
             | {integer(), map(), String.t(), map()})
        ) :: no_return()
  def serve(bind_host, port, handler)
      when is_binary(bind_host) and is_integer(port) and is_function(handler, 7) do
    serve(bind_host, port, @default_options, handler)
  end

  @spec serve(String.t(), integer(), map(), (String.t(), String.t(), map(), map() -> {integer(), String.t(), String.t()})) ::
          no_return()
  def serve(bind_host, port, options, handler)
      when is_binary(bind_host) and is_integer(port) and is_map(options) and is_function(handler, 4) do
    if port <= 0 or port > 65_535 do
      raise Cairn.RuntimeError, "HTTP_SERVE expects a port in 1..65535, got #{inspect(port)}"
    end

    ip = resolve_bind_ip!(bind_host)
    options = normalize_options!(options)

    {:ok, listener} =
      case :gen_tcp.listen(port, Keyword.put(@listen_opts, :ip, ip)) do
        {:ok, socket} -> {:ok, socket}
        {:error, reason} ->
          raise Cairn.RuntimeError,
            "HTTP_SERVE: cannot listen on #{bind_host}:#{port}: #{inspect(reason)}"
      end

    serve_loop(listener, handler, options)
  end

  @spec serve(
          String.t(),
          integer(),
          map(),
          (String.t(), String.t(), map(), map(), map(), map() ->
             {integer(), String.t(), String.t()} | {integer(), map(), String.t()})
        ) :: no_return()
  def serve(bind_host, port, options, handler)
      when is_binary(bind_host) and is_integer(port) and is_map(options) and is_function(handler, 6) do
    if port <= 0 or port > 65_535 do
      raise Cairn.RuntimeError, "HTTP_SERVE expects a port in 1..65535, got #{inspect(port)}"
    end

    ip = resolve_bind_ip!(bind_host)
    options = normalize_options!(options)

    {:ok, listener} =
      case :gen_tcp.listen(port, Keyword.put(@listen_opts, :ip, ip)) do
        {:ok, socket} -> {:ok, socket}
        {:error, reason} ->
          raise Cairn.RuntimeError,
            "HTTP_SERVE: cannot listen on #{bind_host}:#{port}: #{inspect(reason)}"
      end

    serve_loop(listener, handler, options)
  end

  @spec serve(
          String.t(),
          integer(),
          map(),
          (String.t(), String.t(), map(), map(), map(), map(), map() ->
             {integer(), String.t(), String.t()}
             | {integer(), map(), String.t()}
             | {integer(), map(), String.t(), map()})
        ) :: no_return()
  def serve(bind_host, port, options, handler)
      when is_binary(bind_host) and is_integer(port) and is_map(options) and is_function(handler, 7) do
    if port <= 0 or port > 65_535 do
      raise Cairn.RuntimeError, "HTTP_SERVE expects a port in 1..65535, got #{inspect(port)}"
    end

    ip = resolve_bind_ip!(bind_host)
    options = normalize_options!(options)

    {:ok, listener} =
      case :gen_tcp.listen(port, Keyword.put(@listen_opts, :ip, ip)) do
        {:ok, socket} -> {:ok, socket}
        {:error, reason} ->
          raise Cairn.RuntimeError,
            "HTTP_SERVE: cannot listen on #{bind_host}:#{port}: #{inspect(reason)}"
      end

    serve_loop(listener, handler, options)
  end

  defp response_for_request(client, options, handler) do
    case read_request(client, options) do
      {:error, :bad_request} ->
        http_response(400, %{"Content-Type" => "text/plain; charset=utf-8"}, "bad request\n")

      {:error, :too_long} ->
        http_response(414, %{"Content-Type" => "text/plain; charset=utf-8"}, "uri too long\n")

      {:error, :payload_too_large} ->
        http_response(413, %{"Content-Type" => "text/plain; charset=utf-8"}, "payload too large\n")

      {:error, :unsupported_media_type} ->
        http_response(415, %{"Content-Type" => "text/plain; charset=utf-8"}, "unsupported media type\n")

      {:error, :timeout} ->
        :close

      {:error, :closed} ->
        :close

      {:error, reason} ->
        raise Cairn.RuntimeError, "HTTP_SERVE: recv failed: #{inspect(reason)}"

      {:ok, method, path, query, form, headers, cookies, session_id, session} ->
        result =
          case :erlang.fun_info(handler, :arity) do
            {:arity, 4} -> handler.(method, path, query, form)
            {:arity, 6} -> handler.(method, path, query, form, headers, cookies)
            {:arity, 7} -> handler.(method, path, query, form, headers, cookies, session)
          end

        case normalize_handler_response(result) do
          {:ok, status, response_headers, body, session_result} ->
            response_headers = apply_session_headers(response_headers, session_id, session_result)
            http_response(status, response_headers, body)

          {:error, other} ->
            raise Cairn.RuntimeError,
              "HTTP_SERVE handler must return {status_int, content_type_str, body_str}, {status_int, headers_map, body_str}, or a session-aware 4-tuple, got #{inspect(other)}"
        end
    end
  end

  defp normalize_handler_response({status, content_type, body})
       when is_integer(status) and is_binary(content_type) and is_binary(body) do
    {:ok, status, %{"Content-Type" => content_type}, body, :unchanged}
  end

  defp normalize_handler_response({status, headers, body})
       when is_integer(status) and is_map(headers) and is_binary(body) do
    if Enum.all?(headers, fn {name, value} -> is_binary(name) and is_binary(value) end) do
      {:ok, status, headers, body, :unchanged}
    else
      {:error, {status, headers, body}}
    end
  end

  defp normalize_handler_response({status, headers, body, session})
       when is_integer(status) and is_map(headers) and is_binary(body) and is_map(session) do
    if Enum.all?(headers, fn {name, value} -> is_binary(name) and is_binary(value) end) and
         Enum.all?(session, fn {key, value} -> is_binary(key) and is_binary(value) end) do
      {:ok, status, headers, body, session}
    else
      {:error, {status, headers, body, session}}
    end
  end

  defp normalize_handler_response(other), do: {:error, other}

  defp apply_session_headers(headers, _session_id, :unchanged), do: headers

  defp apply_session_headers(headers, session_id, session) when is_map(session) do
    cond do
      map_size(session) == 0 and is_binary(session_id) ->
        SessionStore.delete(session_id)
        Map.put(headers, "Set-Cookie", clear_session_cookie())

      map_size(session) == 0 ->
        headers

      true ->
        id = session_id || SessionStore.new_id()
        SessionStore.save(id, session)
        Map.put(headers, "Set-Cookie", session_cookie(id))
    end
  end

  defp parse_request_line(line) do
    case String.split(line, " ", parts: 3) do
      [method, target | _] ->
        {path, query} = parse_request_target(target)
        {method, path, query}

      _ ->
        {:invalid, :invalid}
    end
  end

  defp parse_request_target(target) do
    case String.split(target, "?", parts: 2) do
      [path] ->
        {path, %{}}

      [path, raw_query] ->
        {path, parse_query(raw_query)}
    end
  end

  defp parse_query(""), do: %{}

  defp parse_query(raw_query) do
    raw_query
    |> String.split("&", trim: true)
    |> Enum.reduce(%{}, fn pair, acc ->
      case String.split(pair, "=", parts: 2) do
        [raw_key, raw_value] ->
          Map.put(acc, URI.decode_www_form(raw_key), URI.decode_www_form(raw_value))

        [raw_key] ->
          Map.put(acc, URI.decode_www_form(raw_key), "")

        _ ->
          acc
      end
    end)
  end

  defp http_response(status, headers, body) do
    headers =
      headers
      |> Map.put_new("Content-Type", "text/plain; charset=utf-8")
      |> Map.put("Content-Length", Integer.to_string(byte_size(body)))
      |> Map.put("Connection", "close")

    header_lines =
      headers
      |> Enum.map(fn {name, value} -> [name, ": ", value, "\r\n"] end)

    ["HTTP/1.1 ", status_line(status), "\r\n", header_lines, "\r\n", body]
    |> IO.iodata_to_binary()
  end

  defp status_line(200), do: "200 OK"
  defp status_line(400), do: "400 Bad Request"
  defp status_line(401), do: "401 Unauthorized"
  defp status_line(403), do: "403 Forbidden"
  defp status_line(413), do: "413 Payload Too Large"
  defp status_line(415), do: "415 Unsupported Media Type"
  defp status_line(405), do: "405 Method Not Allowed"
  defp status_line(404), do: "404 Not Found"
  defp status_line(414), do: "414 URI Too Long"
  defp status_line(status), do: Integer.to_string(status) <> " OK"

  defp resolve_bind_ip!(bind_host) do
    case :inet.parse_address(String.to_charlist(bind_host)) do
      {:ok, ip} -> ip
      {:error, _reason} -> raise Cairn.RuntimeError, "HTTP_SERVE: bind address must be an IPv4/IPv6 literal, got #{inspect(bind_host)}"
    end
  end

  defp serve_loop(listener, handler, options) do
    {:ok, client} =
      case :gen_tcp.accept(listener) do
        {:ok, socket} -> {:ok, socket}
        {:error, reason} -> raise Cairn.RuntimeError, "HTTP_SERVE: accept failed: #{inspect(reason)}"
      end

    worker =
      spawn(fn ->
        receive do
          {:serve, socket} -> handle_client(socket, handler, options)
        end
      end)

    :ok = :gen_tcp.controlling_process(client, worker)
    send(worker, {:serve, client})

    serve_loop(listener, handler, options)
  end

  defp handle_client(client, handler, options) do
    try do
      case response_for_request(client, options, handler) do
        response when is_binary(response) ->
          :ok = :gen_tcp.send(client, response)

        :close ->
          :ok
      end
    after
      :gen_tcp.close(client)
    end
  end

  defp read_request(client, options) do
    with {:ok, head_block, remainder} <-
           read_until_header_terminator(
             client,
             options["request_line_max"],
             options["read_timeout_ms"]
           ),
         {:ok, method, path, query, headers} <- parse_request_head(head_block),
         {:ok, form} <-
           read_form_body(
             client,
             remainder,
             method,
             headers,
             options["body_max"],
             options["read_timeout_ms"]
           ) do
      cookies = parse_cookies(headers)
      {session_id, session} = load_session(cookies)
      {:ok, method, path, query, form, headers, cookies, session_id, session}
    end
  end

  defp parse_cookies(headers) do
    case Map.get(headers, "cookie") do
      nil ->
        %{}

      raw_cookie ->
        raw_cookie
        |> String.split(";", trim: true)
        |> Enum.reduce(%{}, fn pair, acc ->
          case String.split(pair, "=", parts: 2) do
            [raw_key, raw_value] ->
              Map.put(acc, String.trim(raw_key), URI.decode_www_form(String.trim(raw_value)))

            [raw_key] ->
              Map.put(acc, String.trim(raw_key), "")

            _ ->
              acc
          end
        end)
    end
  end

  defp load_session(cookies) do
    case Map.get(cookies, SessionStore.cookie_name()) do
      nil ->
        {nil, %{}}

      session_id ->
        case SessionStore.load(session_id) do
          {:ok, session} -> {session_id, session}
          :error -> {nil, %{}}
        end
    end
  end

  defp session_cookie(session_id) do
    "#{SessionStore.cookie_name()}=#{session_id}; Path=/; HttpOnly; SameSite=Lax"
  end

  defp clear_session_cookie do
    "#{SessionStore.cookie_name()}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax"
  end

  defp read_until_header_terminator(_client, max_bytes, _timeout, acc \\ "")

  defp read_until_header_terminator(_client, max_bytes, _timeout, acc)
       when byte_size(acc) > max_bytes do
    {:error, :too_long}
  end

  defp read_until_header_terminator(client, max_bytes, timeout, acc) do
    case extract_header_block(acc, max_bytes) do
      {:ok, head_block, remainder} ->
        {:ok, head_block, remainder}

      :too_long ->
        {:error, :too_long}

      :continue ->
        case :gen_tcp.recv(client, 0, timeout) do
          {:ok, chunk} ->
            read_until_header_terminator(client, max_bytes, timeout, acc <> chunk)

          {:error, :timeout} ->
            {:error, :timeout}

          {:error, :closed} when acc == "" ->
            {:error, :closed}

          {:error, :closed} ->
            {:error, :bad_request}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp extract_header_block(data, max_bytes) do
    cond do
      String.contains?(data, "\r\n\r\n") ->
        [head_block, remainder] = String.split(data, "\r\n\r\n", parts: 2)

        if byte_size(head_block) <= max_bytes,
          do: {:ok, head_block, remainder},
          else: :too_long

      String.contains?(data, "\n\n") ->
        [head_block, remainder] = String.split(data, "\n\n", parts: 2)

        if byte_size(head_block) <= max_bytes,
          do: {:ok, head_block, remainder},
          else: :too_long

      byte_size(data) > max_bytes ->
        :too_long

      true ->
        :continue
    end
  end

  defp parse_request_head(head_block) do
    lines =
      head_block
      |> String.replace("\r\n", "\n")
      |> String.split("\n")

    case lines do
      [request_line | header_lines] ->
        case parse_request_line(request_line) do
          {:invalid, :invalid} ->
            {:error, :bad_request}

          {method, path, query} ->
            {:ok, method, path, query, parse_headers(header_lines)}
        end

      _ ->
        {:error, :bad_request}
    end
  end

  defp parse_headers(lines) do
    lines
    |> Enum.reject(&(&1 == ""))
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          Map.put(acc, String.downcase(String.trim(name)), String.trim(value))

        _ ->
          acc
      end
    end)
  end

  defp read_form_body(_client, _remainder, method, _headers, _body_max, _timeout)
       when method != "POST" do
    {:ok, %{}}
  end

  defp read_form_body(client, remainder, "POST", headers, body_max, timeout) do
    body_length = content_length(headers)

    cond do
      is_nil(body_length) or body_length == 0 ->
        {:ok, %{}}

      body_length < 0 ->
        {:error, :bad_request}

      body_length > body_max ->
        {:error, :payload_too_large}

      not supported_form_content_type?(headers) ->
        {:error, :unsupported_media_type}

      true ->
        case read_exact_body(client, remainder, body_length, timeout) do
          {:ok, body} ->
            {:ok, parse_query(body)}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp content_length(headers) do
    case Map.get(headers, "content-length") do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {length, ""} -> length
          _ -> -1
        end
    end
  end

  defp supported_form_content_type?(headers) do
    case Map.get(headers, "content-type") do
      nil -> false
      value -> String.starts_with?(String.downcase(value), "application/x-www-form-urlencoded")
    end
  end

  defp read_exact_body(_client, remainder, content_length, _timeout)
       when byte_size(remainder) >= content_length do
    {:ok, binary_part(remainder, 0, content_length)}
  end

  defp read_exact_body(client, remainder, content_length, timeout) do
    missing = content_length - byte_size(remainder)

    case :gen_tcp.recv(client, missing, timeout) do
      {:ok, chunk} ->
        {:ok, remainder <> chunk}

      {:error, :timeout} ->
        {:error, :bad_request}

      {:error, :closed} ->
        {:error, :bad_request}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_options!(options) do
    request_line_max =
      normalize_positive_integer_option!(options, "request_line_max", @default_options["request_line_max"])

    read_timeout_ms =
      normalize_positive_integer_option!(options, "read_timeout_ms", @default_options["read_timeout_ms"])

    body_max =
      normalize_positive_integer_option!(options, "body_max", @default_options["body_max"])

    %{
      "request_line_max" => request_line_max,
      "read_timeout_ms" => read_timeout_ms,
      "body_max" => body_max
    }
  end

  defp normalize_positive_integer_option!(options, key, default) do
    case Map.get(options, key, default) do
      value when is_integer(value) and value > 0 ->
        value

      value ->
        raise Cairn.RuntimeError,
          "HTTP_SERVE option '#{key}' must be a positive integer, got #{inspect(value)}"
    end
  end
end
