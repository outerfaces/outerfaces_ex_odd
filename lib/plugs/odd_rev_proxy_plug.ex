defmodule Outerfaces.Odd.Plugs.OddRevProxyPlug do
  @moduledoc """
  Plug for parsing and validating rev-pinned URLs.

  This plug:
  1. Detects requests to `/__rev/<rev>/<path>` URLs
  2. Validates that `<rev>` matches the current rev
  3. Strips the `/__rev/<rev>` prefix from the path
  4. Sets conn assigns for downstream plugs
  5. Handles rev mismatches (redirect or conflict response)

  ## Configuration

      plug OddRevProxyPlug, mismatch_behavior: :redirect  # or :conflict

  ## Conn Assigns

  - `outerfaces_rev` - The rev value extracted from the URL (if present)
  - `outerfaces_rev_matched` - Boolean indicating if the rev matches current_rev()

  """

  import Plug.Conn
  alias Outerfaces.Rev

  @behaviour Plug

  # Matches: /__rev/<rev>/<namespace>/<path>
  # where namespace is "spa" or "cdn"
  @rev_url_regex ~r{^/__rev/([^/]+)/(spa|cdn)/(.*)$}

  @impl true
  def init(opts) do
    %{
      mismatch_behavior: Keyword.get(opts, :mismatch_behavior, :redirect)
    }
  end

  @impl true
  def call(conn, opts) do
    IO.puts("OddRevProxyPlug: Processing request path #{conn.request_path}")

    case parse_rev_path(conn.request_path) do
      {:ok, rev, namespace, stripped_path} ->
        IO.puts(
          "OddRevProxyPlug: Detected rev #{rev}, namespace #{namespace}, stripped path #{stripped_path}"
        )

        handle_rev_request(conn, rev, namespace, stripped_path, opts)

      :no_rev ->
        # No rev prefix, pass through unchanged
        conn
    end
  end

  # Private Functions

  @spec parse_rev_path(String.t()) :: {:ok, String.t(), String.t(), String.t()} | :no_rev
  defp parse_rev_path(request_path) do
    case Regex.run(@rev_url_regex, request_path) do
      [_full_match, rev, namespace, stripped_path] ->
        {:ok, rev, namespace, "/" <> stripped_path}

      nil ->
        :no_rev
    end
  end

  @spec handle_rev_request(Plug.Conn.t(), String.t(), String.t(), String.t(), map()) ::
          Plug.Conn.t()
  defp handle_rev_request(conn, rev, namespace, stripped_path, opts) do
    current_rev = Rev.current_rev()

    if rev == current_rev do
      # Rev matches - strip prefix and continue
      # Both /spa/ and /cdn/ namespaces are stripped - they're URL routing, not filesystem paths
      conn
      |> Map.put(:request_path, stripped_path)
      |> Map.put(:path_info, path_info_from_path(stripped_path))
      |> assign(:outerfaces_rev, rev)
      |> assign(:outerfaces_rev_namespace, namespace)
      |> assign(:outerfaces_rev_matched, true)
    else
      # Rev mismatch - redirect or return error
      handle_rev_mismatch(conn, rev, current_rev, namespace, stripped_path, opts)
    end
  end

  @spec handle_rev_mismatch(Plug.Conn.t(), String.t(), String.t(), String.t(), String.t(), map()) ::
          Plug.Conn.t()
  defp handle_rev_mismatch(conn, requested_rev, current_rev, namespace, stripped_path, opts) do
    case opts.mismatch_behavior do
      :redirect ->
        # Redirect to current rev (preserve namespace in URL)
        new_location = "/__rev/#{current_rev}/#{namespace}#{stripped_path}"

        conn
        |> put_resp_header("location", new_location)
        |> send_resp(302, "Redirecting to current revision")
        |> halt()

      :conflict ->
        # Return 409 Conflict with details
        body =
          Jason.encode!(%{
            error: "revision_mismatch",
            requested_rev: requested_rev,
            current_rev: current_rev,
            message:
              "The requested revision (#{requested_rev}) does not match the current revision (#{current_rev})"
          })

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(409, body)
        |> halt()
    end
  end

  @spec path_info_from_path(String.t()) :: [String.t()]
  defp path_info_from_path(path) do
    path
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
  end
end
