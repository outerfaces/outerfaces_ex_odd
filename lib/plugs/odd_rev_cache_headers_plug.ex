defmodule Outerfaces.Odd.Plugs.OddRevCacheHeadersPlug do
  @moduledoc """
  Plug for setting cache headers based on rev-pinned URL matching.

  This plug sets appropriate cache headers:
  - For rev-pinned assets (rev matched + asset type): `Cache-Control: public, max-age=31536000, immutable`
  - For bootstrap/non-rev/index HTML: `Cache-Control: no-store, no-cache, must-revalidate`

  The plug uses `register_before_send/2` to set headers right before the response is sent,
  allowing other plugs to modify the response first.

  **Important:** Index HTML is NEVER cached immutably, even if rev-matched, to ensure
  users always get the latest bootstrap code.

  ## Configuration

      plug OddRevCacheHeadersPlug

  ## Requires

  This plug should be placed AFTER `OddRevProxyPlug` in the pipeline, as it relies on
  the `conn.assigns.outerfaces_rev_matched` value set by that plug.

  The ServeIndex plug should set `conn.assigns.outerfaces_served_index = true` when
  serving index HTML to prevent immutable caching.

  """

  import Plug.Conn

  @behaviour Plug

  @immutable_cache_control "public, max-age=31536000, immutable"
  @no_cache_control "no-store, no-cache, must-revalidate"

  # Asset-like content types that can be cached immutably
  @cacheable_content_types [
    "application/javascript",
    "text/javascript",
    "application/x-javascript",
    "text/css",
    "application/wasm",
    "image/",
    "font/",
    "application/font",
    "video/",
    "audio/"
  ]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    register_before_send(conn, &set_cache_headers/1)
  end

  # Private Functions

  @spec set_cache_headers(Plug.Conn.t()) :: Plug.Conn.t()
  defp set_cache_headers(conn) do
    # Check if this is an index HTML response
    served_index = Map.get(conn.assigns, :outerfaces_served_index, false)

    # Check if rev matched
    rev_matched = Map.get(conn.assigns, :outerfaces_rev_matched, false)

    # Get content-type
    content_type = get_content_type(conn)

    # Check if existing cache-control header is set
    existing_cache_control = get_resp_header(conn, "cache-control")

    cond do
      # Never cache index HTML immutably (always use bootstrap headers)
      served_index ->
        put_resp_header(conn, "cache-control", @no_cache_control)

      # Never cache HTML immutably (even if rev-matched)
      is_html?(content_type) ->
        put_resp_header(conn, "cache-control", @no_cache_control)

      # Rev matched + asset-like content → immutable
      rev_matched && is_cacheable_asset?(content_type) ->
        put_resp_header(conn, "cache-control", @immutable_cache_control)

      # Rev matched but not an asset (unknown content type) → be conservative, use no-cache
      rev_matched ->
        put_resp_header(conn, "cache-control", @no_cache_control)

      # No rev match → bootstrap headers (only if not already set)
      existing_cache_control == [] ->
        put_resp_header(conn, "cache-control", @no_cache_control)

      # Cache control already set by upstream → don't override
      true ->
        conn
    end
  end

  @spec get_content_type(Plug.Conn.t()) :: String.t() | nil
  defp get_content_type(conn) do
    case get_resp_header(conn, "content-type") do
      [content_type | _] -> content_type
      [] -> nil
    end
  end

  @spec is_html?(String.t() | nil) :: boolean()
  defp is_html?(nil), do: false
  defp is_html?(content_type), do: String.contains?(content_type, "text/html")

  @spec is_cacheable_asset?(String.t() | nil) :: boolean()
  defp is_cacheable_asset?(nil), do: false

  defp is_cacheable_asset?(content_type) do
    Enum.any?(@cacheable_content_types, &String.contains?(content_type, &1))
  end
end
