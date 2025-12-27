defmodule Outerfaces.Odd.Plugs.OddCDNProviderContentSecurityPlug do
  @moduledoc """
  A plug for setting Content Security Policy headers on responses.

  """
  import Plug.Conn
  alias Plug.Conn

  # upgrade-insecure-requests"
  @hardcoded_csp "base-uri 'self'; block-all-mixed-content; default-src 'self';" <>
                   " form-action 'self'; frame-ancestors 'none'; img-src 'self';" <>
                   " object-src 'none'; script-src 'self';" <>
                   " style-src 'self' 'unsafe-inline';"

  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts \\ []), do: opts

  @spec call(Conn.t(), Keyword.t()) :: Conn.t()
  def call(%Conn{} = conn, opts) do
    origin_applications =
      Keyword.get(opts, :origin_applications, [])
      |> Enum.flat_map(&build_origin_list_for_application/1)

    conn
    |> register_before_send(fn conn ->
      # nonce = generate_nonce()

      origin = get_req_header(conn, "origin") |> List.first()

      conn =
        if origin in origin_applications do
          put_resp_header(conn, "access-control-allow-origin", origin)
        else
          conn
        end

      conn
      |> put_resp_header("content-security-policy", @hardcoded_csp)
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("x-frame-options", "deny")
      |> put_resp_header(
        "strict-transport-security",
        "max-age=31536000; includeSubDomains; preload"
      )
      |> put_resp_header("referrer-policy", "no-referrer")
      |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
      |> put_resp_header("access-control-allow-headers", "Content-Type, Authorization")
      |> put_resp_header("cross-origin-resource-policy", "cross-origin")

      # |> assign(:csp_nonce, nonce)
      # |> maybe_inject_nonce()
    end)
  end

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

  @spec build_origin_list_for_application(%{
          protocol: String.t(),
          host: String.t(),
          port: non_neg_integer()
        }) :: [String.t()]
  def build_origin_list_for_application(%{protocol: protocol, host: host, port: port}) do
    [
      "#{protocol}://localhost:#{port}",
      "#{protocol}://#{host}:#{port}"
    ]
  end
end
