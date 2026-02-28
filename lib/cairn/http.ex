defmodule Cairn.HTTP do
  @moduledoc """
  Minimal host-backed HTTP helpers for bounded serving primitives.

  The first slice is intentionally narrow: serve one request on localhost,
  then return. This keeps the runtime honest while making the transport path
  testable and usable from a browser.
  """

  @listen_opts [:binary, packet: :raw, active: false, reuseaddr: true]

  @spec serve(integer(), (String.t(), String.t() -> {integer(), String.t(), String.t()})) :: no_return()
  def serve(port, handler) when is_integer(port) and is_function(handler, 2) do
    serve("127.0.0.1", port, handler)
  end

  @spec serve(String.t(), integer(), (String.t(), String.t() -> {integer(), String.t(), String.t()})) ::
          no_return()
  def serve(bind_host, port, handler)
      when is_binary(bind_host) and is_integer(port) and is_function(handler, 2) do
    if port <= 0 or port > 65_535 do
      raise Cairn.RuntimeError, "HTTP_SERVE expects a port in 1..65535, got #{inspect(port)}"
    end

    ip = resolve_bind_ip!(bind_host)

    {:ok, listener} =
      case :gen_tcp.listen(port, Keyword.put(@listen_opts, :ip, ip)) do
        {:ok, socket} -> {:ok, socket}
        {:error, reason} ->
          raise Cairn.RuntimeError,
            "HTTP_SERVE: cannot listen on #{bind_host}:#{port}: #{inspect(reason)}"
      end

    serve_loop(listener, handler)
  end

  defp response_for_request(request, handler) do
    case parse_request_line(request) do
      {:invalid, :invalid} ->
        http_response(400, "text/plain; charset=utf-8", "bad request\n")

      {method, path} ->
        case handler.(method, path) do
          {status, content_type, body}
              when is_integer(status) and is_binary(content_type) and is_binary(body) ->
            http_response(status, content_type, body)

          other ->
            raise Cairn.RuntimeError,
              "HTTP_SERVE handler must return {status_int, content_type_str, body_str}, got #{inspect(other)}"
        end
    end
  end

  defp parse_request_line(request) do
    case String.split(request, "\r\n", parts: 2) do
      [line | _] ->
        case String.split(line, " ", parts: 3) do
          [method, path | _] -> {method, path}
          _ -> {:invalid, :invalid}
        end

      _ ->
        {:invalid, :invalid}
    end
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
  defp status_line(status), do: Integer.to_string(status) <> " OK"

  defp resolve_bind_ip!(bind_host) do
    case :inet.parse_address(String.to_charlist(bind_host)) do
      {:ok, ip} -> ip
      {:error, _reason} -> raise Cairn.RuntimeError, "HTTP_SERVE: bind address must be an IPv4/IPv6 literal, got #{inspect(bind_host)}"
    end
  end

  defp serve_loop(listener, handler) do
    {:ok, client} =
      case :gen_tcp.accept(listener) do
        {:ok, socket} -> {:ok, socket}
        {:error, reason} -> raise Cairn.RuntimeError, "HTTP_SERVE: accept failed: #{inspect(reason)}"
      end

    worker =
      spawn(fn ->
        receive do
          {:serve, socket} -> handle_client(socket, handler)
        end
      end)

    :ok = :gen_tcp.controlling_process(client, worker)
    send(worker, {:serve, client})

    serve_loop(listener, handler)
  end

  defp handle_client(client, handler) do
    try do
      case :gen_tcp.recv(client, 0, 5_000) do
        {:ok, request} ->
          :ok = :gen_tcp.send(client, response_for_request(request, handler))

        {:error, :closed} ->
          :ok

        {:error, reason} ->
          raise Cairn.RuntimeError, "HTTP_SERVE: recv failed: #{inspect(reason)}"
      end
    after
      :gen_tcp.close(client)
    end
  end
end
