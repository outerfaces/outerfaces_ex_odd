defmodule Outerfaces.Odd.Plugs.OddCDNConsumerServeIndex do
  @moduledoc """
  ServeIndex plug to handle both static asset requests and index.html fallback.
  Handles CDN consumer requests.
  """

  import Plug.Conn

  alias Outerfaces.Odd.Plugs.OddCDNRoflJSPlug, as: ModifyCDNJSFiles
  alias Outerfaces.Odd.Plugs.OddCDNRoflCSSPlug, as: ModifyCDNCSSFiles
  alias Outerfaces.Odd.Plugs.OddCDNRoflHTMLPlug, as: ModifyCDNHTMLFiles

  @behaviour Plug

  @impl true
  def init(opts) do
    %{
      index_path: Keyword.get(opts, :index_path, "priv/static/index.html"),
      static_root: Keyword.get(opts, :static_root, "priv/static"),
      static_patterns: Keyword.get(opts, :static_patterns, default_static_patterns())
    }
  end

  @impl true
  def call(conn, %{
        index_path: index_path,
        static_root: static_root,
        static_patterns: static_patterns
      }) do
    request_path = conn.request_path

    cond do
      static_asset_request?(request_path, static_patterns) ->
        serve_static_asset(conn, static_root, request_path)

      true ->
        serve_index_html(conn, index_path)
    end
  end

  defp serve_static_asset(conn, static_root, request_path) do
    relative_request_path = String.trim_leading(request_path, "/")
    full_path = Path.expand(Path.join(static_root, relative_request_path))

    if File.exists?(full_path) and not File.dir?(full_path) do
      mime_type = MIME.from_path(full_path) || "application/octet-stream"

      conn
      |> put_resp_content_type(mime_type)
      |> then(fn conn ->
        # Determine if file needs transformation using already-computed mime_type
        is_javascript = String.contains?(mime_type, "javascript")
        is_css = String.contains?(mime_type, "css")
        is_html = String.contains?(mime_type, "html")

        is_rofl_js_file = String.contains?(full_path, ".rofl.js")
        is_rofl_css_file = String.contains?(full_path, ".rofl.css")
        is_rofl_html_file = String.contains?(full_path, ".rofl.html")

        # Build CDN origin for rev-pinned transformations
        # For unified proxy mode (CDN and UI on same port): use empty string
        # For direct CDN mode (separate CDN port): use full origin
        cdn_origin =
          case Map.get(conn.assigns, :cdn_port) do
            # If cdn_port assign exists and differs from UI port, use full origin
            cdn_port when is_integer(cdn_port) and cdn_port != conn.port ->
              protocol = if conn.scheme == :https, do: "https", else: "http"
              cdn_host = conn.host || "localhost"
              "#{protocol}://#{cdn_host}:#{cdn_port}"

            # Otherwise (unified mode or no separate CDN), use empty string for relative URLs
            _ ->
              ""
          end

        cond do
          is_javascript and is_rofl_js_file ->
            # Transform .rofl.js files using new conn-aware function
            with {:ok, content} <- File.read(full_path),
                 modified_file <-
                   ModifyCDNJSFiles.transform_javascript_with_conn(
                     content,
                     conn,
                     cdn_origin
                   ) do
              conn
              |> send_resp(200, modified_file)
            else
              _ ->
                conn
                |> send_file(200, full_path)
            end

          is_css and is_rofl_css_file ->
            # Transform .rofl.css files using new conn-aware function
            with {:ok, content} <- File.read(full_path),
                 modified_file <-
                   ModifyCDNCSSFiles.transform_css_with_conn(
                     content,
                     conn,
                     cdn_origin
                   ) do
              conn
              |> send_resp(200, modified_file)
            else
              _ ->
                conn
                |> send_file(200, full_path)
            end

          is_html and is_rofl_html_file ->
            # Transform .rofl.html files using HTML transformation
            with {:ok, content} <- File.read(full_path),
                 modified_file <-
                   ModifyCDNHTMLFiles.transform_html_cdn_tokens(
                     content,
                     conn,
                     cdn_origin
                   ) do
              conn
              |> send_resp(200, modified_file)
            else
              _ ->
                conn
                |> send_file(200, full_path)
            end

          true ->
            # No transformation needed
            conn
            |> send_file(200, full_path)
        end
      end)
      |> halt()
    else
      send_resp(conn, 404, "File not found")
      |> halt()
    end
  end

  defp serve_index_html(conn, index_path) do
    # Build CDN origin for rev-pinned transformations
    # For unified proxy mode (CDN and UI on same port): use empty string
    # For direct CDN mode (separate CDN port): use full origin
    cdn_origin =
      case Map.get(conn.assigns, :cdn_port) do
        # If cdn_port assign exists and differs from UI port, use full origin
        cdn_port when is_integer(cdn_port) and cdn_port != conn.port ->
          protocol = if conn.scheme == :https, do: "https", else: "http"
          cdn_host = conn.host || "localhost"
          "#{protocol}://#{cdn_host}:#{cdn_port}"

        # Otherwise (unified mode or no separate CDN), use empty string for relative URLs
        _ ->
          ""
      end

    cond do
      File.exists?(index_path) ->
        # Check if this is a .rofl.html file that needs transformation
        if String.ends_with?(index_path, ".rofl.html") do
          with {:ok, content} <- File.read(index_path),
               modified_file <-
                 ModifyCDNHTMLFiles.transform_html_cdn_tokens(
                   content,
                   conn,
                   cdn_origin
                 ) do
            conn
            |> assign(:outerfaces_served_index, true)
            |> put_resp_content_type("text/html")
            |> send_resp(200, modified_file)
            |> halt()
          else
            _ ->
              send_resp(conn, 500, "Failed to transform index.rofl.html")
              |> halt()
          end
        else
          # Regular .html file, serve as-is
          conn
          |> assign(:outerfaces_served_index, true)
          |> put_resp_content_type("text/html")
          |> send_file(200, index_path)
          |> halt()
        end

      true ->
        send_resp(conn, 404, "index.html not found")
        |> halt()
    end
  end

  defp static_asset_request?(request_path, patterns) do
    Enum.any?(patterns, &Regex.match?(&1, request_path))
  end

  defp default_static_patterns do
    [
      # Directory patterns
      ~r{^/assets/},
      ~r{^/js/},
      ~r{^/css/},
      ~r{^/images/},
      ~r{^/fonts/},
      # JavaScript
      ~r{\.js$},
      ~r{\.mjs$},
      # CSS
      ~r{\.css$},
      # Images
      ~r{\.png$},
      ~r{\.jpg$},
      ~r{\.jpeg$},
      ~r{\.gif$},
      ~r{\.svg$},
      ~r{\.webp$},
      ~r{\.ico$},
      # Fonts
      ~r{\.woff$},
      ~r{\.woff2$},
      ~r{\.ttf$},
      ~r{\.otf$},
      ~r{\.eot$},
      # WebAssembly
      ~r{\.wasm$},
      # Source maps
      ~r{\.map$},
      # Data formats
      ~r{\.json$},
      ~r{\.xml$},
      ~r{\.txt$},
      # Audio/Video (if serving media assets)
      ~r{\.mp3$},
      ~r{\.mp4$},
      ~r{\.wav$},
      ~r{\.webm$}
    ]
  end
end
