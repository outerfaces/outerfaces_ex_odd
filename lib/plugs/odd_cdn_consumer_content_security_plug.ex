defmodule Outerfaces.Odd.Plugs.OddCDNConsumerContentSecurityPlug do
  @moduledoc """
  A plug for setting Content Security Policy headers on responses.
  To configure the CSP, pass a map of key-value pairs to the plug.

  Supports two modes:
  - `use_self_policy: true` - Simple 'self' based policy for unified proxy mode
  - `source_host_options: [...]` - Explicit allowed sources list (default)
  """
  import Plug.Conn
  alias Plug.Conn

  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts \\ []), do: opts

  @spec call(Conn.t(), Keyword.t()) :: Conn.t()
  def call(%Conn{} = conn, opts) when is_list(opts) do
    conn
    |> register_before_send(fn conn ->
      # Use existing nonce if already set (e.g., by serve_index_html), otherwise generate new one
      nonce = conn.assigns[:csp_nonce] || generate_nonce()

      # Check if using simplified 'self' policy for unified proxy mode
      use_self_policy = Keyword.get(opts, :use_self_policy, false)

      csp =
        if use_self_policy do
          build_self_content_security_policy(nonce)
        else
          build_content_security_policy(Keyword.get(opts, :source_host_options, []), nonce)
        end

      # Check if cross-origin isolation is enabled (for AudioWorklet/SharedArrayBuffer)
      enable_cross_origin_isolation = Keyword.get(opts, :enable_cross_origin_isolation, false)

      conn
      |> put_resp_header("content-security-policy", csp)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("x-frame-options", "deny")
      |> put_resp_header(
        "strict-transport-security",
        "max-age=31536000; includeSubDomains; preload"
      )
      |> put_resp_header("referrer-policy", "no-referrer")
      |> maybe_put_cross_origin_isolation_headers(enable_cross_origin_isolation)
      |> assign(:csp_nonce, nonce)
    end)
  end

  @spec maybe_put_cross_origin_isolation_headers(Conn.t(), boolean()) :: Conn.t()
  defp maybe_put_cross_origin_isolation_headers(conn, true) do
    conn
    |> put_resp_header("cross-origin-opener-policy", "same-origin")
    |> put_resp_header("cross-origin-embedder-policy", "require-corp")
  end

  defp maybe_put_cross_origin_isolation_headers(conn, _), do: conn

  # Simple 'self' based policy for unified proxy mode
  # All services are on the same origin, so 'self' covers everything
  @spec build_self_content_security_policy(String.t()) :: String.t()
  defp build_self_content_security_policy(nonce) do
    "base-uri 'self'; block-all-mixed-content;" <>
      " default-src 'self';" <>
      " form-action 'self'; frame-ancestors 'none';" <>
      " img-src 'self' data:;" <>
      " object-src 'none'; script-src 'nonce-#{nonce}' 'self' 'wasm-unsafe-eval';" <>
      " script-src-elem 'nonce-#{nonce}' 'self';" <>
      " style-src 'unsafe-inline' 'self';" <>
      " style-src-elem 'unsafe-inline' 'self';" <>
      " connect-src 'self';"
  end

  @spec build_content_security_policy(
          allowed_sources :: [%{protocol: String.t(), host: String.t(), port: non_neg_integer()}],
          nonce :: String.t()
        ) :: String.t()
  defp build_content_security_policy(allowed_sources, nonce) do
    # Separate HTTP/HTTPS sources from WebSocket sources
    # WebSocket protocols (ws://, wss://) should only be in connect-src
    {http_sources, _ws_sources} =
      allowed_sources
      |> Enum.split_with(fn %{protocol: protocol} ->
        protocol in ["http", "https"]
      end)

    # Format HTTP sources (no leading 'self' - we'll add it per-directive)
    http_sources_formatted =
      http_sources
      |> Enum.map(&build_url/1)
      |> Enum.join(" ")

    # For connect-src, include both HTTP and WebSocket sources
    connect_sources_formatted =
      allowed_sources
      |> Enum.flat_map(&expand_connect_source/1)
      |> Enum.uniq()
      |> Enum.join(" ")

    "base-uri 'self'; block-all-mixed-content;" <>
      " default-src 'self' #{http_sources_formatted};" <>
      " form-action 'self'; frame-ancestors 'none';" <>
      " img-src 'self' data: #{http_sources_formatted};" <>
      " object-src 'none'; script-src 'nonce-#{nonce}' 'self' #{http_sources_formatted};" <>
      " script-src-elem 'nonce-#{nonce}' 'self' #{http_sources_formatted};" <>
      " style-src 'unsafe-inline' 'self' #{http_sources_formatted};" <>
      " style-src-elem 'unsafe-inline' 'self' #{http_sources_formatted};" <>
      " connect-src 'self' #{connect_sources_formatted};"

    # " upgrade-insecure-requests"
  end

  @spec build_url(map()) :: String.t()
  defp build_url(%{protocol: protocol, host: host, port: port}) do
    "#{protocol}://#{host}:#{port}"
  end

  # For connect-src, include websocket equivalents for HTTP(S) sources
  defp expand_connect_source(%{protocol: protocol} = source)
       when protocol in ["http", "https"] do
    ws_protocol = if protocol == "https", do: "wss", else: "ws"

    [
      build_url(source),
      build_url(%{source | protocol: ws_protocol})
    ]
  end

  defp expand_connect_source(source), do: [build_url(source)]

  @spec maybe_inject_nonce(Conn.t()) :: Conn.t()
  def maybe_inject_nonce(%Plug.Conn{request_path: request_path, resp_body: body} = conn) do
    if request_path in ["/", "/index.html"] do
      nonce = conn.assigns[:csp_nonce]

      updated_body =
        body
        |> String.replace("<script", "<script nonce=\"#{nonce}\"")
        |> String.replace("<style", "<style nonce=\"#{nonce}\"")

      Plug.Conn.resp(conn, conn.status, updated_body)
    else
      conn
    end
  end

  @spec generate_nonce() :: String.t()
  def generate_nonce do
    :crypto.strong_rand_bytes(16)
    |> Base.encode64()
    |> binary_part(0, 16)
  end
end
