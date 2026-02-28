defmodule Cairn.HTTP do
  @moduledoc """
  Minimal host-backed HTTP helpers for bounded serving primitives.

  The first slice is intentionally narrow: serve one request on localhost,
  then return. This keeps the runtime honest while making the transport path
  testable and usable from a browser.
  """

  @listen_opts [:binary, packet: :raw, active: false, reuseaddr: true, ip: {127, 0, 0, 1}]

  @spec serve_once(String.t(), integer()) :: :ok
  def serve_once(path, port) when is_binary(path) and is_integer(port) do
    if port <= 0 or port > 65_535 do
      raise Cairn.RuntimeError, "HTTP_SERVE expects a port in 1..65535, got #{inspect(port)}"
    end

    body =
      case File.read(path) do
        {:ok, contents} -> contents
        {:error, reason} -> raise Cairn.RuntimeError, "HTTP_SERVE: cannot read '#{path}': #{reason}"
      end

    {:ok, listener} =
      case :gen_tcp.listen(port, @listen_opts) do
        {:ok, socket} -> {:ok, socket}
        {:error, reason} -> raise Cairn.RuntimeError, "HTTP_SERVE: cannot listen on #{port}: #{inspect(reason)}"
      end

    try do
      {:ok, client} =
        case :gen_tcp.accept(listener) do
          {:ok, socket} -> {:ok, socket}
          {:error, reason} -> raise Cairn.RuntimeError, "HTTP_SERVE: accept failed: #{inspect(reason)}"
        end

      try do
        request =
          case :gen_tcp.recv(client, 0, 5_000) do
            {:ok, data} -> data
            {:error, reason} -> raise Cairn.RuntimeError, "HTTP_SERVE: recv failed: #{inspect(reason)}"
          end

        :ok = :gen_tcp.send(client, response_for_request(request, body))
      after
        :gen_tcp.close(client)
      end
    after
      :gen_tcp.close(listener)
    end

    :ok
  end

  defp response_for_request(request, body) do
    case parse_request_line(request) do
      {"GET", "/"} ->
        http_response("200 OK", "text/html; charset=utf-8", body)

      _ ->
        http_response("404 Not Found", "text/plain; charset=utf-8", "not found\n")
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
      status,
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
end
