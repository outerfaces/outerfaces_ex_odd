defmodule Outerfaces.Odd.Plugs.OddRevCacheHeadersPlug do
  @moduledoc """
  Plug for setting cache headers based on rev-pinned URL matching.

  This plug sets appropriate cache headers:
  - For rev-pinned assets (rev matched): `Cache-Control: public, max-age=31536000, immutable`
  - For bootstrap/non-rev assets: `Cache-Control: no-store, no-cache, must-revalidate`

  The plug uses `register_before_send/2` to set headers right before the response is sent,
  allowing other plugs to modify the response first.

  ## Configuration

      plug OddRevCacheHeadersPlug

  ## Requires

  This plug should be placed AFTER `OddRevProxyPlug` in the pipeline, as it relies on
  the `conn.assigns.outerfaces_rev_matched` value set by that plug.

  """

  import Plug.Conn

  @behaviour Plug

  @immutable_cache_control "public, max-age=31536000, immutable"
  @no_cache_control "no-store, no-cache, must-revalidate"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    register_before_send(conn, &set_cache_headers/1)
  end

  # Private Functions

  @spec set_cache_headers(Plug.Conn.t()) :: Plug.Conn.t()
  defp set_cache_headers(conn) do
    cache_control =
      if Map.get(conn.assigns, :outerfaces_rev_matched, false) do
        @immutable_cache_control
      else
        @no_cache_control
      end

    put_resp_header(conn, "cache-control", cache_control)
  end
end
