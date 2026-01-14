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
    static_root = Keyword.get(opts, :static_root, "priv/static")
    root = Path.expand(static_root)
    index_path = Keyword.get(opts, :index_path, Path.join(root, "index.html")) |> Path.expand()

    %{
      index_path: index_path,
      static_root: root,
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

  defp serve_static_asset(conn, root, request_path) do
    with false <- String.contains?(request_path, <<0>>),
         rel <- String.trim_leading(request_path, "/"),
         false <- String.contains?(rel, ["\\", ":"]),
         candidate <- Path.expand(rel, root),
         true <- candidate == root or String.starts_with?(candidate, root <> "/"),
         true <- File.regular?(candidate) do
      mime_type = MIME.from_path(candidate) || "application/octet-stream"
      is_javascript = String.contains?(mime_type, "javascript")
      is_css = String.contains?(mime_type, "css")
      is_html = String.contains?(mime_type, "html")

      is_rofl_js_file = String.contains?(candidate, ".rofl.js")
      is_rofl_css_file = String.contains?(candidate, ".rofl.css")
      is_rofl_html_file = String.contains?(candidate, ".rofl.html")

      cdn_origin =
        case Map.get(conn.assigns, :cdn_port) do
          cdn_port when is_integer(cdn_port) and cdn_port != conn.port ->
            protocol = if conn.scheme == :https, do: "https", else: "http"
            cdn_host = conn.host || "localhost"
            "#{protocol}://#{cdn_host}:#{cdn_port}"

          _ ->
            ""
        end

      cond do
        is_javascript and is_rofl_js_file ->
          with {:ok, content} <- File.read(candidate),
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
              |> send_file(200, candidate)
          end

        is_css and is_rofl_css_file ->
          with {:ok, content} <- File.read(candidate),
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
              |> send_file(200, candidate)
          end

        is_html and is_rofl_html_file ->
          with {:ok, content} <- File.read(candidate),
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
              |> send_file(200, candidate)
          end

        true ->
          conn
          |> send_file(200, candidate)
      end
      |> halt()
    else
      _ ->
        send_resp(conn, 404, "File not found")
        |> halt()
    end
  end

  defp serve_index_html(conn, index_path) do
    cdn_origin =
      case Map.get(conn.assigns, :cdn_port) do
        cdn_port when is_integer(cdn_port) and cdn_port != conn.port ->
          protocol = if conn.scheme == :https, do: "https", else: "http"
          cdn_host = conn.host || "localhost"
          "#{protocol}://#{cdn_host}:#{cdn_port}"

        _ ->
          ""
      end

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
      conn
      |> assign(:outerfaces_served_index, true)
      |> put_resp_content_type("text/html")
      |> send_file(200, index_path)
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
