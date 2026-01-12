defmodule Outerfaces.Odd.Plugs.OddCDNRoflHTMLPlug do
  @moduledoc """
  Provides HTML transformation functions for rewriting [OUTERFACES_ODD_CDN] and
  [OUTERFACES_ODD_SPA] tokens in HTML src/href attributes.

  This module always emits rev-pinned URLs in the canonical format:
  - CDN: `<cdn_origin>/__rev/<rev>/cdn/<path>`
  - SPA: `/__rev/<rev>/spa/<path>`

  ## Examples

      # Unified proxy mode (cdn_origin = ""):
      html = "<script src=\"[OUTERFACES_ODD_CDN]/lib.js\"></script>"
      transform_html_cdn_tokens(html, conn, "") #=> "<script src=\"/__rev/abc123/cdn/lib.js\"></script>"

      # Direct CDN mode (cdn_origin = "http://localhost:60032"):
      html = "<script src=\"[OUTERFACES_ODD_CDN]/lib.js\"></script>"
      transform_html_cdn_tokens(html, conn, "http://localhost:60032") #=> "<script src=\"http://localhost:60032/__rev/abc123/cdn/lib.js\"></script>"

      # SPA tokens (always relative):
      html = "<script src=\"[OUTERFACES_ODD_SPA]/main.js\"></script>"
      transform_html_cdn_tokens(html, conn, "") #=> "<script src=\"/__rev/abc123/spa/main.js\"></script>"

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
  - `conn` - The Plug.Conn struct (used to get rev)
  - `cdn_origin` - Origin for CDN assets:
    - Unified proxy mode: "" (empty string, emits relative URLs)
    - Direct CDN mode: "http://localhost:60032" (full origin)

  ## Returns

  Transformed HTML string with:
  - All [OUTERFACES_ODD_CDN] and [OUTERFACES_ODD_SPA] tokens replaced
  - Rev meta tag injected in <head>
  """
  @spec transform_html_cdn_tokens(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  def transform_html_cdn_tokens(html_content, conn, cdn_origin \\ "") do
    # Short-circuit if no tokens present (performance optimization)
    if String.contains?(html_content, "[OUTERFACES_") do
      html_content
      |> replace_odd_cdn_tokens(conn, cdn_origin)
      |> replace_odd_spa_tokens(conn)
      |> inject_rev_meta_tag(conn)
    else
      html_content
    end
  end

  # Private Functions

  @spec replace_odd_cdn_tokens(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_odd_cdn_tokens(html_content, conn, cdn_origin) do
    rev = get_rev(conn)

    # Emit canonical rev-pinned URLs: <cdn_origin>/__rev/<rev>/cdn/<path>
    Regex.replace(@odd_cdn_attr_regex, html_content, fn _match, attr_start, prefix, path, quote ->
      "#{attr_start}#{prefix}#{cdn_origin}/__rev/#{rev}/cdn/#{path}#{quote}"
    end)
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
