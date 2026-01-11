defmodule Outerfaces.Odd.Plugs.OddCDNRoflCSSPlug do
  @moduledoc """
  Transforms CSS @import statements by rewriting CDN tokens.

  Supports both legacy and new token patterns:
  - [OUTERFACES_LOCAL_CDN] - DEPRECATED, aliased to [OUTERFACES_ODD_CDN]
  - [OUTERFACES_ODD_CDN] - Dual-mode: rev-pinned or absolute URLs

  Dual-mode behavior:
  - When conn.assigns.outerfaces_rev is present: rev-pinned URLs (/__rev/<rev>/cdn/...)
  - Otherwise: absolute URLs (http://localhost:60032/...)
  """

  # Regex to match CSS @import statements with the OUTERFACES_LOCAL_CDN marker
  @local_cdn_imports_regex ~r/@import\s+['"]([^'"]*)\[OUTERFACES_LOCAL_CDN\]\/([^'"]*)['"]\s*;?/i
  # New regex (supports both ODD and LOCAL for backward compatibility)
  @odd_cdn_imports_regex ~r/@import\s+['"]([^'"]*)\[OUTERFACES_(?:ODD|LOCAL)_CDN\]\/([^'"]*)['"]\s*;?/i

  @spec transform_css_cdn_imports(
          file_content :: String.t(),
          cdn_service_host_name :: String.t(),
          cdn_service_host_port :: integer(),
          url_scheme :: String.t()
        ) :: String.t()
  def transform_css_cdn_imports(
        file_content,
        cdn_service_host_name,
        cdn_service_host_port,
        url_scheme
      ) do
    cdn_base_url = "#{url_scheme}://#{cdn_service_host_name}:#{cdn_service_host_port}"
    transform_css_cdn_imports_with_base_url(file_content, cdn_base_url)
  end

  @spec transform_css_cdn_imports_with_base_url(
          file_content :: String.t(),
          cdn_base_url :: String.t()
        ) :: String.t()
  def transform_css_cdn_imports_with_base_url(file_content, cdn_base_url) do
    content = normalize_newlines(file_content)
    replace_cdn_imports_with_base_url(content, cdn_base_url)
  end

  @spec normalize_newlines(String.t()) :: String.t()
  def normalize_newlines(content), do: String.replace(content, "\r\n", "\n")

  @spec replace_cdn_imports(
          file_body :: String.t(),
          cdn_protocol :: String.t(),
          cdn_host :: String.t(),
          cdn_port :: integer()
        ) :: String.t()
  def replace_cdn_imports(
        file_body,
        cdn_protocol,
        cdn_host,
        cdn_port
      )
      when is_binary(file_body) and
             is_binary(cdn_protocol) and
             is_binary(cdn_host) and
             is_integer(cdn_port) do
    cdn_base_url = "#{cdn_protocol}://#{cdn_host}:#{cdn_port}"
    replace_cdn_imports_with_base_url(file_body, cdn_base_url)
  end

  # New function that works with base URL (supports both absolute and proxy-relative URLs)
  @spec replace_cdn_imports_with_base_url(file_body :: String.t(), cdn_base_url :: String.t()) ::
          String.t()
  def replace_cdn_imports_with_base_url(file_body, cdn_base_url)
      when is_binary(file_body) and is_binary(cdn_base_url) do
    Regex.replace(
      @local_cdn_imports_regex,
      file_body,
      "@import '#{cdn_base_url}/\\2'"
    )
  end

  # NEW: Rev-pinned transformation function

  @doc """
  Transforms CSS @import statements with rev-pinned URLs.

  This function always emits rev-pinned URLs in the canonical format:
  - CDN: `<cdn_origin>/__rev/<rev>/cdn/<path>`

  ## Parameters

  - `file_content` - CSS file content
  - `conn` - Plug.Conn struct (used to get rev)
  - `cdn_origin` - Origin for CDN assets:
    - Unified proxy mode: "" (empty string, emits relative URLs)
    - Direct CDN mode: "http://localhost:60032" (full origin)

  ## Returns

  Transformed CSS content with all tokens replaced

  ## Examples

      # Unified proxy mode (cdn_origin = "")
      transform_css_with_conn(content, conn, "")
      # Emits: /__rev/abc123/cdn/foo.css

      # Direct CDN mode (cdn_origin = "http://localhost:60032")
      transform_css_with_conn(content, conn, "http://localhost:60032")
      # Emits: http://localhost:60032/__rev/abc123/cdn/foo.css
  """
  @spec transform_css_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  def transform_css_with_conn(file_content, conn, cdn_origin) do
    # Short-circuit if no tokens present (performance optimization)
    if String.contains?(file_content, "[OUTERFACES_") do
      content = normalize_newlines(file_content)
      replace_odd_cdn_imports_with_conn(content, conn, cdn_origin)
    else
      file_content
    end
  end

  @spec replace_odd_cdn_imports_with_conn(String.t(), Plug.Conn.t(), String.t()) :: String.t()
  defp replace_odd_cdn_imports_with_conn(file_body, conn, cdn_origin) do
    rev = get_rev(conn)

    # Emit canonical rev-pinned URLs: <cdn_origin>/__rev/<rev>/cdn/<path>
    Regex.replace(@odd_cdn_imports_regex, file_body, fn _match, prefix, path ->
      "@import '#{prefix}#{cdn_origin}/__rev/#{rev}/cdn/#{path}'"
    end)
  end

  @spec get_rev(Plug.Conn.t()) :: String.t()
  defp get_rev(conn) do
    Map.get(conn.assigns, :outerfaces_rev) || Outerfaces.Rev.current_rev()
  end
end
