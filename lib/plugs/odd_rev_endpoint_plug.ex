defmodule Outerfaces.Odd.Plugs.OddRevEndpointPlug do
  @moduledoc """
  Plug that serves the current revision as JSON at `/__outerfaces__/rev.json`.

  This endpoint provides a fast, lightweight way for service workers to check
  the current revision without parsing HTML or fetching bootstrap files.

  ## Usage

  Add to your pipeline before `OddCDNConsumerServeIndex`:

      plug OddRevEndpointPlug

  ## Response Format

      {
        "rev": "abc123def456",
        "schema_version": "1.0"
      }

  ## Cache Headers

  Always returns `Cache-Control: no-store, no-cache, must-revalidate` to ensure
  clients always get the current rev value.
  """

  import Plug.Conn
  require Logger
  alias Outerfaces.Rev

  @behaviour Plug

  @rev_endpoint_path "/__outerfaces__/rev.json"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    if conn.request_path == @rev_endpoint_path do
      serve_rev_json(conn)
    else
      conn
    end
  end

  # Private Functions

  @spec serve_rev_json(Plug.Conn.t()) :: Plug.Conn.t()
  defp serve_rev_json(conn) do
    current_rev = Rev.current_rev()

    response_body =
      Jason.encode!(%{
        rev: current_rev,
        schema_version: "1.0",
        timestamp: System.system_time(:second)
      })

    conn
    |> put_resp_header("content-type", "application/json; charset=utf-8")
    |> put_resp_header("cache-control", "no-store, no-cache, must-revalidate")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
    # CORS headers for service worker access
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET")
    |> put_resp_header("access-control-allow-headers", "Content-Type")
    |> send_resp(200, response_body)
    |> halt()
  end
end
