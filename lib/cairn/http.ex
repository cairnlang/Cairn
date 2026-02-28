defmodule Cairn.HTTP do
  @moduledoc """
  Minimal host-backed HTTP helpers for bounded serving primitives.

  The current slice stays intentionally narrow:
  - one long-lived listener
  - one lightweight worker per connection
  - minimal request-line parsing (`method`, `path`, `query`)
  - simple response framing

  This keeps the transport boundary honest while letting Cairn own routing and
  response decisions.
  """

  @listen_opts [:binary, packet: :raw, active: false, reuseaddr: true]
  @default_options %{
    "request_line_max" => 4096,
    "read_timeout_ms" => 5000
  }

  @spec serve(integer(), (String.t(), String.t(), map() -> {integer(), String.t(), String.t()})) ::
          no_return()
  def serve(port, handler) when is_integer(port) and is_function(handler, 3) do
    serve("127.0.0.1", port, @default_options, handler)
  end

  @spec serve(integer(), map(), (String.t(), String.t(), map() -> {integer(), String.t(), String.t()})) ::
          no_return()
  def serve(port, options, handler)
      when is_integer(port) and is_map(options) and is_function(handler, 3) do
    serve("127.0.0.1", port, options, handler)
  end

  @spec serve(String.t(), integer(), (String.t(), String.t(), map() -> {integer(), String.t(), String.t()})) ::
          no_return()
  def serve(bind_host, port, handler)
      when is_binary(bind_host) and is_integer(port) and is_function(handler, 3) do
    serve(bind_host, port, @default_options, handler)
  end

  @spec serve(String.t(), integer(), map(), (String.t(), String.t(), map() -> {integer(), String.t(), String.t()})) ::
          no_return()
  def serve(bind_host, port, options, handler)
      when is_binary(bind_host) and is_integer(port) and is_map(options) and is_function(handler, 3) do
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

  defp response_for_request(line, handler) do
    case parse_request_line(line) do
      {:invalid, :invalid} ->
        http_response(400, "text/plain; charset=utf-8", "bad request\n")

      {method, path, query} ->
        case handler.(method, path, query) do
          {status, content_type, body}
              when is_integer(status) and is_binary(content_type) and is_binary(body) ->
            http_response(status, content_type, body)

          other ->
            raise Cairn.RuntimeError,
              "HTTP_SERVE handler must return {status_int, content_type_str, body_str}, got #{inspect(other)}"
        end
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

  defp http_response(status, content_type, body) do
    [
      "HTTP/1.1 ",
      status_line(status),
      "\r\n",
      "Content-Type: ",
      content_type,
      "\r\n",
      "Content-Length: ",
      Integer.to_string(byte_size(body)),
      "\r\n",
      "Connection: close\r\n\r\n",
      body
    ]
    |> IO.iodata_to_binary()
  end

  defp status_line(200), do: "200 OK"
  defp status_line(400), do: "400 Bad Request"
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
      case read_request_line(client, options["request_line_max"], options["read_timeout_ms"]) do
        {:ok, line} ->
          :ok = :gen_tcp.send(client, response_for_request(line, handler))

        {:error, :too_long} ->
          :ok = :gen_tcp.send(client, http_response(414, "text/plain; charset=utf-8", "uri too long\n"))

        {:error, :timeout} ->
          :ok

        {:error, :bad_request} ->
          :ok = :gen_tcp.send(client, http_response(400, "text/plain; charset=utf-8", "bad request\n"))

        {:error, :closed} ->
          :ok

        {:error, reason} ->
          raise Cairn.RuntimeError, "HTTP_SERVE: recv failed: #{inspect(reason)}"
      end
    after
      :gen_tcp.close(client)
    end
  end

  defp read_request_line(_client, max_bytes, _timeout, acc \\ "")

  defp read_request_line(_client, max_bytes, _timeout, acc) when byte_size(acc) > max_bytes do
    {:error, :too_long}
  end

  defp read_request_line(client, max_bytes, timeout, acc) do
    case extract_request_line(acc, max_bytes) do
      {:ok, line} ->
        {:ok, line}

      :too_long ->
        {:error, :too_long}

      :continue ->
        case :gen_tcp.recv(client, 0, timeout) do
          {:ok, chunk} ->
            read_request_line(client, max_bytes, timeout, acc <> chunk)

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

  defp extract_request_line(data, max_bytes) do
    case String.split(data, "\r\n", parts: 2) do
      [line, _rest] ->
        if byte_size(line) <= max_bytes, do: {:ok, line}, else: :too_long

      [^data] ->
        case String.split(data, "\n", parts: 2) do
          [line, _rest] ->
            if byte_size(line) <= max_bytes, do: {:ok, String.trim_trailing(line, "\r")}, else: :too_long

          [_partial] ->
            if byte_size(data) > max_bytes, do: :too_long, else: :continue
        end
    end
  end

  defp normalize_options!(options) do
    request_line_max =
      normalize_positive_integer_option!(options, "request_line_max", @default_options["request_line_max"])

    read_timeout_ms =
      normalize_positive_integer_option!(options, "read_timeout_ms", @default_options["read_timeout_ms"])

    %{
      "request_line_max" => request_line_max,
      "read_timeout_ms" => read_timeout_ms
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
