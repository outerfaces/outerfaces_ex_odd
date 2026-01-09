defmodule Outerfaces.Odd.Plugs.OddCDNRoflHTMLPlug do
  @moduledoc """
  Provides HTML transformation functions for rewriting [OUTERFACES_ODD_CDN] and
  [OUTERFACES_ODD_SPA] tokens in HTML src/href attributes.

  This module supports dual-mode operation:
  - Rev-pinned mode: Rewrites tokens to `/__rev/<rev>/cdn/...` or `/__rev/<rev>/spa/...`
  - Non-rev mode: Rewrites ODD_CDN tokens to absolute URLs (e.g., `http://localhost:60032/...`)

  The mode is determined by checking `conn.assigns.outerfaces_rev`. If present,
  rev-pinned mode is used; otherwise, absolute URLs are generated.

  ## Examples

      # Rev-pinned mode:
      html = "<script src=\"[OUTERFACES_ODD_SPA]/main.js\"></script>"
      transform_html_cdn_tokens(html, conn) #=> "<script src=\"/__rev/abc123/spa/main.js\"></script>"

      # Non-rev mode (no rev in assigns):
      html = "<script src=\"[OUTERFACES_ODD_CDN]/lib.js\"></script>"
      transform_html_cdn_tokens(html, conn) #=> "<script src=\"http://localhost:60032/lib.js\"></script>"

  """

  alias Outerfaces.Rev

  # Regex patterns for matching tokens in HTML attributes
  # Matches: src="[OUTERFACES_ODD_CDN]/path" or href='[OUTERFACES_ODD_CDN]/path'
  @odd_cdn_attr_regex ~r/((?:src|href)=["'])([^"']*)\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^"']*)(["'])/i
  @odd_spa_attr_regex ~r/((?:src|href)=["'])([^"']*)\[OUTERFACES_ODD_SPA\]\/([^"']*)(["'])/i

  # Regex for injecting rev meta tag (finds </head> or <body> tag)
  @head_close_regex ~r{</head>}i
  @body_open_regex ~r{<body[^>]*>}i

  @doc """
  Transforms HTML content by rewriting ODD_CDN and ODD_SPA tokens in src/href attributes
  and injecting a rev meta tag.

  ## Parameters

  - `html_content` - The HTML content to transform
  - `conn` - The Plug.Conn struct (used to determine mode and get configuration)
  - `cdn_base_url` - (optional) Base URL for CDN in absolute mode (e.g., "http://localhost:8011")

  ## Returns

  Transformed HTML string with:
  - All [OUTERFACES_ODD_CDN] and [OUTERFACES_ODD_SPA] tokens replaced
  - Rev meta tag injected in <head>
  """
  @spec transform_html_cdn_tokens(String.t(), Plug.Conn.t(), String.t() | nil) :: String.t()
  def transform_html_cdn_tokens(html_content, conn, cdn_base_url \\ nil) do
    html_content
    |> replace_odd_cdn_tokens(conn, cdn_base_url)
    |> replace_odd_spa_tokens(conn)
    |> inject_rev_meta_tag(conn)
  end

  # Private Functions

  @spec replace_odd_cdn_tokens(String.t(), Plug.Conn.t(), String.t() | nil) :: String.t()
  defp replace_odd_cdn_tokens(html_content, conn, cdn_base_url) do
    rev = get_rev(conn)

    # For CDN tokens, we always need to point to the CDN server
    # If cdn_base_url is provided (separate CDN port), use absolute URL with rev
    # Otherwise, use relative rev-pinned URL
    case cdn_base_url do
      nil ->
        # Same origin - use relative rev-pinned URL
        Regex.replace(@odd_cdn_attr_regex, html_content, fn _match,
                                                            attr_start,
                                                            prefix,
                                                            path,
                                                            quote ->
          "#{attr_start}#{prefix}/__rev/#{rev}/cdn/#{path}#{quote}"
        end)

      base_url ->
        # Separate CDN port - use absolute URL with rev
        Regex.replace(@odd_cdn_attr_regex, html_content, fn _match,
                                                            attr_start,
                                                            prefix,
                                                            path,
                                                            quote ->
          "#{attr_start}#{prefix}#{base_url}/__rev/#{rev}/cdn/#{path}#{quote}"
        end)
    end
  end

  @spec replace_odd_spa_tokens(String.t(), Plug.Conn.t()) :: String.t()
  defp replace_odd_spa_tokens(html_content, conn) do
    # ODD_SPA is always rev-pinned
    rev = get_rev(conn)

    Regex.replace(@odd_spa_attr_regex, html_content, fn _match, attr_start, prefix, path, quote ->
      "#{attr_start}#{prefix}/__rev/#{rev}/spa/#{path}#{quote}"
    end)
  end

  @spec inject_rev_meta_tag(String.t(), Plug.Conn.t()) :: String.t()
  defp inject_rev_meta_tag(html_content, conn) do
    rev = get_rev(conn)
    meta_tag = "  <meta name=\"outerfaces-rev\" content=\"#{rev}\">\n"

    cond do
      Regex.match?(@head_close_regex, html_content) ->
        # Inject before </head>
        Regex.replace(@head_close_regex, html_content, "#{meta_tag}</head>", global: false)

      Regex.match?(@body_open_regex, html_content) ->
        # No </head> found, inject after <body>
        Regex.replace(
          @body_open_regex,
          html_content,
          fn match ->
            "#{match}\n#{meta_tag}"
          end,
          global: false
        )

      true ->
        # No </head> or <body> found, prepend to content
        meta_tag <> html_content
    end
  end

  @spec get_rev(Plug.Conn.t()) :: String.t()
  defp get_rev(conn) do
    Map.get(conn.assigns, :outerfaces_rev) || Rev.current_rev()
  end
end
