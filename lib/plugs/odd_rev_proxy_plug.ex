defmodule Outerfaces.Odd.Plugs.OddRevProxyPlug do
  @moduledoc """
  Plug for parsing and validating rev-pinned URLs.

  This plug:
  1. Detects requests to `/__rev/<rev>/<namespace>/<path>` URLs
  2. Validates that `<rev>` matches the current rev
  3. Strips the `/__rev/<rev>` prefix from the path
  4. Sets conn assigns for downstream plugs
  5. Handles rev mismatches (redirect navigations, 409 for assets)

  ## Configuration

      plug OddRevProxyPlug, mismatch_behavior: :redirect  # or :conflict

  ## Conn Assigns

  - `outerfaces_rev` - The rev value extracted from the URL (if present)
  - `outerfaces_rev_namespace` - The namespace (spa, cdn, apps, etc.)
  - `outerfaces_rev_matched` - Boolean indicating if the rev matches current_rev()
  - `outerfaces_rev_current` - The current rev value (set on mismatch)

  """

  import Plug.Conn
  require Logger
  alias Outerfaces.Rev

  @behaviour Plug

  # Matches: /__rev/<rev>/<namespace>/<path>
  # where namespace can be any segment (spa, cdn, apps, etc.)
  # Optionally validate namespace against allowlist if needed
  @rev_url_regex ~r{^/__rev/([^/]+)/([^/]+)/(.*)$}

  # Valid namespaces - can be expanded as needed
  @valid_namespaces ["spa", "cdn", "apps"]

  @impl true
  def init(opts) do
    %{
      mismatch_behavior: Keyword.get(opts, :mismatch_behavior, :redirect)
    }
  end

  @impl true
  def call(conn, opts) do
    Logger.debug("OddRevProxyPlug: Processing request path #{conn.request_path}")

    case parse_rev_path(conn.request_path) do
      {:ok, rev, namespace, stripped_path} ->
        Logger.debug(
          "OddRevProxyPlug: Detected rev #{rev}, namespace #{namespace}, stripped path #{stripped_path}"
        )

        # Optionally validate namespace
        if namespace in @valid_namespaces do
          handle_rev_request(conn, rev, namespace, stripped_path, opts)
        else
          Logger.warning("OddRevProxyPlug: Unknown namespace '#{namespace}', allowing it")
          handle_rev_request(conn, rev, namespace, stripped_path, opts)
        end

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
      # Namespaces are stripped - they're URL routing, not filesystem paths
      %{conn | request_path: stripped_path, path_info: path_info_from_path(stripped_path)}
      |> assign(:outerfaces_rev, rev)
      |> assign(:outerfaces_rev_namespace, namespace)
      |> assign(:outerfaces_rev_matched, true)
      |> assign(:outerfaces_rev_current, current_rev)
    else
      # Rev mismatch - redirect or return error
      handle_rev_mismatch(conn, rev, current_rev, namespace, stripped_path, opts)
    end
  end

  @spec handle_rev_mismatch(Plug.Conn.t(), String.t(), String.t(), String.t(), String.t(), map()) ::
          Plug.Conn.t()
  defp handle_rev_mismatch(conn, requested_rev, current_rev, namespace, _stripped_path, opts) do
    # Set assigns for observability even on mismatch
    conn =
      conn
      |> assign(:outerfaces_rev, requested_rev)
      |> assign(:outerfaces_rev_namespace, namespace)
      |> assign(:outerfaces_rev_matched, false)
      |> assign(:outerfaces_rev_current, current_rev)

    # Determine if this is a navigation request or an asset/module fetch
    is_nav = is_navigation?(conn)

    case opts.mismatch_behavior do
      :redirect ->
        if is_nav do
          # Navigation: redirect to root to get current rev
          Logger.info(
            "OddRevProxyPlug: Navigation rev mismatch (#{requested_rev} != #{current_rev}), redirecting to /"
          )

          conn
          |> put_resp_header("location", "/")
          |> send_resp(302, "Redirecting to current revision")
          |> halt()
        else
          # Asset/module: return 409 for service worker to handle
          Logger.info(
            "OddRevProxyPlug: Asset rev mismatch (#{requested_rev} != #{current_rev}), returning 409"
          )

          body =
            Jason.encode!(%{
              error: "revision_mismatch",
              requested_rev: requested_rev,
              current_rev: current_rev,
              message:
                "The requested revision (#{requested_rev}) does not match the current revision (#{current_rev})"
            })

          conn
          |> put_resp_header("x-outerfaces-rev-mismatch", "true")
          |> put_resp_content_type("application/json")
          |> send_resp(409, body)
          |> halt()
        end

      :conflict ->
        # Always return 409 Conflict with details (regardless of request type)
        body =
          Jason.encode!(%{
            error: "revision_mismatch",
            requested_rev: requested_rev,
            current_rev: current_rev,
            message:
              "The requested revision (#{requested_rev}) does not match the current revision (#{current_rev})"
          })

        conn
        |> put_resp_header("x-outerfaces-rev-mismatch", "true")
        |> put_resp_content_type("application/json")
        |> send_resp(409, body)
        |> halt()
    end
  end

  # Detect navigation requests vs asset/module fetches
  # Uses Sec-Fetch-Mode header (modern browsers) and Accept header fallback
  @spec is_navigation?(Plug.Conn.t()) :: boolean()
  defp is_navigation?(conn) do
    # Check Sec-Fetch-Mode header (Fetch Metadata standard)
    sec_fetch_mode = get_req_header(conn, "sec-fetch-mode") |> List.first()

    # Check Accept header for HTML preference
    accept = get_req_header(conn, "accept") |> List.first()

    cond do
      # Sec-Fetch-Mode: navigate indicates a navigation request
      sec_fetch_mode == "navigate" -> true
      # Accept: text/html (and not also accepting */* with higher priority) suggests navigation
      accept && String.contains?(accept, "text/html") -> true
      # Default to false (assume asset/module fetch)
      true -> false
    end
  end

  @spec path_info_from_path(String.t()) :: [String.t()]
  defp path_info_from_path(path) do
    path
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
  end
end
